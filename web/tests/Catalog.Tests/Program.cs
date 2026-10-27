using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.Logging.Abstractions;
using RomChecker.Web;
using RomChecker.Web.Features.Catalog;
using RomChecker.Web.Features.Library;
using RomChecker.Web.Features.Settings;
using RomChecker.Web.Features.Storage;
using RomChecker.Web.Infrastructure;

var repo = Path.GetFullPath(args.Length > 0 ? args[0] : ".");
while (!File.Exists(Path.Combine(repo, "RomSorter.ps1")) && Directory.GetParent(repo) is { } parent)
    repo = parent.FullName;
if (!File.Exists(Path.Combine(repo, "RomSorter.ps1"))) throw new InvalidOperationException("Run the catalog tests from this repository.");
var fixture = Path.Combine(repo, ".tools", "catalog-tests-" + Guid.NewGuid().ToString("N"));
var root = Path.Combine(fixture, "legacy");
var data = Path.Combine(fixture, "data");
var storageRoot = Path.Combine(fixture, "storage");
Directory.CreateDirectory(root);
Directory.CreateDirectory(data);
Directory.CreateDirectory(storageRoot);
var oldStorage = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_ROOT");
var oldUrl = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_URL");
var oldToken = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_TOKEN");
Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_ROOT", storageRoot);
Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_URL", "http://catalog-test.invalid");
Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_TOKEN", new string('x', 32));
var passed = 0;
void Assert(bool condition, string message)
{
    if (!condition) throw new Exception("FAILED: " + message);
    passed++;
}
async Task Reject(Func<Task> action, string message)
{
    try { await action(); }
    catch (RequestException) { passed++; return; }
    throw new Exception("FAILED (expected rejection): " + message);
}
try
{
    var powerShell = Environment.GetEnvironmentVariable("CATALOG_TEST_POWERSHELL") ?? "pwsh";
    var options = new WebOptions(root, data, repo, powerShell, new string('p', 20), "", TimeSpan.FromMinutes(2));
    var handler = new StorageHandler();
    var storage = new StorageClient(new ClientFactory(handler), options);
    var database = new CatalogDatabase(options);
    CanonicalCatalog NewCatalog() => new(database, options, storage, NullLogger<CanonicalCatalog>.Instance);
    var catalog = NewCatalog();
    var romPath = Path.Combine(root, "Review.nes");
    await File.WriteAllBytesAsync(romPath, [1, 2, 3, 4]);
    var sourceId = Guid.NewGuid().ToString("N");
    async Task WriteEvidence(string path, string category = "Not_In_DAT", string security = "Clean",
        string integrity = "Internal checks passed (not authenticity)", string antivirus = "Completed - no detections",
        string online = "Skipped", bool dependencies = true, string? group = null, string? matched = null)
    {
        var index = Path.Combine(root, "_RomSorter");
        Directory.CreateDirectory(index);
        var evidence = new Dictionary<string, object?>
        {
            ["CollectionId"] = sourceId, ["GroupId"] = group ?? sourceId,
            ["OriginalRelative"] = "Review.nes", ["RelativePath"] = Path.GetRelativePath(root, path).Replace('\\', '/'),
            ["FileName"] = Path.GetFileName(path), ["Console"] = "NES", ["ConsoleName"] = "Nintendo Entertainment System",
            ["Category"] = category, ["Length"] = new FileInfo(path).Length,
            ["SHA256"] = Convert.ToHexString(SHA256.HashData(await File.ReadAllBytesAsync(path))),
            ["CheckedUtc"] = DateTimeOffset.UtcNow.ToString("O"), ["IntegrityStatus"] = integrity,
            ["Security"] = security, ["AntivirusStatus"] = antivirus, ["OnlineMalwareStatus"] = online,
            ["IdentificationStatus"] = "Unknown", ["DependenciesComplete"] = dependencies, ["DependencyConflict"] = false,
            ["Organization"] = "Held for review", ["DatMatch"] = matched,
            ["CheckPolicy"] = new Dictionary<string, object> { ["OnlineCheck"] = "Off" }
        };
        await File.WriteAllTextAsync(Path.Combine(index, "collection.json"), Json.Serialize(new[] { evidence }));
    }
    await WriteEvidence(romPath);
    await catalog.Refresh();
    var entry = catalog.Entries().Single();
    Assert(Json.Serialize(entry).Contains("\"sha256\"") && !Json.Serialize(entry).Contains("\"shA256\""), "SHA256 JSON contract uses sha256.");
    Assert(entry.CheckStatus == "checked" && !entry.PublishEligible, "Missing reference remains independent from completed checks.");
    Assert(entry.Evidence.GetProperty("OriginalRelative").GetString() == "Review.nes", "Original uppercase evidence is retained.");
    await Reject(() => Task.Run(() => catalog.PhysicalPath(entry with { RelativePath = "../outside.nes" })), "Caller-created entries cannot redirect physical resolution.");
    var stableId = entry.Id;
    await catalog.Refresh();
    Assert(catalog.History(stableId).Length == 1, "Repeated migration is idempotent and audit history does not duplicate.");
    catalog = NewCatalog();
    Assert(catalog.Get(stableId).SHA256 == entry.SHA256, "Catalog and stable identity survive restart.");
    await Reject(() => catalog.Approve(new([stableId], "Reviewed homebrew", false), "Administrator"), "Explicit confirmation required.");
    await Reject(() => catalog.Approve(new([stableId], "Reviewed old fingerprint.", true, SHA256: new() { [stableId] = new string('0', 64) }),
        "Administrator"), "Stale displayed review fingerprints are rejected.");
    var approved = await catalog.Approve(new([stableId], "Reviewed known homebrew; no reference available.", true), "Administrator");
    Assert(approved.Single().PublishEligible && approved.Single().Approval?.SHA256 == entry.SHA256, "Approval is fingerprint-bound and changes publication policy.");
    Assert((await catalog.EnsurePublishable(approved.Single())).Id == stableId, "Publication rehashes an approved physical file.");
    Assert(catalog.History(stableId).Any(item => item.Actor == "Administrator" && item.Action == "manual-approved" && item.SHA256 == entry.SHA256),
        "Audit includes administrator, reason, action, and physical fingerprint.");
    File.Move(romPath, Path.Combine(root, "Renamed.nes"));
    romPath = Path.Combine(root, "Renamed.nes");
    File.Delete(Path.Combine(root, "_RomSorter", "collection.json"));
    await catalog.Refresh();
    Assert(catalog.Entries().Single().Id == stableId, "A unique physical move retains canonical identity without relying on filename.");
    await WriteEvidence(romPath);
    await catalog.Refresh();
    var beforeChange = catalog.Get(stableId);
    await catalog.Approve(new([stableId], "Reviewed after rename, same physical bytes.", true), "Administrator");
    beforeChange = catalog.Get(stableId);
    var beforeLength = new FileInfo(romPath).Length;
    await File.WriteAllBytesAsync(romPath, [4, 3, 2, 1]);
    Assert(new FileInfo(romPath).Length == beforeLength, "Content mutation fixture preserves file size.");
    await Reject(() => catalog.EnsurePublishable(beforeChange), "Changed content cannot be published.");
    Assert(catalog.Get(stableId).Approval is null && catalog.Get(stableId).CheckStatus == "stale", "Content changes revoke approval and check eligibility.");
    await File.WriteAllBytesAsync(romPath, [1, 2, 3, 4]);
    await catalog.Refresh();
    Assert(catalog.Get(stableId).CheckStatus == "stale", "Restoring old bytes cannot resurrect old check clearance.");
    await Task.Delay(20);
    await WriteEvidence(romPath);
    await catalog.Refresh();
    Assert(catalog.Get(stableId).CheckStatus == "checked", "Fresh verification clears a stale epoch.");
    foreach (var unsafeCase in new[]
    {
        ("Suspicious", "Completed - no detections", "Skipped", true),
        ("Malicious", "Completed - no detections", "Skipped", true),
        ("Clean", "Incomplete", "Skipped", true),
        ("Clean", "Disabled", "Skipped", true),
        ("Clean", "Completed - no detections", "Incomplete", true),
        ("Clean", "Completed - no detections", "Skipped", false)
    })
    {
        await WriteEvidence(romPath, security: unsafeCase.Item1, antivirus: unsafeCase.Item2,
            online: unsafeCase.Item3, dependencies: unsafeCase.Item4);
        await catalog.Refresh();
        await Reject(() => catalog.Approve(new([stableId], "Cannot bypass safety checks.", true), "Administrator"),
            "Approvals cannot bypass suspicious/malicious/incomplete/dependency findings.");
    }
    await WriteEvidence(romPath, integrity: "Unknown");
    await catalog.Refresh();
    await Reject(() => catalog.Approve(new([stableId], "No supported integrity evidence available.", true), "Administrator"),
        "Manual review cannot replace missing supported integrity checks.");
    await WriteEvidence(romPath, category: "Invalid_Corrupt", integrity: "Failed checks", matched: "Known matching reference");
    await catalog.Refresh();
    Assert(!catalog.Get(stableId).PublishEligible, "A reference fingerprint never bypasses failed integrity checks.");
    await catalog.Approve(new([stableId], "Known internal checksum modification, reviewed.", true), "Administrator");
    Assert(catalog.Get(stableId).PublishEligible, "A clean checked internal mismatch can be explicitly approved.");
    var originals = Path.Combine(storageRoot, "batches", Guid.NewGuid().ToString("N"), "originals");
    Directory.CreateDirectory(originals);
    await File.WriteAllTextAsync(Path.Combine(originals, "untouched.txt"), "preserve");
    handler.Unavailable = true;
    await Reject(() => catalog.Refresh(), "Storage outage is surfaced.");
    Assert(catalog.Get(stableId).Approval is not null, "Storage outage retains previous catalog snapshot.");
    handler.Unavailable = false;
    Assert(await File.ReadAllTextAsync(Path.Combine(originals, "untouched.txt")) == "preserve", "Migration does not write original imports.");
    File.Delete(romPath);
    await catalog.Refresh();
    Assert(catalog.Get(stableId).Missing && !catalog.Get(stableId).PublishEligible, "Disappeared files retain identity/history and cannot publish.");
    Assert(catalog.List(new(Checks: "unchecked")).Ids.Contains(stableId), "Unchecked scope includes stale and missing entries.");
    await Reject(() => Task.Run(() => CanonicalCatalog.ValidateSelection([stableId, stableId], 2)), "Duplicate selections rejected.");
    await Reject(() => Task.Run(() => CanonicalCatalog.ValidateSelection([stableId], 0)), "Caller-controlled scope limit is bounded.");

    // Execute two independent prepared batches through the real engine and one durable dispatcher.
    byte[] Nes()
    {
        var bytes = new byte[40976];
        bytes[0] = 0x4e; bytes[1] = 0x45; bytes[2] = 0x53; bytes[3] = 0x1a; bytes[4] = 2; bytes[5] = 1;
        return bytes;
    }
    foreach (var name in new[] { "Batch one", "Batch two" })
    {
        var id = Guid.NewGuid().ToString("N");
        handler.Batches.Add(new(id, name, "ready", DateTimeOffset.UtcNow, Prepared: true));
        var tree = storage.BatchRoot(id);
        Directory.CreateDirectory(tree);
        await File.WriteAllBytesAsync(Path.Combine(tree, "Selected.nes"), Nes());
        await File.WriteAllBytesAsync(Path.Combine(tree, "Unselected.nes"), Nes());
    }
    await catalog.Refresh();
    var batchEntries = catalog.Entries().Where(item => item.BatchId is not null).ToArray();
    Assert(batchEntries.Length == 4 && batchEntries.All(item => item.CheckStatus == "unchecked"), "Prepared-undetected imports are visible as pending permanent entries.");
    Assert(batchEntries.Count(item => item.DuplicateOf is not null) == batchEntries.Length - batchEntries.Select(item => item.SHA256).Distinct().Count(),
        "Exact duplicate content is reported across imports without merging physical files.");
    Assert(batchEntries.All(item => catalog.Get(item.Id).DuplicateOf == item.DuplicateOf), "Detail and list duplicate evidence remain consistent.");
    var selectedIds = batchEntries.Where(item => item.FileName == "Selected.nes").Select(item => item.Id).ToArray();
    var store = new Store(options);
    var paths = new LibraryPaths(options);
    var jobs = new JobService(store, options, new SettingsValidator(options, paths), paths,
        new EngineRunner(options, storage), storage, NullLogger<JobService>.Instance);
    var service = new CatalogVerificationService(catalog, database, jobs, store, NullLogger<CatalogVerificationService>.Instance);
    var settings = new EngineSettings { DefenderScan = false, Hasheous = "Off", AutoDat = false,
        IdentifyUnknown = false, RetailOnly = false, RequireDatMatch = false, ResumeScans = false };
    var queued = service.Enqueue(new(selectedIds, settings, MaxSelection: 2));
    Assert(database.Verifications().Single().Steps.Length == 2, "Multi-batch scope is durable before execution.");
    // Reconstruct dispatcher before start to verify the queue is database-backed, not an in-memory Channel.
    service = new(catalog, new CatalogDatabase(options), jobs, store, NullLogger<CatalogVerificationService>.Instance);
    using var timeout = new CancellationTokenSource(TimeSpan.FromMinutes(3));
    await jobs.StartAsync(timeout.Token);
    await service.StartAsync(timeout.Token);
    try
    {
        CatalogVerification current;
        do
        {
            await Task.Delay(200, timeout.Token);
            current = service.Get(queued.Id);
        } while (current.Status is "queued" or "running");
        if (current.Status != "completed")
            foreach (var job in store.All()) Console.Error.WriteLine($"{job.Id} ({job.Action}): {await jobs.Log(job.Id)}");
        Assert(current.Status == "completed", "Sequential multi-batch verification completed: " + current.Error);
        Assert(current.Steps.All(step => step.Status == "completed" && step.JobId is not null), "Each durable scope step records its completed job.");
        Assert(selectedIds.All(id => catalog.Get(id).CheckStatus == "checked"), "Selected catalog files are verified.");
        Assert(catalog.Entries().Where(item => item.BatchId is not null && item.FileName == "Unselected.nes")
            .All(item => item.CheckedUtc is null), "Unselected files retain unchecked state.");
        Assert(handler.MaxLeases == 1, "Batches are leased and verified strictly sequentially.");
        Assert(selectedIds.All(id => !catalog.Get(id).PublishEligible), "Disabled antivirus never results in publication clearance.");
        Assert(catalog.Get(selectedIds[0]).Evidence.GetProperty("DependenciesComplete").GetBoolean(), "Engine persists explicit dependency completeness.");
        var target = catalog.Get(selectedIds[0]);
        await File.WriteAllTextAsync(Path.Combine(storage.BatchRoot(target.BatchId!), "Selected.srm"), "save companion");
        await catalog.Refresh();
        var scoped = service.Enqueue(new([target.Id], settings, MaxSelection: 1));
        do
        {
            await Task.Delay(200, timeout.Token);
            current = service.Get(scoped.Id);
        } while (current.Status is "queued" or "running");
        Assert(current.Status == "failed" && current.Error!.Contains("maxSelection"), "Newly detected linked files cannot bypass the caller's explicit scope limit.");
        Assert(catalog.Entries().Single(item => item.BatchId == target.BatchId && item.FileName == "Selected.srm").CheckedUtc is null,
            "The over-limit unit is not partially verified or moved.");
        var apiBuilder = WebApplication.CreateBuilder(new WebApplicationOptions { ContentRootPath = repo });
        apiBuilder.Logging.ClearProviders();
        apiBuilder.WebHost.UseUrls("http://127.0.0.1:0");
        apiBuilder.Services.AddSingleton(catalog);
        apiBuilder.Services.AddSingleton(service);
        await using var api = apiBuilder.Build();
        api.MapGroup("/api").MapCatalog();
        await api.StartAsync(timeout.Token);
        try
        {
            var address = api.Services.GetRequiredService<IServer>().Features.Get<IServerAddressesFeature>()!.Addresses.Single();
            using var client = new HttpClient { BaseAddress = new Uri(address) };
            var response = await client.GetAsync("/api/catalog", timeout.Token);
            Assert(response.IsSuccessStatusCode, "Catalog endpoint binds optional query defaults.");
            var page = await response.Content.ReadFromJsonAsync<CatalogPage>(Json.Options, timeout.Token);
            Assert(page!.Size == 100 && page.Ids.Length == catalog.Entries().Length, "Catalog API exposes all filtered IDs independently of pagination.");
            var filtered = await client.GetFromJsonAsync<CatalogPage>("/api/catalog?q=Selected&size=1&checks=checked", Json.Options, timeout.Token);
            Assert(filtered!.Items.Length == 1 && filtered.Ids.Length == 2, "Catalog API applies scope filters before pagination.");
            catalog.UpdateSync(selectedIds[0], "awaiting-scan", "Queued for external scan.");
            var syncFiltered = await client.GetFromJsonAsync<CatalogPage>("/api/catalog?syncStatus=awaiting-scan&size=1", Json.Options, timeout.Token);
            Assert(syncFiltered!.Filtered == 1 && syncFiltered.Ids.SequenceEqual([selectedIds[0]]) &&
                syncFiltered.Groups.Sum(group => group.Total) == 1, "Sync-state filtering applies to items, groups, and all-filtered IDs.");
            var history = await client.GetFromJsonAsync<CatalogHistory[]>($"/api/catalog/{stableId}/history", Json.Options, timeout.Token);
            Assert(history!.Any(item => item.Action == "manual-approved"), "Audit history endpoint preserves previous approvals.");
        }
        finally { await api.StopAsync(CancellationToken.None); }
    }
    finally
    {
        await service.StopAsync(CancellationToken.None);
        await jobs.StopAsync(CancellationToken.None);
        service.Dispose();
        jobs.Dispose();
    }
    Console.WriteLine($"PASS: {passed} catalog assertions");
}
finally
{
    Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_ROOT", oldStorage);
    Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_URL", oldUrl);
    Environment.SetEnvironmentVariable("ROMCHECKER_STORAGE_TOKEN", oldToken);
    Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
    if (Directory.Exists(fixture)) Directory.Delete(fixture, true);
}

sealed class ClientFactory(HttpMessageHandler handler) : IHttpClientFactory
{
    public HttpClient CreateClient(string name) => new(handler, false);
}
sealed class StorageHandler : HttpMessageHandler
{
    public List<Batch> Batches { get; } = [];
    public bool Unavailable { get; set; }
    public int MaxLeases { get; private set; }
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        if (Unavailable) throw new HttpRequestException("Fixture unavailable");
        lock (Batches)
        {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(Batches.ToArray(), options: Json.Options) };
        }
        var parts = request.RequestUri!.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var lease = await request.Content!.ReadFromJsonAsync<LeaseRequest>(Json.Options, token);
        lock (Batches)
        {
            var index = Batches.FindIndex(batch => batch.Id == parts[^2]);
            if (index < 0) return new(HttpStatusCode.NotFound) { Content = JsonContent.Create(new { error = "Batch not found" }) };
            if (parts[^1] == "lease" && Batches[index].Lease is not null)
                return new(HttpStatusCode.Conflict) { Content = JsonContent.Create(new { error = "Batch leased" }) };
            Batches[index] = Batches[index] with { Lease = parts[^1] == "lease" ? lease!.JobId : null };
            MaxLeases = Math.Max(MaxLeases, Batches.Count(batch => batch.Lease is not null));
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { ok = true }) };
        }
    }
}
