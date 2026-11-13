using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;

namespace RomChecker.Web.Features.Storage;

public static class BatchEndpoints
{
    public static void MapBatches(this WebApplication app)
    {
        var api = app.MapGroup("/internal");
        api.MapGet("/batches", (BatchStore store) => store.All());
        api.MapPost("/batches", async (BatchRequest request, HttpContext context, BatchStore store) =>
        {
            var key = context.Request.Headers["Idempotency-Key"].ToString();
            if (key.Length == 0) return store.Create(request.Name);
            var gate = store.Gate(key);
            await gate.WaitAsync(context.RequestAborted);
            try { return store.Create(request.Name, key); }
            finally { gate.Release(); }
        });
        api.MapGet("/batches/{id}", (string id, BatchStore store) => store.Get(id));
        api.MapPost("/batches/{id}/uploads", async (string id, UploadRequest request, BatchStore store, StorageOptions options) =>
        {
            var gate = store.Gate(id);
            await gate.WaitAsync();
            try
            {
                var batch = store.Get(id);
                store.Available(batch, "uploading");
                var path = StoragePaths.Relative(request.Path);
                if (request.Size < 0) throw new RequestException("Invalid file size.");
                if (request.Size > options.MaxBytes) throw new RequestException("File size exceeds storage limits.", 413);
                var fileId = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(path.ToUpperInvariant())))[..32].ToLowerInvariant();
                var existing = BatchStore.Read<UploadState>(store.UploadPath(id, fileId));
                if (existing is not null)
                {
                    if (existing.Path != path || existing.Size != request.Size || existing.Modified != request.Modified)
                        throw new RequestException("A different file already uses this path. Create a new batch.", 409);
                    var target = StoragePaths.Resolve(store.Tree(id, "originals"), existing.Path);
                    if (!existing.Complete && File.Exists(target))
                    {
                        if (new FileInfo(target).Length != existing.Size) throw new RequestException("Stored upload has changed.", 409);
                        existing = existing with { Complete = true, Offset = existing.Size };
                        BatchStore.Write(store.UploadPath(id, fileId), existing);
                    }
                    var offset = existing.Complete ? existing.Size : File.Exists(store.Part(id, fileId)) ? new FileInfo(store.Part(id, fileId)).Length : 0;
                    return existing with { Offset = offset };
                }
                if (batch.Files >= options.MaxFiles || batch.Bytes > options.MaxBytes - request.Size)
                    throw new RequestException("Batch exceeds the configured file or byte limit.", 413);
                store.Capacity(request.Size);
                var upload = new UploadState(fileId, path, request.Size, request.Modified, 0, false);
                BatchStore.Write(store.UploadPath(id, fileId), upload);
                store.Save(batch with { Files = batch.Files + 1, Bytes = batch.Bytes + request.Size });
                return upload;
            }
            finally { gate.Release(); }
        });
        api.MapPut("/batches/{id}/uploads/{fileId}", async (string id, string fileId, long offset, HttpContext context, BatchStore store) =>
        {
            if (context.Request.ContentLength is not long length || length < 0 || length > StorageOptions.ChunkBytes)
                throw new RequestException("Use a bounded upload chunk with Content-Length.", 413);
            var gate = store.Gate(id);
            await gate.WaitAsync(context.RequestAborted);
            try
            {
                store.Available(store.Get(id), "uploading");
                var upload = store.Upload(id, fileId);
                if (upload.Complete) return Results.Ok(upload);
                var part = store.Part(id, fileId);
                await using (var output = new FileStream(part, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None, 65536, true))
                {
                    if (offset != output.Length || length > upload.Size - offset)
                        throw new RequestException("Upload offset changed. Resume this file to read its current offset.", 409);
                    store.Capacity(length);
                    output.Position = offset;
                    var buffer = new byte[65536];
                    long received = 0;
                    try
                    {
                        while (received < length)
                        {
                            var count = await context.Request.Body.ReadAsync(buffer.AsMemory(0, (int)Math.Min(buffer.Length, length - received)), context.RequestAborted);
                            if (count == 0) throw new RequestException("Upload chunk ended early.");
                            await output.WriteAsync(buffer.AsMemory(0, count), context.RequestAborted);
                            received += count;
                        }
                        await output.FlushAsync(context.RequestAborted);
                    }
                    catch { output.SetLength(offset); throw; }
                    upload = upload with { Offset = output.Length };
                }
                if (upload.Offset == upload.Size)
                {
                    var target = StoragePaths.Resolve(store.Tree(id, "originals"), upload.Path);
                    Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                    File.Move(part, target);
                    upload = upload with { Complete = true };
                }
                BatchStore.Write(store.UploadPath(id, fileId), upload);
                return Results.Ok(upload);
            }
            finally { gate.Release(); }
        });
        api.MapPost("/batches/{id}/prepare", async (string id, BatchStore store, BatchTransfers transfers) =>
        {
            var gate = store.Gate(id);
            if (!await gate.WaitAsync(0)) throw new RequestException("Batch is busy transferring or downloading. Retry shortly.", 409);
            try { transfers.Prepare(id); return Results.Accepted(); }
            finally { gate.Release(); }
        });
        api.MapGet("/batches/{id}/capacity", (string id, BatchStore store, StorageOptions options) =>
        {
            var batch = store.Get(id);
            return new { availableBytes = new DriveInfo(options.Root).AvailableFreeSpace, reserveBytes = options.ReserveBytes,
                preparationBytes = batch.Prepared ? 0 : batch.Bytes, originalBytes = batch.Bytes,
                processingBytes = batch.Prepared ? StoragePaths.Files(store.Tree(id, "processed")).Sum(file => new FileInfo(file.Full).Length) : 0 };
        });
        api.MapPost("/batches/{id}/rename", async (string id, BatchRequest request, BatchStore store) =>
        {
            if (string.IsNullOrWhiteSpace(request.Name) || request.Name.Length > 120) throw new RequestException("Choose a collection name (1-120 characters).");
            var gate = store.Gate(id); await gate.WaitAsync();
            try
            {
                var batch = store.Get(id); store.Available(batch, "uploading", "ready", "failed");
                store.Save(batch with { Name = request.Name.Trim() });
                return Results.NoContent();
            }
            finally { gate.Release(); }
        });
        api.MapPost("/batches/{id}/lease", async (string id, LeaseRequest request, BatchStore store) =>
        {
            StoragePaths.Id(request.JobId);
            var gate = store.Gate(id);
            if (!await gate.WaitAsync(0)) throw new RequestException("Batch is busy transferring or downloading. Retry shortly.", 409);
            try
            {
                var batch = store.Get(id);
                store.Available(batch, "ready");
                store.Save(batch with { Status = "processing", Lease = request.JobId });
                return Results.NoContent();
            }
            finally { gate.Release(); }
        });
        api.MapPost("/batches/{id}/release", async (string id, LeaseRequest request, BatchStore store) =>
        {
            var gate = store.Gate(id); await gate.WaitAsync();
            try
            {
                var batch = store.Get(id);
                if (batch.Lease != request.JobId) throw new RequestException("Processing lease does not match.", 409);
                store.Save(batch with { Status = "ready", Lease = null });
                return Results.NoContent();
            }
            finally { gate.Release(); }
        });
        api.MapDelete("/batches/{id}", async (string id, BatchStore store) =>
        {
            var gate = store.Gate(id);
            if (!await gate.WaitAsync(0)) throw new RequestException("Batch is busy transferring or downloading. Retry shortly.", 409);
            try
            {
                store.Available(store.Get(id), "uploading", "ready", "failed");
                var directory = store.DirectoryFor(id);
                foreach (var _ in StoragePaths.Files(directory)) { }
                Directory.Delete(directory, true);
                return Results.NoContent();
            }
            finally { gate.Release(); }
        });
        api.MapGet("/batches/{id}/browse", async (string id, string? tree, string? path, int? page, BatchStore store) =>
        {
            var gate = store.Gate(id); await gate.WaitAsync();
            try
            {
                var batch = store.Get(id); store.Available(batch, "uploading", "ready", "failed");
                var root = store.Tree(id, tree ?? "processed");
                var relative = StoragePaths.Relative(path ?? "", true);
                var directory = StoragePaths.Resolve(root, relative, true);
                if (!Directory.Exists(directory)) throw new RequestException("Folder not found.", 404);
                var number = Math.Clamp(page ?? 1, 1, 10000);
                var entries = Directory.EnumerateFileSystemEntries(directory)
                    .OrderBy(p => p, StringComparer.Ordinal).Skip((number - 1) * 200).Take(201).ToArray();
                var result = entries.Take(200).Select(entry =>
                {
                    StoragePaths.AssertNoLinks(root, entry);
                    return new StorageEntry(Path.GetFileName(entry), Path.GetRelativePath(root, entry).Replace(Path.DirectorySeparatorChar, '/'),
                        Directory.Exists(entry), File.Exists(entry) ? new FileInfo(entry).Length : 0);
                }).ToArray();
                return new StorageListing(relative, result, number, entries.Length > 200);
            }
            finally { gate.Release(); }
        });
        api.MapGet("/batches/{id}/download", async (string id, string? path, HttpContext context, BatchStore store, StorageOptions options) =>
        {
            var gate = store.Gate(id); await gate.WaitAsync(context.RequestAborted);
            try
            {
                store.Available(store.Get(id), "ready");
                var root = store.Tree(id, "processed");
                var relative = StoragePaths.Relative(path ?? "", true);
                var full = StoragePaths.Resolve(root, relative, true);
                if (File.Exists(full))
                {
                    context.Response.ContentType = "application/octet-stream";
                    context.Response.Headers.ContentDisposition = $"attachment; filename*=UTF-8''{Uri.EscapeDataString(Path.GetFileName(full))}";
                    await context.Response.SendFileAsync(full, context.RequestAborted);
                    return;
                }
                // Build a bounded metadata manifest before sending headers; ROM bytes are streamed, not buffered.
                var files = StoragePaths.Files(root, relative).Take(options.MaxFiles + 1).ToArray();
                if (files.Length > options.MaxFiles) throw new RequestException("Folder exceeds the ZIP file-count limit.", 413);
                context.Response.ContentType = "application/zip";
                context.Response.Headers.ContentDisposition = $"attachment; filename=\"roms-{id}.zip\"";
                using var zip = new ZipArchive(context.Response.Body, ZipArchiveMode.Create, true);
                foreach (var file in files)
                {
                    context.RequestAborted.ThrowIfCancellationRequested();
                    StoragePaths.AssertNoLinks(root, file.Full);
                    var entry = zip.CreateEntry(file.Relative, CompressionLevel.NoCompression);
                    await using var source = File.OpenRead(file.Full);
                    await using var output = entry.Open();
                    await source.CopyToAsync(output, context.RequestAborted);
                }
            }
            finally { gate.Release(); }
        });
    }
}
