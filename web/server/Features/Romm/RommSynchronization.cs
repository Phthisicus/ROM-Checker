using System.Security.Cryptography;
using System.Text.Json;
using RomChecker.Web.Features.Catalog;

namespace RomChecker.Web.Features.Romm;

public sealed partial class RommService
{
    public static RommSyncSettings ValidateSync(RommSyncSettings settings, RommPlatformMapping[] mappings)
    {
        var ids = settings.PlatformIds ?? [];
        if (settings.IntervalMinutes is < 1 or > 1440 || ids.Length > 1000 || ids.Any(id => id < 1)
            || ids.Any(id => !mappings.Any(mapping => mapping.PlatformId == id)))
            throw new RequestException("Sync interval must be 1-1440 minutes and inbound platforms must have saved mappings.");
        if (settings.AutoImport && ids.Length == 0)
            throw new RequestException("Select at least one mapped RomM platform before enabling automatic imports.");
        return settings with { PlatformIds = ids.Distinct().Order().ToArray() };
    }

    private void RequireInboundPolicy(string connectionId, int platform)
    {
        var current = store.Config();
        if (current.ConnectionId != connectionId || current.Sync is not { AutoImport: true } sync
            || !(sync.PlatformIds ?? []).Contains(platform)
            || !(current.PlatformMappings ?? []).Any(mapping => mapping.PlatformId == platform))
            throw new RequestException("Automatic inbound import was disabled or this platform is no longer selected.", 409);
    }

    public async Task<RommJob> QueueSync(bool confirm)
    {
        if (!confirm) throw new RequestException("Confirm running synchronization with the saved settings.");
        await submissions.WaitAsync();
        try { return QueueSyncCore(Configured()); }
        finally { submissions.Release(); }
    }
    private RommJob QueueSyncCore(RommConfig config)
    {
        var settings = config.Sync ?? new();
        if (!settings.AutoImport && !settings.RefreshMetadata)
            throw new RequestException("Enable and save inbound discovery or scheduled metadata refresh first.", 409);
        if (store.Jobs().Any(job => job.Kind == "sync" && job.ConnectionId == config.ConnectionId
            && job.Status is "queued" or "running"))
            throw new RequestException("A RomM synchronization pass is already pending.", 409);
        var job = new RommJob(Guid.NewGuid().ToString("N"), "sync", "queued", DateTimeOffset.UtcNow,
            null, null, config.ConnectionId, [], Automatic: true);
        store.Save(job);
        return job;
    }
    private async Task ScheduleSync()
    {
        await submissions.WaitAsync();
        try
        {
            var config = store.Config();
            var settings = config.Sync ?? new();
            if (!settings.AutoImport && !settings.RefreshMetadata) return;
            var previous = store.Jobs().Where(job => job.ConnectionId == config.ConnectionId && job.Kind == "sync")
                .OrderByDescending(job => job.Created).FirstOrDefault();
            if (previous is not null && (previous.Status is "queued" or "running"
                || DateTimeOffset.UtcNow - (previous.Finished ?? previous.Created) < TimeSpan.FromMinutes(settings.IntervalMinutes)))
                return;
            QueueSyncCore(config);
        }
        finally { submissions.Release(); }
    }

    private async Task<RommItem[]> Reconcile(RommConfig config, CancellationToken token)
    {
        var settings = config.Sync ?? new();
        if (!settings.AutoImport && !settings.RefreshMetadata)
            throw new RequestException("Inbound sync and metadata refresh were disabled.", 409);
        var known = store.Remotes(config.ConnectionId).ToDictionary(state => state.RommId);
        var links = store.Links().Where(link => link.ConnectionId == config.ConnectionId && link.RommId is > 0).ToArray();
        var ids = settings.RefreshMetadata ? known.Keys.Concat(links.Select(link => link.RommId!.Value)).ToHashSet()
            : known.Values.Where(state => settings.AutoImport && (settings.PlatformIds ?? []).Contains(state.Snapshot?.PlatformId ?? 0))
                .Select(state => state.RommId).ToHashSet();
        if (settings.AutoImport)
        {
            var seen = new HashSet<int>();
            for (var offset = 0; ;)
            {
                if (offset >= 100000) throw new RequestException("RomM discovery exceeds 100000 games. Narrow the remote library before continuing.", 409);
                var response = await client.Get(config, $"api/roms?limit=100&offset={offset}&order_by=id&order_dir=asc", token);
                var page = RommClient.Array(response);
                if (page.Length == 0) break;
                foreach (var rom in page)
                {
                    var id = RommClient.Number(rom, "id");
                    if (id < 1 || !seen.Add(id))
                        throw new RequestException("RomM pagination repeated or returned invalid game IDs. No deletions were inferred; retry after its library settles.", 409);
                    if ((settings.PlatformIds ?? []).Contains(RommClient.Number(rom, "platform_id"))) ids.Add(id);
                }
                offset += page.Length;
                if (response.ValueKind == JsonValueKind.Object && response.TryGetProperty("total", out var total)
                    && total.TryGetInt32(out var count))
                {
                    if (offset >= count) break;
                }
                else if (page.Length < 100) break;
            }
        }
        var results = new List<RommItem>();
        foreach (var id in ids.Order())
        {
            token.ThrowIfCancellationRequested();
            var current = store.Config();
            if (current.ConnectionId != config.ConnectionId) throw new RequestException("RomM connection changed.", 409);
            var currentSettings = current.Sync ?? new();
            if (!currentSettings.AutoImport && !currentSettings.RefreshMetadata)
                throw new RequestException("Synchronization was disabled; no further changes were applied.", 409);
            var state = known.GetValueOrDefault(id);
            var references = links.Where(link => link.RommId == id).ToArray();
            var existingIds = state?.EntryIds is { Length: > 0 } saved ? saved : references.Select(link => link.EntryId).ToArray();
            var name = state?.Name ?? $"RomM #{id}";
            var baseline = state?.Snapshot;
            try
            {
                if (store.Jobs().Any(job => job.ConnectionId == config.ConnectionId && job.Kind != "sync"
                    && job.Status is "queued" or "running" or "awaiting-import" or "awaiting-scan"
                    && job.Items.Any(item => item.RommId == id || existingIds.Contains(item.EntryId))))
                {
                    results.Add(new("remote:" + id, "pending", RommId: id));
                    continue;
                }
                var remote = await client.Get(config, $"api/roms/{id}", token);
                if (RommClient.Number(remote, "id") != id) throw new RequestException("RomM returned a different game ID.", 409);
                name = RommClient.Text(remote, "name");
                if (state?.Status == "ignored" && state.IgnoredFingerprint == RommIdentity.ObservedVersion(remote))
                {
                    results.Add(new("remote:" + id, "ignored", RommId: id));
                    continue;
                }
                var snapshot = RommIdentity.Snapshot(remote);
                currentSettings = store.Config().Sync ?? new();
                var inbound = currentSettings.AutoImport && (currentSettings.PlatformIds ?? []).Contains(snapshot.PlatformId);
                if (!currentSettings.RefreshMetadata && !inbound) continue;
                if (baseline is null && references.Length > 0)
                    baseline = RommIdentity.Snapshot(references[0].Metadata);
                if (state?.IgnoredFingerprint == snapshot.Fingerprint)
                {
                    results.Add(new("remote:" + id, "ignored", RommId: id));
                    continue;
                }
                if (baseline is not null && baseline.Fingerprint != snapshot.Fingerprint)
                    throw new RequestException("Remote files, paths or platform changed. Keep the local copy or explicitly import the new version separately.", 409);
                if (existingIds.Length > 0)
                {
                    var entries = existingIds.Select(catalog.Get).ToArray();
                    var savedLinks = links.Where(link => existingIds.Contains(link.EntryId)).ToArray();
                    if (entries.Any(entry => entry.Missing || !savedLinks.Any(link => link.EntryId == entry.Id && link.Fingerprint == entry.SHA256)))
                        throw new RequestException("Local content changed or is missing. Restore or recheck the local files before refreshing this link.", 409);
                    await BindRemote(config, id, remote, snapshot, entries, token, automatic: true,
                        metadataOnly: currentSettings.RefreshMetadata, refreshMetadata: currentSettings.RefreshMetadata);
                }
                else
                {
                    if (!inbound) continue;
                    var duplicate = await FindLocalCopy(config, snapshot, token);
                    if (duplicate is not null) await BindRemote(config, id, remote, snapshot, duplicate, token, automatic: true);
                    else
                    {
                        var history = store.Jobs().Where(job => job.ConnectionId == config.ConnectionId && job.Kind == "import").ToArray();
                        if (history.Any(job => job.Items.Any(item => item.RommId == id)))
                            throw new RequestException("This game has a previous import. Retry or review that import; automatic sync will not create another copy.", 409);
                        if (history.Any(job => job.Status is "queued" or "running" or "awaiting-import"
                            && job.Items.Any(item => item.RemoteSnapshot?.ContentKey == snapshot.ContentKey)))
                        {
                            results.Add(new("remote:" + id, "pending", RommId: id));
                            continue;
                        }
                        await QueueImport([id], true, automatic: true, token: token);
                        results.Add(new("remote:" + id, "queued-import", RommId: id));
                        continue;
                    }
                }
                results.Add(new("remote:" + id, "linked", RommId: id));
            }
            catch (RequestException ex) when (ex.Status is 404 or 409)
            {
                if (ex.Status == 404 && state?.IgnoredFingerprint == "missing" && state.Status == "ignored")
                {
                    results.Add(new("remote:" + id, "ignored", RommId: id));
                    continue;
                }
                RecordConflict(config, id, name, baseline, existingIds, ex.Message);
                results.Add(new("remote:" + id, "failed", ex.Message, id));
            }
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
            {
                RecordConflict(config, id, name, baseline, existingIds, "A linked local file is missing. No deletion was propagated.");
                results.Add(new("remote:" + id, "failed", "A linked local file is missing.", id));
            }
        }
        return results.ToArray();
    }

    private void RecordConflict(RommConfig config, int id, string name, RommRemoteSnapshot? snapshot, string[] ids, string detail)
    {
        store.Save(new RommRemoteState(config.ConnectionId, id, name, snapshot, "conflict", detail, DateTimeOffset.UtcNow, ids));
        foreach (var link in store.Links().Where(link => link.ConnectionId == config.ConnectionId && link.RommId == id))
        {
            if (link.Status == "conflict") continue;
            store.Save(link with { Status = "conflict" });
            if (catalog.Entries().Any(entry => entry.Id == link.EntryId))
                catalog.UpdateSync(link.EntryId, "conflict", detail);
        }
    }

    private async Task<string> LocalSHA1(CatalogEntry entry, CancellationToken token)
    {
        if (entry.Missing) throw new RequestException("A linked local file is missing.", 409);
        var path = catalog.PhysicalPath(entry);
        await using var input = File.OpenRead(path);
        using var sha1 = IncrementalHash.CreateHash(HashAlgorithmName.SHA1);
        using var sha256 = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[65536];
        long length = 0;
        int read;
        while ((read = await input.ReadAsync(buffer, token)) > 0)
        {
            sha1.AppendData(buffer, 0, read);
            sha256.AppendData(buffer, 0, read);
            length += read;
        }
        if (length != entry.Length || !string.Equals(Convert.ToHexString(sha256.GetHashAndReset()), entry.SHA256, StringComparison.OrdinalIgnoreCase))
            throw new RequestException("Local bytes changed. Refresh and recheck the local library before synchronization.", 409);
        return Convert.ToHexString(sha1.GetHashAndReset());
    }
    private async Task<CatalogEntry[]?> FindLocalCopy(RommConfig config, RommRemoteSnapshot snapshot, CancellationToken token)
    {
        var consoles = (config.PlatformMappings ?? []).Where(mapping => mapping.PlatformId == snapshot.PlatformId).Select(mapping => mapping.Console).ToHashSet();
        foreach (var group in catalog.Entries().GroupBy(GroupKey))
        {
            var entries = group.ToArray();
            if (entries.Any(entry => entry.Missing || !consoles.Contains(entry.Console))
                || entries.Length != snapshot.Files.Length || entries.Sum(entry => entry.Length) != snapshot.Files.Sum(file => file.Size)) continue;
            var files = new List<RommFileIdentity>();
            foreach (var entry in entries) files.Add(new(entry.FileName, entry.Length, await LocalSHA1(entry, token)));
            if (RommIdentity.ContentKey(snapshot.PlatformId, files) == snapshot.ContentKey) return entries;
        }
        return null;
    }
    private async Task BindRemote(RommConfig config, int id, JsonElement remote, RommRemoteSnapshot snapshot,
        CatalogEntry[] entries, CancellationToken token, bool automatic = false, bool metadataOnly = false,
        bool refreshMetadata = true)
    {
        var files = new List<RommFileIdentity>();
        foreach (var entry in entries) files.Add(new(entry.FileName, entry.Length, await LocalSHA1(entry, token)));
        if (RommIdentity.ContentKey(snapshot.PlatformId, files) != snapshot.ContentKey)
            throw new RequestException("The complete local game no longer matches RomM's file hashes.", 409);
        await submissions.WaitAsync(token);
        try
        {
            var current = store.Config();
            if (current.ConnectionId != config.ConnectionId) throw new RequestException("The RomM connection changed.", 409);
            if (automatic)
            {
                if (metadataOnly)
                {
                    if (current.Sync?.RefreshMetadata != true)
                        throw new RequestException("Scheduled metadata refresh was disabled.", 409);
                }
                else RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
            }
            if (entries.Any(entry => catalog.Get(entry.Id).SHA256 != entry.SHA256))
                throw new RequestException("Local content changed during synchronization. Recheck before linking.", 409);
            var previous = store.Links().Where(link => link.ConnectionId == config.ConnectionId).ToDictionary(link => link.EntryId);
            foreach (var entry in entries)
            {
                previous.TryGetValue(entry.Id, out var link);
                if (link is not null && link.RommId != id) continue;
                var metadata = refreshMetadata || link is null ? remote : link.Metadata;
                store.Save(new RommLink(entry.Id, id, "linked", metadata, DateTimeOffset.UtcNow, entry.SHA256, config.ConnectionId, link?.ExportPath));
                if (entry.SyncStatus != "linked") catalog.UpdateSync(entry.Id, "linked", $"Linked exact content to RomM #{id}; verification is unchanged.");
                if (link is null || link.RommId != id || link.Status != "linked" || link.Metadata.GetRawText() != metadata.GetRawText())
                    catalog.Audit(entry.Id, refreshMetadata ? "romm-metadata" : "romm-linked",
                        refreshMetadata ? $"Refreshed descriptive metadata from RomM #{id}; verification is unchanged."
                            : $"Rechecked exact content against RomM #{id}; descriptive metadata and verification are unchanged.");
            }
            store.Save(new RommRemoteState(config.ConnectionId, id, RommClient.Text(remote, "name"), snapshot, "linked",
                null, DateTimeOffset.UtcNow, entries.Select(entry => entry.Id).ToArray()));
        }
        finally { submissions.Release(); }
    }
    private async Task<JsonElement> LinkedMetadata(RommConfig config, CatalogEntry entry, RommLink link, CancellationToken token)
    {
        var id = link.RommId!.Value;
        var state = store.Remotes(config.ConnectionId).FirstOrDefault(state => state.RommId == id);
        if (state?.Status is "conflict" or "ignored")
            throw new RequestException("Recheck or resolve this RomM synchronization conflict before refreshing metadata.", 409);
        var baseline = state?.Snapshot;
        try
        {
            baseline ??= RommIdentity.Snapshot(link.Metadata);
            var remote = await client.Get(config, $"api/roms/{id}", token);
            if (RommClient.Number(remote, "id") != id) throw new RequestException("RomM returned a different game ID.", 409);
            var snapshot = RommIdentity.Snapshot(remote);
            if (baseline.Fingerprint != snapshot.Fingerprint)
                throw new RequestException("Remote files, paths or platform changed. Recheck synchronization before refreshing metadata.", 409);
            var sha1 = await LocalSHA1(entry, token);
            if (entry.SHA256 != link.Fingerprint || !snapshot.Files.Any(file => file.Size == entry.Length && file.SHA1 == sha1))
                throw new RequestException("Local content no longer matches its existing RomM link.", 409);
            return remote;
        }
        catch (RequestException ex) when (ex.Status is 404 or 409)
        {
            var ids = state?.EntryIds ?? store.Links().Where(value => value.ConnectionId == config.ConnectionId && value.RommId == id)
                .Select(value => value.EntryId).ToArray();
            RecordConflict(config, id, state?.Name ?? entry.FileName, baseline, ids, ex.Message);
            throw;
        }
    }
    public async Task ResolveConflict(int id, RommConflictAction request, CancellationToken token)
    {
        if (!request.Confirm || request.Action != "keep-local") throw new RequestException("Confirm keeping the local copy.");
        await submissions.WaitAsync(token);
        try
        {
            var config = Configured();
            if (store.Jobs().Any(job => job.ConnectionId == config.ConnectionId && job.Status is "queued" or "running" or "awaiting-import" or "awaiting-scan"))
                throw new RequestException("Wait for pending RomM work before resolving conflicts.", 409);
            var state = store.Remotes(config.ConnectionId).FirstOrDefault(state => state.RommId == id && state.Status == "conflict")
                ?? throw new RequestException("Synchronization conflict not found.", 404);
            string fingerprint;
            try { fingerprint = RommIdentity.ObservedVersion(await client.Get(config, $"api/roms/{id}", token)); }
            catch (RequestException ex) when (ex.Status == 404) { fingerprint = "missing"; }
            store.Save(state with { Status = "ignored", IgnoredFingerprint = fingerprint,
                Detail = "Kept local content. This remote version will not be imported or overwrite local metadata.", Updated = DateTimeOffset.UtcNow });
        }
        finally { submissions.Release(); }
    }
}
