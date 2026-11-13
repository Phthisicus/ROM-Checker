using System.Security.Cryptography;
using System.Text.Json;
using RomChecker.Web.Features.Storage;

namespace RomChecker.Web.Features.Catalog;

public sealed class CanonicalCatalog(CatalogDatabase database, WebOptions options, StorageClient storage,
    ILogger<CanonicalCatalog> logger)
{
    private readonly SemaphoreSlim mutations = new(1, 1);
    private static readonly StringComparer Paths = OperatingSystem.IsWindows()
        ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;
    private static readonly string[] Categories =
        ["Original", "Hacks_Mods", "Translations", "Beta_Proto_Sample", "PD_Homebrew_Unlicensed", "BS_ST", "Companion"];

    public CatalogEntry[] Entries()
    {
        var entries = database.Entries();
        var owners = DuplicateOwners(entries);
        var eligibility = entries.ToDictionary(entry => entry.Id, CanPublish);
        var blockedUnits = entries.Where(entry => entry.GroupId.Length > 0 && !eligibility[entry.Id].Eligible)
            .Select(entry => (entry.BatchId, entry.GroupId)).ToHashSet();
        return entries.Select(entry =>
        {
            var policy = eligibility[entry.Id];
            if (policy.Eligible && blockedUnits.Contains((entry.BatchId, entry.GroupId)))
                policy = new(false, "A linked file is blocked; the complete unit must remain together.");
            return entry with { PublishEligible = policy.Eligible, PublishBlockReason = policy.Reason, Regions = CatalogRegions.For(entry),
                DuplicateOf = owners.TryGetValue(entry.SHA256, out var owner) && owner != entry.Id ? owner : entry.DuplicateOf };
        }).ToArray();
    }
    private static Dictionary<string, string> DuplicateOwners(IEnumerable<CatalogEntry> entries) =>
        entries.Where(entry => !entry.Missing && entry.SHA256.Length == 64).OrderBy(entry => entry.Id, StringComparer.Ordinal)
            .GroupBy(entry => entry.SHA256, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Id, StringComparer.OrdinalIgnoreCase);
    public CatalogEntry Get(string id)
    {
        StoragePaths.Id(id);
        var entry = database.Get(id) ?? throw new RequestException("Catalog file not found.", 404);
        var owners = DuplicateOwners(database.Entries());
        return Decorate(entry with { DuplicateOf = owners.TryGetValue(entry.SHA256, out var owner) && owner != entry.Id ? owner : entry.DuplicateOf },
            database.Unit(entry));
    }
    public CatalogPage List(CatalogQuery query)
    {
        if (query.Page < 1 || query.Size is < 1 or > 1000) throw new RequestException("Page must be positive; size must be 1-1000.");
        if (query.Checks is not (null or "" or "checked" or "unchecked") ||
            query.Reference is not (null or "" or "matched" or "unmatched" or "modified") ||
            query.Publication is not (null or "" or "eligible" or "blocked") ||
            query.Sort is not (null or "" or "name" or "name-desc" or "console" or "checked" or "size"))
            throw new RequestException("Invalid catalog filter.");
        var all = Entries();
        var copies = all.Where(entry => entry.SHA256.Length == 64).GroupBy(entry => entry.SHA256, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() > 1).Select(group => group.Key).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var filtered = all.Where(entry =>
            (string.IsNullOrWhiteSpace(query.Q) || $"{entry.FileName} {entry.RelativePath} {entry.ConsoleName}".Contains(query.Q, StringComparison.OrdinalIgnoreCase)) &&
            (string.IsNullOrEmpty(query.Console) || entry.Console == query.Console) &&
            (string.IsNullOrEmpty(query.Category) || entry.Category == query.Category) &&
            (string.IsNullOrEmpty(query.Checks) || (entry.CheckStatus == "checked") == (query.Checks == "checked")) &&
            (string.IsNullOrEmpty(query.Reference) || entry.ReferenceStatus == query.Reference) &&
            (string.IsNullOrEmpty(query.SyncStatus) || entry.SyncStatus == query.SyncStatus) &&
            (query.Duplicates is null || query.Duplicates.Value == copies.Contains(entry.SHA256)) &&
            (query.Attention is null || query.Attention.Value == !entry.PublishEligible) &&
            (string.IsNullOrEmpty(query.Publication) || entry.PublishEligible == (query.Publication == "eligible")))
            .ToArray();
        var ordered = query.Sort switch
        {
            "name" => filtered.OrderBy(entry => entry.FileName, StringComparer.OrdinalIgnoreCase),
            "name-desc" => filtered.OrderByDescending(entry => entry.FileName, StringComparer.OrdinalIgnoreCase),
            "checked" => filtered.OrderByDescending(entry => entry.CheckedUtc),
            "size" => filtered.OrderByDescending(entry => entry.Length),
            _ => filtered.OrderBy(entry => entry.ConsoleName, StringComparer.OrdinalIgnoreCase)
                .ThenBy(entry => entry.RelativePath, StringComparer.OrdinalIgnoreCase)
        };
        filtered = ordered.ThenBy(entry => entry.Id, StringComparer.Ordinal).ToArray();
        var groups = filtered.GroupBy(entry => entry.Console).Select(group => new CatalogGroup(
            group.Key, group.First().ConsoleName, group.Count(), group.Count(entry => entry.CheckStatus == "checked"),
            group.Count(entry => !entry.PublishEligible), group.Select(entry => entry.Id).ToArray())).ToArray();
        return new(filtered.Skip((int)Math.Min((long)(query.Page - 1) * query.Size, int.MaxValue)).Take(query.Size).ToArray(),
            all.Length, filtered.Length, query.Page, query.Size, groups, filtered.Select(entry => entry.Id).ToArray(),
            all.Select(entry => entry.Category).Distinct().Order().ToArray(),
            new(all.Length, all.Count(entry => entry.CheckStatus == "checked"), all.Count(entry => entry.CheckStatus != "checked"),
                all.Count(entry => !entry.PublishEligible), all.Count(entry => entry.PublishEligible), all.Count(entry => entry.Missing)),
            all.GroupBy(entry => entry.Console).Select(group => new CatalogConsole(group.Key, group.First().ConsoleName))
                .OrderBy(console => console.Name, StringComparer.OrdinalIgnoreCase).ToArray());
    }
    public string PhysicalPath(CatalogEntry entry)
    {
        // Never allow caller-created entry objects to redirect a publication to another file.
        var current = database.Get(entry.Id)
            ?? throw new RequestException("Catalog file not found.", 404);
        if (current.BatchId != entry.BatchId || current.RelativePath != entry.RelativePath)
            throw new RequestException("Catalog location changed. Refresh and retry.", 409);
        return Resolve(current.BatchId, current.RelativePath);
    }
    private string Resolve(string? batchId, string relative)
        => StoragePaths.Resolve(batchId is null ? options.Root : storage.BatchRoot(batchId), relative);

    public static string Text(JsonElement evidence, string property)
        => evidence.ValueKind == JsonValueKind.Object && evidence.TryGetProperty(property, out var value)
            ? value.ValueKind == JsonValueKind.String ? value.GetString() ?? "" : value.ValueKind is JsonValueKind.Null ? "" : value.ToString()
            : "";
    private static bool Flag(JsonElement evidence, string property)
    {
        var text = Text(evidence, property);
        return !string.IsNullOrEmpty(text) && text is not ("False" or "false" or "0");
    }
    private static CatalogEligibility RequiredChecks(CatalogEntry entry)
    {
        if (entry.Missing) return new(false, "Physical file is missing.");
        if (entry.CheckStatus != "checked" || entry.CheckedUtc is null || entry.SHA256.Length != 64)
            return new(false, "Verification is incomplete or the physical content changed.");
        if (!string.Equals(Text(entry.Evidence, "SHA256"), entry.SHA256, StringComparison.OrdinalIgnoreCase))
            return new(false, "Verification fingerprint does not match the physical file.");
        if (entry.Security != "Clean") return new(false, "Security is not clean; manual approval cannot bypass it.");
        if (Text(entry.Evidence, "AntivirusStatus") != "Completed - no detections")
            return new(false, "Antivirus is disabled, incomplete, unavailable, or detected a threat.");
        var online = Text(entry.Evidence, "OnlineMalwareStatus");
        if (online is not ("Completed" or "Not selected by policy" or "Skipped"))
            return new(false, "Online malware checks are incomplete.");
        if (online == "Skipped" && (!entry.Evidence.TryGetProperty("CheckPolicy", out var policy) || Text(policy, "OnlineCheck") != "Off"))
            return new(false, "The configured online malware check did not complete.");
        if (Text(entry.Evidence, "IdentificationStatus") is "Needs review" or "Error" or "Deferred" or "Unsupported platform" or "Unresolved" or "Hash limit")
            return new(false, "Identity evidence is conflicting or incomplete.");
        if (entry.Console is "" or "-" || !Categories.Contains(entry.Category) &&
            entry.Category is not ("Not_In_DAT" or "Invalid_Corrupt" or "Unknown_Check_Manually"))
            return new(false, "Console or classification is not eligible.");
        if (Text(entry.Evidence, "DependenciesComplete") != "True" && Text(entry.Evidence, "DependenciesComplete") != "true")
            return new(false, "Dependency completeness has not been verified. Re-run verification.");
        if (Text(entry.Evidence, "DependencyConflict") is "True" or "true")
            return new(false, "A linked file has conflicting or incomplete evidence.");
        if ((entry.IntegrityStatus is "" or "Unknown") && Text(entry.Evidence, "Header") is not ("Valid" or "Invalid"))
            return new(false, "Supported integrity evidence is incomplete; manual review cannot replace missing checks.");
        return new(true, null);
    }
    public CatalogEligibility CanPublish(CatalogEntry entry)
    {
        var required = RequiredChecks(entry);
        if (!required.Eligible) return required;
        var approved = entry.Approval is { } approval && approval.SHA256.Equals(entry.SHA256, StringComparison.OrdinalIgnoreCase);
        if (entry.IntegrityStatus is "Failed checks" || Text(entry.Evidence, "Header") == "Invalid")
            return approved ? new(true, null) : new(false, "An internal structure/checksum finding requires fingerprint-bound approval.");
        if (entry.ReferenceStatus != "matched")
            return approved ? new(true, null) : new(false, "No reference match or a known modification requires fingerprint-bound approval.");
        if (entry.IntegrityStatus is "Unknown" or "")
            return new(false, "Integrity evidence is incomplete.");
        if (!Categories.Contains(entry.Category) && !approved)
            return new(false, "This classification requires review.");
        return new(true, null);
    }
    private CatalogEntry Decorate(CatalogEntry entry, CatalogEntry[] entries)
    {
        var eligibility = CanPublish(entry);
        if (eligibility.Eligible && !string.IsNullOrEmpty(entry.GroupId))
        {
            var blocked = entries.FirstOrDefault(other => other.Id != entry.Id && other.BatchId == entry.BatchId &&
                other.GroupId == entry.GroupId && !CanPublish(other).Eligible);
            if (blocked is not null) eligibility = new(false, "A linked file is blocked; the complete unit must remain together.");
        }
        return entry with { PublishEligible = eligibility.Eligible, PublishBlockReason = eligibility.Reason, Regions = CatalogRegions.For(entry) };
    }
    public async Task<CatalogEntry> EnsurePublishable(CatalogEntry entry)
    {
        await mutations.WaitAsync();
        try
        {
            var current = Get(entry.Id);
            if (entry.SHA256 != current.SHA256) throw new RequestException("Catalog content changed. Refresh and retry.", 409);
            var unit = database.Unit(current);
            foreach (var member in unit)
            {
                var fingerprint = await Fingerprint(PhysicalPath(member), CancellationToken.None);
                if (fingerprint.Hash != member.SHA256 || fingerprint.Length != member.Length)
                {
                    database.Save(Invalidate(member, fingerprint.Hash, fingerprint.Length), "content-changed",
                        "Physical content changed before publication; check results and approval invalidated.");
                    throw new RequestException("Physical content changed. Verification and approval were invalidated.", 409);
                }
                var policy = CanPublish(member);
                if (!policy.Eligible) throw new RequestException(policy.Reason!, 409);
            }
            return Get(entry.Id);
        }
        catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException)
        { throw new RequestException("Physical file is missing.", 409); }
        finally { mutations.Release(); }
    }
    public void Audit(string entryId, string action, string detail) => database.Audit(Get(entryId), action, detail);
    public CatalogHistory[] History(string id) { _ = Get(id); return database.History(id); }
    public void UpdateSync(string id, string status, string detail)
    {
        mutations.Wait();
        try { database.Save(Get(id) with { SyncStatus = status, UpdatedUtc = DateTimeOffset.UtcNow }, "sync-" + status, detail, "Administrator"); }
        finally { mutations.Release(); }
    }
    public static void ValidateSelection(string[]? ids, int maxSelection)
    {
        if (maxSelection is < 1 or > 100000) throw new RequestException("maxSelection must be 1-100000.");
        if (ids is null || ids.Length < 1 || ids.Length > maxSelection)
            throw new RequestException($"Select between 1 and {maxSelection} catalog files.");
        foreach (var id in ids) StoragePaths.Id(id);
        if (ids.Distinct().Count() != ids.Length) throw new RequestException("Selection contains duplicate IDs.");
    }
    public async Task<CatalogEntry[]> Approve(CatalogApproveRequest request, string actor, CancellationToken token = default)
    {
        ValidateSelection(request.Ids, request.MaxSelection);
        if (!request.Confirm) throw new RequestException("Explicit confirmation is required for approval.");
        if (string.IsNullOrWhiteSpace(request.Reason) || request.Reason.Trim().Length is < 5 or > 2000)
            throw new RequestException("Provide a review reason of 5-2000 characters.");
        await mutations.WaitAsync(token);
        try
        {
            var changes = new List<(CatalogEntry Entry, string? Action, string Detail, string Actor)>();
            foreach (var id in request.Ids)
            {
                var entry = Get(id);
                if (request.SHA256 is not null && (!request.SHA256.TryGetValue(id, out var reviewedHash) ||
                    !entry.SHA256.Equals(reviewedHash, StringComparison.OrdinalIgnoreCase)))
                    throw new RequestException("The reviewed fingerprint changed. Refresh the findings before approval.", 409);
                var fingerprint = await Fingerprint(PhysicalPath(entry), token);
                if (fingerprint.Hash != entry.SHA256 || fingerprint.Length != entry.Length)
                {
                    database.Save(Invalidate(entry, fingerprint.Hash, fingerprint.Length), "content-changed", "Changed content cannot be approved.");
                    throw new RequestException("Physical content changed. Re-run verification before review.", 409);
                }
                var required = RequiredChecks(entry);
                if (!required.Eligible) throw new RequestException(required.Reason!, 409);
                foreach (var member in database.Unit(entry).Where(other => other.Id != entry.Id))
                {
                    var memberChecks = RequiredChecks(member);
                    if (!memberChecks.Eligible) throw new RequestException("A linked file has incomplete or unsafe checks: " + memberChecks.Reason, 409);
                    var memberFingerprint = await Fingerprint(PhysicalPath(member), token);
                    if (memberFingerprint.Hash != member.SHA256 || memberFingerprint.Length != member.Length)
                    {
                        database.Save(Invalidate(member, memberFingerprint.Hash, memberFingerprint.Length), "content-changed",
                            "A linked file changed before manual review.");
                        throw new RequestException("A linked file changed. Re-run verification before review.", 409);
                    }
                }
                if (entry.ReferenceStatus == "matched" && entry.IntegrityStatus != "Failed checks" && Text(entry.Evidence, "Header") != "Invalid")
                    throw new RequestException("This file has no approvable mismatch or missing reference.", 409);
                var approval = new CatalogApproval(entry.SHA256, request.Reason.Trim(), actor, DateTimeOffset.UtcNow);
                changes.Add((entry with { Approval = approval, UpdatedUtc = DateTimeOffset.UtcNow }, "manual-approved",
                    request.Reason.Trim(), actor));
            }
            database.SaveMany(changes);
            return request.Ids.Select(Get).ToArray();
        }
        catch (Exception ex) when (ex is RequestException or FileNotFoundException or DirectoryNotFoundException)
        {
            foreach (var entry in database.Entries().Where(entry => request.Ids.Contains(entry.Id)))
                database.Audit(entry, "manual-approval-rejected", $"{request.Reason.Trim()} Rejected: {ex.Message}", actor);
            if (ex is RequestException) throw;
            throw new RequestException("Physical file or linked dependency is missing. Refresh before review.", 409);
        }
        finally { mutations.Release(); }
    }
    private static CatalogEntry Invalidate(CatalogEntry entry, string hash, long length) => entry with
    {
        SHA256 = hash, Length = length, CheckStatus = "stale", CheckedUtc = null, Approval = null,
        CheckInvalidatedUtc = DateTimeOffset.UtcNow,
        ReferenceStatus = "unmatched", IntegrityStatus = "Unknown", Security = "Not checked",
        Organization = "Held for review", HoldReason = "Physical content changed; verification is required.",
        SyncStatus = "stale", UpdatedUtc = DateTimeOffset.UtcNow
    };
    private static async Task<(string Hash, long Length)> Fingerprint(string path, CancellationToken token, bool exclusive = true)
    {
        var modified = File.GetLastWriteTimeUtc(path);
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read,
            exclusive ? FileShare.Read : FileShare.ReadWrite | FileShare.Delete,
            128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
        var length = stream.Length;
        var hash = Convert.ToHexString(await SHA256.HashDataAsync(stream, token));
        if (stream.Length != length || !File.Exists(path) || File.GetLastWriteTimeUtc(path) != modified)
            throw new IOException("File changed while computing its fingerprint.");
        return (hash, length);
    }
    public async Task Refresh(CancellationToken token = default, bool forceHash = false)
    {
        await mutations.WaitAsync(token);
        try
        {
            // Read the complete source list before changing a snapshot. Storage outages are not deletions.
            var sources = new List<(string? Id, string Root)>();
            if (storage.Enabled)
            {
                var batches = await storage.Get<Batch[]>("batches", token);
                var existing = batches.Select(batch => batch.Id).ToHashSet(StringComparer.Ordinal);
                var removed = database.Entries().Where(entry => entry.BatchId is not null && !existing.Contains(entry.BatchId) && !entry.Missing)
                    .Select(entry => (entry with { Missing = true, CheckStatus = "stale", Approval = null, SyncStatus = "stale",
                        CheckInvalidatedUtc = DateTimeOffset.UtcNow, UpdatedUtc = DateTimeOffset.UtcNow },
                        (string?)"import-deleted", "Import no longer exists; retained history, invalidated publication eligibility.", "System"));
                database.SaveMany(removed);
                foreach (var batch in batches.Where(batch => batch.Prepared))
                {
                    if (batch.Lease is not null) continue;
                    sources.Add((batch.Id, storage.BatchRoot(batch.Id)));
                }
            }
            sources.Add((null, options.Root));
            foreach (var (id, root) in sources)
            {
                token.ThrowIfCancellationRequested();
                if (!Directory.Exists(root))
                {
                    logger.LogWarning("Catalog source {Source} is unavailable; retaining previous snapshot", id ?? "legacy");
                    continue;
                }
                try { await Reconcile(id, root, token, forceHash); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or JsonException or RequestException)
                { logger.LogError(ex, "Catalog reconciliation failed for {Source}; previous snapshot retained", id ?? "legacy"); }
            }
        }
        finally { mutations.Release(); }
    }
    private async Task Reconcile(string? batchId, string root, CancellationToken token, bool forceHash)
    {
        var manifestPath = Path.Combine(root, "_RomSorter", "collection.json");
        StoragePaths.AssertNoLinks(root, manifestPath);
        var manifest = await JobService.ReadFileJson(manifestPath);
        if (manifest.ValueKind is not (JsonValueKind.Null or JsonValueKind.Array))
            throw new JsonException("Collection index must be an array.");
        var evidenceByPath = new Dictionary<string, JsonElement>(Paths);
        if (manifest.ValueKind == JsonValueKind.Array)
            foreach (var evidence in manifest.EnumerateArray())
            {
                var relative = StoragePaths.Relative(Text(evidence, "RelativePath"));
                if (!evidenceByPath.TryAdd(relative, evidence.Clone())) throw new JsonException("Duplicate collection paths.");
            }
        var previous = database.Entries().Where(entry => entry.BatchId == batchId).ToArray();
        var previousByCollection = previous.Where(entry => entry.CollectionId.Length > 0).GroupBy(entry => entry.CollectionId)
            .ToDictionary(group => group.Key, group => group.ToArray());
        var previousByPath = previous.GroupBy(entry => entry.RelativePath, Paths)
            .ToDictionary(group => group.Key, group => group.ToArray(), Paths);
        var consumed = new HashSet<string>();
        var files = Inventory(root).ToArray();
        var fingerprints = new Dictionary<string, (string Hash, long Length)>(Paths);
        foreach (var file in files)
        {
            token.ThrowIfCancellationRequested();
            var info = new FileInfo(file.Full);
            var known = previousByPath.TryGetValue(file.Relative, out var candidates) && candidates.Length == 1 ? candidates[0] : null;
            fingerprints[file.Full] = !forceHash && known is { Missing: false, SHA256.Length: 64 }
                && known.Length == info.Length && known.FileModifiedUtc == info.LastWriteTimeUtc
                ? (known.SHA256, known.Length) : await Fingerprint(file.Full, token, false);
        }
        var hashCounts = fingerprints.Values.GroupBy(value => value.Hash).ToDictionary(group => group.Key, group => group.Count());
        var livePaths = files.Select(file => file.Relative).ToHashSet(Paths);
        var vanishedByHash = previous.Where(entry => !livePaths.Contains(entry.RelativePath)).GroupBy(entry => entry.SHA256)
            .ToDictionary(group => group.Key, group => group.ToArray());
        var changes = new List<(CatalogEntry Entry, string? Action, string Detail, string Actor)>();
        foreach (var file in files)
        {
            token.ThrowIfCancellationRequested();
            var fingerprint = fingerprints[file.Full];
            evidenceByPath.TryGetValue(file.Relative, out var evidence);
            var collectionId = Text(evidence, "CollectionId");
            var old = previousByCollection.TryGetValue(collectionId, out var byCollection)
                ? byCollection.FirstOrDefault(entry => !consumed.Contains(entry.Id)) : null;
            if (old is null && previousByPath.TryGetValue(file.Relative, out var byPath))
                old = byPath.FirstOrDefault(entry => !consumed.Contains(entry.Id));
            if (old is null)
            {
                // Only infer a move when one vanished file and one live file have that content.
                var candidates = vanishedByHash.TryGetValue(fingerprint.Hash, out var byHash)
                    ? byHash.Where(entry => !consumed.Contains(entry.Id)).ToArray() : [];
                if (candidates.Length == 1 && hashCounts[fingerprint.Hash] == 1)
                    old = candidates[0];
            }
            if (old is not null) consumed.Add(old.Id);
            var changed = old is not null && (old.SHA256 != fingerprint.Hash || old.Length != fingerprint.Length);
            var checkedText = Text(evidence, "CheckedUtc");
            var checkedUtc = DateTimeOffset.TryParse(checkedText, out var date) ? (DateTimeOffset?)date : null;
            var validEvidence = checkedUtc is not null &&
                fingerprint.Hash.Equals(Text(evidence, "SHA256"), StringComparison.OrdinalIgnoreCase);
            // Once stale, an old manifest cannot resurrect check clearance, even if bytes are restored.
            if (old?.CheckInvalidatedUtc is { } invalidated && checkedUtc <= invalidated)
                validEvidence = false;
            var entry = new CatalogEntry
            {
                Id = old?.Id ?? Guid.NewGuid().ToString("N"), BatchId = batchId, CollectionId = collectionId,
                GroupId = Text(evidence, "GroupId"), FileName = Path.GetFileName(file.Full),
                RelativePath = file.Relative, OriginalRelative = old?.OriginalRelative is { Length: > 0 } original ? original :
                    Text(evidence, "OriginalRelative") is { Length: > 0 } imported ? imported : file.Relative,
                Length = fingerprint.Length, SHA256 = fingerprint.Hash,
                Console = Text(evidence, "Console") is { Length: > 0 } console ? console : "-",
                ConsoleName = Text(evidence, "ConsoleName") is { Length: > 0 } name ? name : "Unknown / Needs identification",
                Category = Text(evidence, "Category") is { Length: > 0 } category ? category : "Unknown_Check_Manually",
                CheckedUtc = validEvidence ? checkedUtc : null,
                CheckInvalidatedUtc = validEvidence ? null : changed ? DateTimeOffset.UtcNow : old?.CheckInvalidatedUtc,
                CheckStatus = validEvidence ? "checked" : changed || old?.CheckStatus == "stale" ? "stale" : "unchecked",
                ReferenceStatus = Text(evidence, "Category") is "Hacks_Mods" or "Translations" ? "modified" :
                    validEvidence && (Flag(evidence, "DatMatch") || Flag(evidence, "HashMatch")) ? "matched" : "unmatched",
                IntegrityStatus = validEvidence ? Text(evidence, "IntegrityStatus") : "Unknown",
                Security = validEvidence ? Text(evidence, "Security") : "Not checked",
                Organization = Text(evidence, "Organization") is { Length: > 0 } organization ? organization : "Pending",
                HoldReason = validEvidence ? Text(evidence, "HoldReason") : "Verification is required.",
                Approval = !changed && old?.Approval?.SHA256 == fingerprint.Hash ? old.Approval : null,
                Evidence = evidence.ValueKind == JsonValueKind.Object ? evidence : JsonSerializer.SerializeToElement(new { }),
                DuplicateOf = Text(evidence, "DupOf") is { Length: > 0 } duplicate ? duplicate : null,
                SyncStatus = changed ? "stale" : old?.SyncStatus ?? "not-published", UpdatedUtc = DateTimeOffset.UtcNow,
                FileModifiedUtc = File.GetLastWriteTimeUtc(file.Full)
            };
            if (!validEvidence && (changed || old?.CheckStatus == "stale"))
                entry = entry with { Approval = null, HoldReason = "Physical content changed; verification is required." };
            var action = old is null ? "migrated" : changed ? "content-changed" :
                old.RelativePath != entry.RelativePath ? "location-changed" :
                old.CheckedUtc != entry.CheckedUtc ? "checks-updated" : old.Missing ? "file-restored" : null;
            changes.Add((entry, action, old is null ? "Added to permanent library; original files and recovery journals were retained." :
                action == "location-changed" ? $"{old.RelativePath} -> {entry.RelativePath}" : "Reconciled physical content and collection evidence.", "System"));
        }
        foreach (var missing in previous.Where(entry => !consumed.Contains(entry.Id) && !entry.Missing))
            changes.Add((missing with { Missing = true, Approval = null, CheckStatus = "stale", SyncStatus = "stale",
                CheckInvalidatedUtc = DateTimeOffset.UtcNow,
                UpdatedUtc = DateTimeOffset.UtcNow }, "file-missing", "File absent from accessible source; catalog history retained.", "System"));
        database.SaveMany(changes);
    }
    private static IEnumerable<(string Full, string Relative)> Inventory(string root)
    {
        var reserved = new HashSet<string>(["_RomSorter", "_Unpacked archives", "_Quarantine", "_Duplicates", "_Not valid"], Paths);
        var pending = new Stack<string>();
        pending.Push(root);
        while (pending.TryPop(out var directory))
        {
            StoragePaths.AssertNoLinks(root, directory);
            foreach (var path in Directory.EnumerateFileSystemEntries(directory))
            {
                StoragePaths.AssertNoLinks(root, path);
                if (Directory.Exists(path))
                {
                    if (!reserved.Contains(Path.GetFileName(path))) pending.Push(path);
                }
                else yield return (path, Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/'));
            }
        }
    }
}
