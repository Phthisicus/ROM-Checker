using System.Security.Cryptography;
using System.Text.Json;
using System.Net.Http.Json;
using RomChecker.Web.Features.Catalog;
using RomChecker.Web.Features.Storage;

namespace RomChecker.Web.Features.Romm;

public sealed partial class RommService(RommStore store, RommClient client, CanonicalCatalog catalog,
    StorageClient storage, WebOptions options, JobService engineJobs, Store engineStore, ILogger<RommService> logger) : BackgroundService
{
    private readonly SemaphoreSlim submissions = new(1, 1);
    public string ExportRoot { get; } = Path.GetFullPath(Environment.GetEnvironmentVariable("ROMCHECKER_ROMM_EXPORT_ROOT")
        ?? Path.Combine(storage.Root, "romm-library"));
    public RommLink[] Links()
    {
        var current = catalog.Entries().ToDictionary(entry => entry.Id);
        return store.Links().Where(link => link.ConnectionId == store.Config().ConnectionId && current.ContainsKey(link.EntryId))
            .Select(link => string.Equals(current[link.EntryId].SHA256, link.Fingerprint, StringComparison.OrdinalIgnoreCase)
                ? link : link with { Status = "stale" }).ToArray();
    }
    public async Task SaveConfig(RommConfig request)
    {
        await submissions.WaitAsync();
        try
        {
            var old = store.Config();
            var rules = RommPublishPolicy.Validate(request.PublishRules ?? old.PublishRules ?? new());
            var sync = ValidateSync(request.Sync ?? old.Sync ?? new(), request.PlatformMappings ?? []);
            var uri = RommClient.ValidateUrl(request.Url);
            var mappings = request.PlatformMappings ?? [];
            if (mappings.Length > 1000 || mappings.Any(mapping => string.IsNullOrWhiteSpace(mapping.Console) || mapping.PlatformId < 1
                || string.IsNullOrWhiteSpace(mapping.Slug) || mapping.Slug.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_')))
                throw new RequestException("Each platform mapping needs a console, positive platform ID, and a portable RomM filesystem slug.");
            if (mappings.Select(mapping => mapping.Console).Distinct(StringComparer.Ordinal).Count() != mappings.Length)
                throw new RequestException("Only one RomM mapping per console is allowed.");
            var token = string.IsNullOrEmpty(request.Token) ? old.Token : request.Token;
            if (token.Length < 16 || token.Length > 4096 || token.Any(char.IsControl))
                throw new RequestException("Enter a valid RomM API token.");
            if (uri.AbsoluteUri != old.Url && string.IsNullOrEmpty(request.Token))
                throw new RequestException("Supply a token when changing RomM servers; existing credentials are never forwarded to another server.");
            var changed = uri.AbsoluteUri != old.Url || Json.Serialize(mappings) != Json.Serialize(old.PlatformMappings ?? []);
            if ((changed || token != old.Token) && store.Jobs().Any(job => job.Status is "queued" or "running" or "awaiting-scan" or "awaiting-import"))
                throw new RequestException("Finish pending synchronization jobs before changing the connection. Automatic publishing can still be disabled.", 409);
            store.Save(request with { Url = uri.AbsoluteUri, Token = token,
                PlatformMappings = mappings, PublishRules = rules, Sync = sync,
                ConnectionId = changed || old.ConnectionId == "" ? Guid.NewGuid().ToString("N") : old.ConnectionId });
            if (changed)
                foreach (var link in store.Links().Where(link => link.ConnectionId == old.ConnectionId))
                    catalog.UpdateSync(link.EntryId, "not-published", "RomM connection or platform mappings changed; previous exports were not deleted.");
        }
        finally { submissions.Release(); }
    }
    private RommConfig Configured()
    {
        var config = store.Config();
        if (string.IsNullOrEmpty(config.Url) || string.IsNullOrEmpty(config.Token)) throw new RequestException("Configure RomM first.", 409);
        return config;
    }
    public CatalogEntry[] Select(string[] ids)
    {
        if (ids is null || ids.Length is 0 or > 100000) throw new RequestException("Select between 1 and 100000 ROM files.");
        var chosen = ids.Distinct(StringComparer.Ordinal).Select(catalog.Get).ToArray();
        var groups = chosen.Select(GroupKey).ToHashSet(StringComparer.Ordinal);
        var result = catalog.Entries().Where(entry => groups.Contains(GroupKey(entry))).ToArray();
        if (result.Length > 100000) throw new RequestException("Linked selection exceeds 100000 files.");
        return result;
    }
    private static string GroupKey(CatalogEntry entry) => entry.BatchId + ":" +
        (RommClient.Text(entry.Evidence, "GroupId") is { Length: > 0 } group ? group : entry.Id);
    public RommRulePreview PreviewAutomatic(RommRulePreviewRequest request)
    {
        if (request.Page < 1 || request.Size is < 1 or > 200)
            throw new RequestException("Page must be positive; preview size must be 1-200.");
        var config = store.Config();
        config = config with { PublishRules = RommPublishPolicy.Validate(request.Rules ?? config.PublishRules ?? new()) };
        var groups = AutomaticGroups(config, catalog.Entries());
        return new(groups.Length, groups.Count(group => group.Status != "excluded"),
            groups.Count(group => group.Status == "ready"), groups.Count(group => group.Status == "excluded"),
            groups.Count(group => group.Status == "pending"), groups.Count(group => group.Status == "linked"),
            groups.Count(group => group.Status == "failed"), request.Page, request.Size,
            groups.Skip((int)Math.Min((long)(request.Page - 1) * request.Size, int.MaxValue)).Take(request.Size).ToArray());
    }
    private RommRuleGroup[] AutomaticGroups(RommConfig config, CatalogEntry[] catalogEntries)
    {
        var jobs = store.Jobs();
        var pending = jobs.Where(job => job.Status is "queued" or "running" or "awaiting-scan" or "awaiting-import")
            .SelectMany(job => job.Items).Select(item => item.EntryId).ToHashSet();
        var failed = jobs.Where(job => job.Automatic && job.ConnectionId == config.ConnectionId
            && job.Status is "failed" or "completed-with-errors")
            .SelectMany(job => job.Items.Where(item => item.Status != "linked"))
            .Select(item => (item.EntryId, item.Fingerprint)).ToHashSet();
        var links = store.Links().Where(link => link.ConnectionId == config.ConnectionId && link.Status == "linked")
            .ToDictionary(link => link.EntryId);
        var conflicts = store.Links().Where(link => link.ConnectionId == config.ConnectionId && link.Status == "conflict")
            .Select(link => link.EntryId).ToHashSet();
        conflicts.UnionWith(store.Remotes(config.ConnectionId).Where(state => state.Status is "conflict" or "ignored")
            .SelectMany(state => state.EntryIds));
        return catalogEntries.GroupBy(GroupKey).Select(group =>
        {
            var entries = group.ToArray();
            var reason = RommPublishPolicy.BlockReason(entries, config);
            if (entries.Any(entry => conflicts.Contains(entry.Id))) reason = "Resolve the RomM synchronization conflict before automatic publication.";
            var status = reason is null ? "ready" : "excluded";
            if (reason is null)
            {
                if (entries.Any(entry => pending.Contains(entry.Id)))
                { status = "pending"; reason = "This game already has pending synchronization work."; }
                else if (entries.All(entry => links.TryGetValue(entry.Id, out var link) && link.Fingerprint == entry.SHA256))
                { status = "linked"; reason = "All files already have current RomM links."; }
                else if (entries.Any(entry => failed.Contains((entry.Id, (string?)entry.SHA256))))
                { status = "failed"; reason = "Previous automatic publication failed. Review activity and retry the failed job."; }
            }
            return new RommRuleGroup(group.Key, (entries.FirstOrDefault(entry => entry.Category != "Companion") ?? entries[0]).FileName,
                entries.Length, entries[0].Console, entries[0].BatchId,
                entries.Where(entry => entry.Category != "Companion").Select(CatalogRegions.For)
                    .DistinctBy(region => region.Source + ":" + string.Join(",", region.Values)).ToArray(),
                status, reason ?? "Matches the rules; will be queued when automatic publishing is enabled.",
                entries.Select(entry => entry.Id).ToArray());
        }).OrderBy(group => group.Name, StringComparer.OrdinalIgnoreCase).ThenBy(group => group.Id, StringComparer.Ordinal).ToArray();
    }
    private async Task QueueAutomatic()
    {
        await submissions.WaitAsync();
        try
        {
            var config = store.Config();
            if (!config.AutoPublish) return;
            _ = Configured();
            var entries = catalog.Entries().ToDictionary(entry => entry.Id);
            var items = new List<RommItem>();
            foreach (var group in AutomaticGroups(config, entries.Values.ToArray()).Where(group => group.Status == "ready"))
            {
                if (group.Files > 100000) throw new RequestException("An automatic publishing group exceeds 100000 files.");
                if (items.Count + group.Files > 100000) break;
                items.AddRange(group.EntryIds.Select(id => new RommItem(id, Fingerprint: entries[id].SHA256)));
                if (items.Count >= 1000) break;
            }
            if (items.Count > 0)
                store.Save(new RommJob(Guid.NewGuid().ToString("N"), "publish", "queued", DateTimeOffset.UtcNow,
                    null, null, config.ConnectionId, items.ToArray(), Automatic: true));
        }
        finally { submissions.Release(); }
    }
    private void RequireAutomaticPolicy(RommJob job, CatalogEntry[] group)
    {
        if (!job.Automatic) return;
        var current = store.Config();
        if (!current.AutoPublish) throw new RequestException("Automatic publishing was disabled. No new export was promoted.", 409);
        if (current.ConnectionId != job.ConnectionId) throw new RequestException("The RomM connection changed.", 409);
        var currentGroup = catalog.Entries().Where(entry => GroupKey(entry) == GroupKey(group[0])).ToArray();
        var currentById = currentGroup.ToDictionary(entry => entry.Id);
        if (store.Links().Any(link => link.ConnectionId == current.ConnectionId && link.Status == "conflict" && currentById.ContainsKey(link.EntryId)))
            throw new RequestException("Resolve the RomM synchronization conflict before automatic publication.", 409);
        if (store.Remotes(current.ConnectionId).Any(state => state.Status is "conflict" or "ignored"
            && state.EntryIds.Any(currentById.ContainsKey)))
            throw new RequestException("Resolve the RomM synchronization conflict before automatic publication.", 409);
        if (currentGroup.Length != group.Length || group.Any(entry => !currentById.ContainsKey(entry.Id)))
            throw new RequestException("The linked game group changed. Review it and submit publication again.", 409);
        if (group.Any(entry => currentById[entry.Id].SHA256 != entry.SHA256))
            throw new RequestException("Game content changed during automatic publication. Recheck and submit again.", 409);
        var reason = RommPublishPolicy.BlockReason(currentGroup, current);
        if (reason is not null) throw new RequestException("Automatic publishing rules blocked this game: " + reason, 409);
    }
    public object Preview(string[] ids)
    {
        var config = Configured();
        var selected = Select(ids);
        var eligible = new List<object>();
        var blocked = new List<object>();
        foreach (var group in selected.GroupBy(GroupKey))
        {
            string? reason = null;
            foreach (var entry in group)
            {
                if (!(config.PlatformMappings ?? []).Any(mapping => mapping.Console == entry.Console)) { reason = "Configure the RomM platform mapping first."; break; }
                if (!entry.PublishEligible) { reason = entry.PublishBlockReason; break; }
            }
            foreach (var entry in group)
                if (reason is null) eligible.Add(new { entry.Id, entry.FileName });
                else blocked.Add(new { entry.Id, entry.FileName, reason = "Linked group: " + reason });
        }
        return new { selected = selected.Length, eligible, blocked };
    }
    public async Task<RommJob> Queue(string kind, string[] ids, bool confirm)
    {
        if (!confirm) throw new RequestException("Explicit confirmation is required.");
        if (kind is not ("publish" or "metadata")) throw new RequestException("Unknown synchronization action.");
        await submissions.WaitAsync();
        try
        {
            var config = Configured();
            var entries = Select(ids);
            var pending = store.Jobs().Where(job => job.Status is "queued" or "running" or "awaiting-scan" or "awaiting-import").ToArray();
            if (entries.Any(entry => pending.Any(job => job.Items.Any(item => item.EntryId == entry.Id))))
                throw new RequestException("A selected file already has pending synchronization work.", 409);
            var items = new List<RommItem>();
            foreach (var group in entries.GroupBy(GroupKey))
            {
                var accepted = true;
                if (kind == "publish")
                    foreach (var entry in group)
                        if (!entry.PublishEligible) { accepted = false; break; }
                if (!accepted) continue;
                foreach (var entry in group)
                {
                    if (!(config.PlatformMappings ?? []).Any(mapping => mapping.Console == entry.Console))
                        throw new RequestException("Configure platform mappings for all eligible consoles.");
                    items.Add(new(entry.Id, Fingerprint: entry.SHA256));
                }
            }
            if (items.Count == 0) throw new RequestException("No selected files are eligible. Complete checks and review blocking findings first.", 409);
            var job = new RommJob(Guid.NewGuid().ToString("N"), kind, "queued", DateTimeOffset.UtcNow, null, null, config.ConnectionId, items.ToArray());
            store.Save(job);
            return job;
        }
        finally { submissions.Release(); }
    }
    public async Task<RommJob> QueueImport(int[] ids, bool confirm, bool importChanged = false, bool automatic = false,
        CancellationToken token = default)
    {
        if (!confirm || ids is null || ids.Length is 0 or > 1000 || ids.Any(id => id < 1)) throw new RequestException("Confirm between 1 and 1000 RomM imports.");
        await submissions.WaitAsync(token);
        try
        {
            var config = Configured();
            var history = store.Jobs().Where(job => job.ConnectionId == config.ConnectionId && job.Kind == "import").ToArray();
            var pending = history.Where(job => job.Status is "queued" or "running" or "awaiting-import").SelectMany(job => job.Items).ToArray();
            if (ids.Any(id => pending.Any(item => item.RommId == id))) throw new RequestException("A selected RomM import is already queued.", 409);
            var states = store.Remotes(config.ConnectionId);
            var items = new List<RommItem>();
            foreach (var id in ids.Distinct())
            {
                var previous = states.FirstOrDefault(state => state.RommId == id);
                if (!importChanged && (previous is not null && !(automatic && previous.Snapshot is null && previous.EntryIds.Length == 0)
                    || history.Any(job => job.Items.Any(item => item.RommId == id))))
                    throw new RequestException("This RomM game already has synchronization history. Recheck conflicts or retry its existing import.", 409);
                if (importChanged && previous?.Status != "conflict")
                    throw new RequestException("Only a reviewed synchronization conflict can be imported as a separate new copy.", 409);
                var remote = await client.Get(config, $"api/roms/{id}", token);
                if (RommClient.Number(remote, "id") != id) throw new RequestException("RomM returned a different game ID.", 409);
                var snapshot = RommIdentity.Snapshot(remote);
                if (automatic) RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
                if (pending.Any(item => item.RemoteSnapshot?.ContentKey == snapshot.ContentKey)
                    || items.Any(item => item.RemoteSnapshot?.ContentKey == snapshot.ContentKey))
                    throw new RequestException("Identical game content already has a pending import. Wait for it to finish before rechecking.", 409);
                items.Add(new("remote:" + id, RommId: id, RemoteSnapshot: snapshot));
            }
            var job = new RommJob(Guid.NewGuid().ToString("N"), "import", "queued", DateTimeOffset.UtcNow, null, null, config.ConnectionId,
                items.ToArray(), Automatic: automatic);
            store.Save(job);
            return job;
        }
        finally { submissions.Release(); }
    }
    public async Task<RommJob> Retry(string id)
    {
        await submissions.WaitAsync();
        try
        {
            var job = store.Get(id);
            if (job.Status is not ("failed" or "completed-with-errors")) throw new RequestException("Only failed work can be retried.", 409);
            if (Configured().ConnectionId != job.ConnectionId) throw new RequestException("The RomM connection changed. Submit a new operation.", 409);
            job = job with { Status = "queued", Error = null, Finished = null, AttemptStarted = DateTimeOffset.UtcNow,
                Items = job.Items.Select(item => item.Status == "failed" ? item with { Status = item.ExportPath is null ? "queued" : "exported", Error = null } : item).ToArray() };
            store.Save(job);
            return job;
        }
        finally { submissions.Release(); }
    }
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var lastAuto = DateTimeOffset.MinValue;
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!engineJobs.RecoveryComplete)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1), stoppingToken);
                    continue;
                }
                foreach (var job in store.Jobs().Where(job => job.Status is "queued" or "awaiting-scan" or "awaiting-import").OrderBy(job => job.Created))
                {
                    stoppingToken.ThrowIfCancellationRequested();
                    await Process(job, stoppingToken);
                }
                var config = store.Config();
                await ScheduleSync();
                if (config.AutoPublish && DateTimeOffset.UtcNow - lastAuto > TimeSpan.FromMinutes(1))
                {
                    lastAuto = DateTimeOffset.UtcNow;
                    await QueueAutomatic();
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "RomM synchronization scheduler failed"); }
            await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
        }
    }
    private async Task Process(RommJob initial, CancellationToken stoppingToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        deadline.CancelAfter(options.JobTimeout);
        var token = deadline.Token;
        var job = initial with { Status = "running", Error = null, AttemptStarted = initial.AttemptStarted ?? DateTimeOffset.UtcNow };
        store.Save(job);
        try
        {
            var config = Configured();
            if (config.ConnectionId != job.ConnectionId) throw new RequestException("RomM connection changed. Submit a new operation.");
            if (job.Kind == "sync")
            {
                job = job with { Items = await Reconcile(config, token) };
            }
            else if (job.Kind == "import")
            {
                for (var index = 0; index < job.Items.Length; index++)
                {
                    if (job.Items[index].Status is "completed" or "failed") continue;
                    try { await Import(job, index, config, token); }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        logger.LogError(ex, "RomM import {JobId} failed for remote {RomId}", job.Id, job.Items[index].RommId);
                        job.Items[index] = job.Items[index] with { Status = "failed", Error = ex.Message };
                        store.Save(job);
                    }
                }
            }
            else
            {
                var entries = job.Items.Select(item => catalog.Get(item.EntryId)).ToArray();
                foreach (var group in entries.GroupBy(GroupKey))
                {
                    var indices = job.Items.Select((item, index) => (item, index)).Where(pair => group.Any(entry => entry.Id == pair.item.EntryId)).Select(pair => pair.index).ToArray();
                    if (indices.All(index => job.Items[index].Status is "linked" or "failed")) continue;
                    try
                    {
                        foreach (var entry in group)
                            if (job.Items.First(item => item.EntryId == entry.Id).Fingerprint != entry.SHA256)
                                throw new RequestException("File content changed since synchronization was queued. Recheck and submit again.");
                        if (job.Kind == "publish" && indices.Any(index => job.Items[index].ExportPath is null))
                        {
                            RequireAutomaticPolicy(job, group.ToArray());
                            var allPresent = true;
                            foreach (var entry in group)
                            {
                                await catalog.EnsurePublishable(entry);
                                var mapping = (config.PlatformMappings ?? []).Single(value => value.Console == entry.Console);
                                if (await client.ByHash(config, RommClient.Text(entry.Evidence, "SHA1"), mapping.PlatformId, token) is null)
                                    allPresent = false;
                            }
                            // Receiving and publishing an already-known game must not create another remote copy.
                            if (!allPresent) await Export(job, group.ToArray(), config, token);
                        }
                        foreach (var index in indices)
                        {
                            var entry = catalog.Get(job.Items[index].EntryId);
                            if (job.Kind == "publish") await catalog.EnsurePublishable(entry);
                            else if (!string.Equals(await Hash(catalog.PhysicalPath(entry), token), entry.SHA256, StringComparison.OrdinalIgnoreCase))
                                throw new RequestException("Local content changed. Recheck before linking descriptive metadata.");
                            var mapping = (config.PlatformMappings ?? []).Single(mapping => mapping.Console == entry.Console);
                            var existingLink = store.Links().FirstOrDefault(link => link.EntryId == entry.Id
                                && link.ConnectionId == config.ConnectionId && link.RommId is > 0);
                            var metadata = job.Kind == "metadata" && existingLink is not null
                                ? await LinkedMetadata(config, entry, existingLink, token)
                                : await client.ByHash(config, RommClient.Text(entry.Evidence, "SHA1"), mapping.PlatformId, token);
                            if (metadata is null)
                            {
                                if (job.Kind == "metadata") throw new RequestException("No exact RomM fingerprint match. Scan RomM or publish the checked file first.", 409);
                                job.Items[index] = job.Items[index] with { Status = "awaiting-scan", Error = null };
                            }
                            else
                            {
                                var remoteId = RommClient.Number(metadata.Value, "id");
                                if (remoteId < 1) throw new RequestException("RomM returned an invalid ROM identifier.", 502);
                                store.Save(new RommLink(entry.Id, remoteId, "linked", metadata.Value, DateTimeOffset.UtcNow,
                                    entry.SHA256, config.ConnectionId, job.Items[index].ExportPath ?? existingLink?.ExportPath));
                                catalog.UpdateSync(entry.Id, "linked", $"Linked exact fingerprint to RomM #{remoteId}.");
                                job.Items[index] = job.Items[index] with { Status = "linked", RommId = remoteId, Error = null };
                                catalog.Audit(entry.Id, "romm-linked", $"Linked exact fingerprint to RomM #{remoteId}; descriptive metadata imported.");
                            }
                            store.Save(job);
                        }
                    }
                    catch (Exception ex) when (ex is not OperationCanceledException)
                    {
                        logger.LogError(ex, "RomM {Kind} job {JobId} failed for a linked file group", job.Kind, job.Id);
                        foreach (var index in indices) job.Items[index] = job.Items[index] with { Status = "failed", Error = ex.Message };
                        MarkPublicationFailed(job, indices);
                        store.Save(job);
                    }
                }
                if (job.Items.Any(item => item.Status == "awaiting-scan") && initial.Status != "awaiting-scan")
                    await client.Scan(config, entries.Select(entry => (config.PlatformMappings ?? []).Single(mapping => mapping.Console == entry.Console).PlatformId).ToArray(), token);
            }
            var waiting = job.Items.Any(item => item.Status == "awaiting-scan");
            if (waiting && DateTimeOffset.UtcNow - job.AttemptStarted > TimeSpan.FromMinutes(30))
                throw new RequestException("RomM has not indexed the exported files after 30 minutes. Check its shared-library mount and scan logs, then retry.");
            var preparing = job.Items.Any(item => item.Status is "preparing" or "detecting");
            var failed = job.Items.Any(item => item.Status == "failed");
            store.Save(job with { Status = waiting ? "awaiting-scan" : preparing ? "awaiting-import" : failed ? "completed-with-errors" : "completed",
                Finished = waiting || preparing ? null : DateTimeOffset.UtcNow });
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            store.Save(job with { Status = "queued", Error = "Server stopped; durable work will resume." });
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "RomM job {JobId} failed", job.Id);
            MarkPublicationFailed(job, Enumerable.Range(0, job.Items.Length).Where(index => job.Items[index].Status != "linked"));
            store.Save(job with { Status = "failed", Error = ex.Message, Finished = DateTimeOffset.UtcNow });
        }
    }
    private void MarkPublicationFailed(RommJob job, IEnumerable<int> indices)
    {
        if (job.Kind != "publish") return;
        foreach (var index in indices)
        {
            var entry = catalog.Get(job.Items[index].EntryId);
            if (entry.SyncStatus is not ("linked" or "failed"))
                catalog.UpdateSync(entry.Id, "failed", "Publication failed; review synchronization history before retrying.");
        }
    }
    private async Task Export(RommJob job, CatalogEntry[] group, RommConfig config, CancellationToken token)
    {
        bool Inside(string parent, string child)
        {
            var relative = Path.GetRelativePath(parent, child);
            return !Path.IsPathRooted(relative) && relative != ".." && !relative.StartsWith(".." + Path.DirectorySeparatorChar);
        }
        var batches = Path.Combine(storage.Root, "batches");
        if (Inside(batches, ExportRoot) || Inside(ExportRoot, batches) || Inside(options.Root, ExportRoot) || Inside(ExportRoot, options.Root))
            throw new RequestException("RomM export must be separate from imports and the mounted legacy library.");
        StoragePaths.AssertNoLinks(ExportRoot, ExportRoot);
        var batch = group[0].BatchId;
        if (string.IsNullOrEmpty(batch)) throw new RequestException("Import legacy files into managed storage before publishing.");
        await storage.Command($"batches/{batch}/lease", new LeaseRequest(job.Id), token);
        try
        {
            foreach (var entry in group) await catalog.EnsurePublishable(entry);
            var mapping = (config.PlatformMappings ?? []).Single(value => value.Console == group[0].Console);
            var groupId = RommClient.Text(group[0].Evidence, "GroupId");
            if (!Guid.TryParseExact(groupId, "N", out _)) groupId = group[0].Id;
            var directory = StoragePaths.Resolve(ExportRoot, $"roms/{mapping.Slug}/{groupId}");
            var stage = StoragePaths.Resolve(ExportRoot, $".staging/{job.Id}/{groupId}");
            Directory.CreateDirectory(stage);
            var relative = group.Select(entry => StoragePaths.Relative(entry.RelativePath)).ToArray();
            var prefix = Path.GetDirectoryName(relative[0].Replace('/', Path.DirectorySeparatorChar)) ?? "";
            while (prefix.Length > 0 && relative.Any(path => !path.StartsWith(prefix.Replace(Path.DirectorySeparatorChar, '/') + "/", StringComparison.Ordinal)))
                prefix = Path.GetDirectoryName(prefix) ?? "";
            var names = relative.Select(path => prefix.Length > 0 ? path[(prefix.Length + 1)..] : path).ToArray();
            if (names.Distinct(StringComparer.OrdinalIgnoreCase).Count() != names.Length) throw new RequestException("Linked files collide in the RomM export.");
            var needed = group.Sum(entry => entry.Length);
            var probe = Directory.Exists(ExportRoot) ? ExportRoot : storage.Root;
            if (new DriveInfo(probe).AvailableFreeSpace < needed + 1024L * 1024 * 1024)
                throw new RequestException("RomM export needs space for a complete group plus a 1 GiB reserve.");
            for (var index = 0; index < group.Length; index++)
            {
                token.ThrowIfCancellationRequested();
                var entry = group[index];
                var target = StoragePaths.Resolve(stage, names[index]);
                Directory.CreateDirectory(Path.GetDirectoryName(target)!);
                var source = catalog.PhysicalPath(entry);
                await using (var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, true))
                await using (var output = new FileStream(target, FileMode.Create, FileAccess.Write, FileShare.None, 65536, true))
                    await input.CopyToAsync(output, token);
                if (!string.Equals(await Hash(target, token), entry.SHA256, StringComparison.OrdinalIgnoreCase))
                    throw new RequestException("File changed during export. Recheck before publishing.");
            }
            foreach (var entry in group) await catalog.EnsurePublishable(entry);
            if (StoragePaths.Files(stage).Count() != group.Length) throw new RequestException("Unexpected files exist in the staged export. Review storage before retrying.");
            await submissions.WaitAsync(token);
            try
            {
                RequireAutomaticPolicy(job, group);
                if (Directory.Exists(directory))
                {
                    var existing = StoragePaths.Files(directory).ToArray();
                    if (existing.Length != group.Length) throw new RequestException("Existing RomM export differs. No files were overwritten.");
                    for (var index = 0; index < group.Length; index++)
                        if (!File.Exists(StoragePaths.Resolve(directory, names[index]))
                            || !string.Equals(await Hash(StoragePaths.Resolve(directory, names[index]), token), group[index].SHA256, StringComparison.OrdinalIgnoreCase))
                            throw new RequestException("A different RomM export already occupies this location. No files were overwritten.");
                    Directory.Delete(stage, true);
                }
                else
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(directory)!);
                    StoragePaths.AssertNoLinks(ExportRoot, directory);
                    Directory.Move(stage, directory);
                }
            }
            finally { submissions.Release(); }
            for (var index = 0; index < group.Length; index++)
            {
                var itemIndex = Array.FindIndex(job.Items, item => item.EntryId == group[index].Id);
                var exportPath = Path.GetRelativePath(ExportRoot, Path.Combine(directory, names[index])).Replace(Path.DirectorySeparatorChar, '/');
                job.Items[itemIndex] = job.Items[itemIndex] with { Status = "exported", ExportPath = exportPath };
                store.Save(new RommLink(group[index].Id, null, "awaiting-scan", JsonSerializer.SerializeToElement(new { }), DateTimeOffset.UtcNow,
                    group[index].SHA256, config.ConnectionId, exportPath));
                catalog.UpdateSync(group[index].Id, "awaiting-scan", "Checked copy exported; waiting for RomM scan.");
                catalog.Audit(group[index].Id, "romm-exported", "Published a checked, policy-eligible copy to " + exportPath);
            }
            store.Save(job);
        }
        finally
        {
            await storage.Command($"batches/{batch}/release", new LeaseRequest(job.Id), CancellationToken.None);
        }
    }
    private async Task Import(RommJob job, int index, RommConfig config, CancellationToken token)
    {
        var item = job.Items[index];
        var remoteId = item.RommId ?? throw new RequestException("Missing remote ROM ID.");
        var remote = await client.Get(config, $"api/roms/{remoteId}", token);
        if (RommClient.Number(remote, "id") != remoteId) throw new RequestException("RomM returned a different game ID.", 409);
        var snapshot = RommIdentity.Snapshot(remote);
        if (item.RemoteSnapshot is { } expectedSnapshot && expectedSnapshot.Fingerprint != snapshot.Fingerprint)
        {
            var previous = store.Remotes(config.ConnectionId).FirstOrDefault(state => state.RommId == remoteId);
            RecordConflict(config, remoteId, RommClient.Text(remote, "name"), previous?.Snapshot ?? expectedSnapshot,
                previous?.EntryIds ?? [], "Remote files changed after this import was queued. Existing bytes were not overwritten.");
            throw new RequestException("Remote files changed after this import was queued. Review the conflict before importing a new version.", 409);
        }
        if (job.Automatic && item.Status is not ("preparing" or "detecting"))
            RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
        if (item.RemoteSnapshot is null)
        {
            item = item with { RemoteSnapshot = snapshot };
            job.Items[index] = item;
            store.Save(job);
        }
        var files = remote.TryGetProperty("files", out var remoteFiles) && remoteFiles.ValueKind == JsonValueKind.Array
            ? remoteFiles.EnumerateArray().ToArray() : [];
        if (files.Length == 0) throw new RequestException("RomM did not supply individual file metadata; no unchecked archive extraction will be attempted.");
        if (files.Length > 100000) throw new RequestException("RomM game exceeds the 100000-file import limit.");
        var batchId = item.BatchId;
        if (batchId is null)
        {
            var duplicate = await FindLocalCopy(config, snapshot, token);
            if (duplicate is not null)
            {
                await BindRemote(config, remoteId, remote, snapshot, duplicate, token, automatic: job.Automatic);
                job.Items[index] = item with { Status = "completed", Error = null };
                store.Save(job);
                return;
            }
            batchId = Guid.NewGuid().ToString("N");
            var batchName = "RomM: " + RommClient.Text(remote, "name");
            if (batchName.Length > 120) batchName = batchName[..120];
            job.Items[index] = item = item with { BatchId = batchId, BatchCreationPending = true, BatchName = batchName };
            store.Save(job);
        }
        if (item.BatchCreationPending)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "batches")
            { Content = JsonContent.Create(new BatchRequest(item.BatchName ?? throw new RequestException("Missing import allocation name.")), options: Json.Options) };
            request.Headers.Add("Idempotency-Key", batchId);
            using var response = await storage.Send(request, token);
            response.EnsureSuccessStatusCode();
            var batch = await response.Content.ReadFromJsonAsync<Batch>(Json.Options, token) ?? throw new RequestException("Storage did not create an import.");
            if (batch.Id != batchId) throw new RequestException("Storage returned a different import allocation.", 502);
            job.Items[index] = item = item with { BatchCreationPending = false, Status = "transferring" };
            store.Save(job);
        }
        var state = await storage.Get<Batch>($"batches/{batchId}", token);
        if (state.Status == "uploading")
        {
            foreach (var file in files)
            {
                if (job.Automatic) RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
                var filename = RommClient.Text(file, "file_name");
                var name = RommIdentity.FilePath(remote, file, files.Length > 1);
                var fileId = RommClient.Number(file, "id");
                if (fileId < 1 || !long.TryParse(RommClient.Text(file, "file_size_bytes"), out var size) || size < 0)
                    throw new RequestException("RomM supplied invalid file metadata.");
                using var start = new HttpRequestMessage(HttpMethod.Post, $"batches/{batchId}/uploads")
                { Content = System.Net.Http.Json.JsonContent.Create(new UploadRequest(name, size, remoteId), options: Json.Options) };
                using var started = await storage.Send(start, token);
                started.EnsureSuccessStatusCode();
                var upload = await started.Content.ReadFromJsonAsync<UploadState>(Json.Options, token) ?? throw new RequestException("Storage did not register the upload.");
                var expected = RommClient.Text(file, "sha1_hash");
                if (upload.Complete)
                {
                    if (expected.Length > 0)
                    {
                        var originalRoot = Path.Combine(storage.Root, "batches", StoragePaths.Id(batchId), "originals");
                        await using var saved = File.OpenRead(StoragePaths.Resolve(originalRoot, name));
                        if (!Convert.ToHexString(await SHA1.HashDataAsync(saved, token)).Equals(expected, StringComparison.OrdinalIgnoreCase))
                            throw new RequestException("Previously downloaded bytes differ from RomM's hash. Review and remove the failed import before starting a new one.");
                    }
                    continue;
                }
                // Single file_ids with a matching file_name requests raw bytes rather than a whole-game ZIP.
                using var response = await client.Send(config, $"api/roms/{remoteId}/content/{Uri.EscapeDataString(filename)}?file_ids={fileId}", HttpMethod.Get, token);
                if (response.StatusCode == System.Net.HttpStatusCode.NotFound) throw new RequestException("RomM file download is unavailable.");
                if (response.Content.Headers.ContentType?.MediaType == "application/zip" && !name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    throw new RequestException("RomM returned an archive instead of raw file bytes. Import stopped to preserve file identity.");
                await using var input = await response.Content.ReadAsStreamAsync(token);
                var buffer = new byte[StorageOptions.ChunkBytes];
                long offset = 0;
                using var sha1 = IncrementalHash.CreateHash(HashAlgorithmName.SHA1);
                if (size == 0)
                {
                    using var empty = new HttpRequestMessage(HttpMethod.Put, $"batches/{batchId}/uploads/{upload.Id}?offset=0")
                    { Content = new ByteArrayContent([]) };
                    using var accepted = await storage.Send(empty, token);
                    accepted.EnsureSuccessStatusCode();
                }
                while (offset < size)
                {
                    if (job.Automatic) RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
                    var count = (int)Math.Min(buffer.Length, size - offset);
                    await input.ReadExactlyAsync(buffer.AsMemory(0, count), token);
                    sha1.AppendData(buffer, 0, count);
                    if (offset >= upload.Offset)
                    {
                        using var chunk = new HttpRequestMessage(HttpMethod.Put, $"batches/{batchId}/uploads/{upload.Id}?offset={offset}")
                        { Content = new ByteArrayContent(buffer, 0, count) };
                        using var accepted = await storage.Send(chunk, token);
                        accepted.EnsureSuccessStatusCode();
                    }
                    offset += count;
                }
                if (await input.ReadAsync(buffer.AsMemory(0, 1), token) != 0) throw new RequestException("RomM file size differs from its metadata.");
                if (expected.Length > 0 && !Convert.ToHexString(sha1.GetHashAndReset()).Equals(expected, StringComparison.OrdinalIgnoreCase))
                    throw new RequestException("RomM download hash differs from its metadata; import remains unchecked and is not prepared.");
            }
            await submissions.WaitAsync(token);
            try
            {
                if (job.Automatic) RequireInboundPolicy(config.ConnectionId, snapshot.PlatformId);
                var latest = await client.Get(config, $"api/roms/{remoteId}", token);
                if (RommIdentity.Snapshot(latest).Fingerprint != snapshot.Fingerprint)
                    throw new RequestException("RomM files changed during transfer; this import remains unprepared. Review and retry.", 409);
                await storage.Command($"batches/{batchId}/prepare", new { }, token);
            }
            finally { submissions.Release(); }
        }
        else if (!state.Prepared && state.Status is not ("preparing" or "ready")) throw new RequestException("RomM import needs attention in Imports before retrying.");
        var status = "preparing";
        if (state.Prepared)
        {
            if (item.DetectionJobId is null)
            {
                item = item with { DetectionJobId = Guid.NewGuid().ToString("N") };
                job.Items[index] = item;
                store.Save(job);
            }
            Job? detection;
            try { detection = engineStore.Get(item.DetectionJobId); }
            catch (RequestException ex) when (ex.Status == 404) { detection = null; }
            if (detection is null && !engineJobs.Busy)
                try { detection = await engineJobs.Submit(new("detect", BatchId: batchId), item.DetectionJobId); }
                catch (RequestException ex) when (ex.Status == 409) { logger.LogInformation("RomM import detection is waiting for engine availability"); }
            if (detection?.Status is "failed" or "interrupted" or "cancelled")
                throw new RequestException("Imported ROM console detection failed. Review Activity and retry from Imports.");
            status = detection is not null && (detection.Status is "completed" or "completed-with-warnings") && !engineJobs.IsActive(detection.Id)
                ? "completed" : "detecting";
            if (status == "completed")
            {
                await catalog.Refresh(token);
                var entries = catalog.Entries().Where(entry => entry.BatchId == batchId && !entry.Missing).ToArray();
                await BindRemote(config, remoteId, remote, snapshot, entries, token);
            }
        }
        job.Items[index] = item with { Status = status, Error = null };
        store.Save(job);
    }
    private static async Task<string> Hash(string path, CancellationToken token)
    {
        await using var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 65536, true);
        return Convert.ToHexString(await SHA256.HashDataAsync(input, token));
    }
}
