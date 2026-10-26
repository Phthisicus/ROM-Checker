namespace RomChecker.Web.Features.Storage;

public static class SmbEndpoints
{
    public static void MapSmb(this WebApplication app)
    {
        var api = app.MapGroup("/internal");
        api.MapPost("/smb", async (SmbConnectionRequest request, SmbSessions sessions) => new { id = await sessions.Connect(request) });
        api.MapDelete("/smb/{id}", async (string id, SmbSessions sessions) => { await sessions.Disconnect(id); return Results.NoContent(); });
        api.MapGet("/smb/{id}/browse", async (string id, string? path, int? page, SmbSessions sessions) =>
        {
            var session = sessions.Get(id);
            if (!await session.Gate.WaitAsync(0)) throw new RequestException("SMB connection is busy.", 409);
            try
            {
                var number = Math.Clamp(page ?? 1, 1, 10000);
                var entries = await Task.Run(() => session.Browse(path ?? ""));
                return new StorageListing(path ?? "", entries.Skip((number - 1) * 200).Take(200).ToArray(), number, entries.Length > number * 200);
            }
            finally { session.Gate.Release(); }
        });
        api.MapPost("/batches/{id}/smb-import", async (string id, SmbImportRequest request, BatchStore store,
            BatchTransfers transfers, SmbSessions sessions, StorageOptions options) =>
        {
            if (request.Paths is not { Length: > 0 and <= 1000 }) throw new RequestException("Select between 1 and 1000 SMB items.");
            foreach (var path in request.Paths) StoragePaths.Relative(path);
            var gate = store.Gate(id); await gate.WaitAsync();
            try
            {
                var batch = store.Get(id);
                store.Available(batch, "uploading");
                if (batch.Files != 0 || StoragePaths.Files(store.Tree(id, "originals")).Any())
                    throw new RequestException("SMB imports require an empty batch; create a separate batch for this import.", 409);
                var session = sessions.Get(request.ConnectionId);
                if (!await session.Gate.WaitAsync(0)) throw new RequestException("SMB connection is busy.", 409);
                store.Save(batch with { Status = "importing", Error = null });
                try
                {
                    transfers.Enqueue(id, async token =>
                    {
                        try
                        {
                            var manifest = new Dictionary<string, StorageEntry>(StringComparer.OrdinalIgnoreCase);
                            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                            var pending = new Queue<StorageEntry>();
                            foreach (var group in request.Paths.Distinct(StringComparer.OrdinalIgnoreCase)
                                .GroupBy(path => path.Contains('/') ? path[..path.LastIndexOf('/')] : ""))
                            {
                                var entries = session.Browse(group.Key).ToDictionary(e => e.Path, StringComparer.OrdinalIgnoreCase);
                                foreach (var path in group)
                                    pending.Enqueue(entries.TryGetValue(path, out var entry) ? entry
                                        : throw new RequestException("SMB selection is no longer available.", 409));
                            }
                            long bytes = 0;
                            while (pending.TryDequeue(out var entry))
                            {
                                token.ThrowIfCancellationRequested();
                                if (!visited.Add(entry.Path)) continue;
                                if (visited.Count > options.MaxFiles * 2L) throw new RequestException("SMB selection exceeds directory limits.", 413);
                                if (entry.Directory)
                                    foreach (var child in session.Browse(entry.Path)) pending.Enqueue(child);
                                else if (!manifest.ContainsKey(entry.Path))
                                {
                                    if (manifest.Count >= options.MaxFiles || entry.Size < 0 || entry.Size > options.MaxBytes - bytes)
                                        throw new RequestException("SMB selection exceeds the configured file or byte limit.", 413);
                                    manifest.Add(entry.Path, entry); bytes += entry.Size;
                                }
                            }
                            if (manifest.Count == 0) throw new RequestException("SMB selection contains no files.");
                            store.Capacity(bytes);
                            foreach (var entry in manifest.Values)
                            {
                                var part = Path.Combine(store.DirectoryFor(id), "parts", Guid.NewGuid().ToString("N"));
                                await session.Copy(entry, part, store, token);
                                var destination = StoragePaths.Resolve(store.Tree(id, "originals"), entry.Path);
                                Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
                                File.Move(part, destination);
                                var progress = store.Get(id);
                                store.Save(progress with { Files = progress.Files + 1, Bytes = progress.Bytes + entry.Size });
                            }
                            store.Save(store.Get(id) with { Status = "uploading" });
                        }
                        finally { session.Used = DateTimeOffset.UtcNow; session.Gate.Release(); }
                    });
                }
                catch { session.Gate.Release(); store.Save(batch); throw; }
                return Results.Accepted();
            }
            finally { gate.Release(); }
        });
    }
}
