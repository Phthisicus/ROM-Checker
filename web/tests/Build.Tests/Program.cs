using System.Net;
using System.Text.Json;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging.Abstractions;
using RomChecker.Web;
using RomChecker.Web.Features.Settings;

var assertions = 0;
void Check(bool condition, string message)
{
    assertions++;
    if (!condition) throw new Exception(message);
}
void Reject(Action action, string message)
{
    try { action(); } catch (InvalidOperationException) { assertions++; return; }
    throw new Exception(message);
}
var directory = Path.Combine(Path.GetTempPath(), "romchecker-build-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(directory);
try
{
    var identity = new BuildIdentity("1.3.0-development.142", 142, 1, "development",
        new string('a', 40), DateTimeOffset.Parse("2026-10-27T20:00:00Z"),
        "https://github.com/Phthisicus/ROM-Checker/actions/runs/123", 1);
    var path = Path.Combine(directory, "build-info.json");
    File.WriteAllText(path, JsonSerializer.Serialize(identity, Json.Options));
    Environment.SetEnvironmentVariable("ROMCHECKER_VERSION", "spoofed");
    Check(BuildIdentity.Load(path) == identity, "Baked identity must ignore runtime overrides");
    File.WriteAllText(path, JsonSerializer.Serialize(identity with { BuildNumber = 0 }, Json.Options));
    Reject(() => BuildIdentity.Load(path), "Reject incomplete published identity");
    File.WriteAllText(path, JsonSerializer.Serialize(identity with { Channel = "stable" }, Json.Options));
    Reject(() => BuildIdentity.Load(path), "Reject channel/version mismatch");
    var internalIdentity = new BuildIdentity("1.3.0-internal.142+aaaaaaa", 142, 1, "internal",
        new string('a', 40), identity.BuiltUtc, identity.WorkflowUrl, 1);
    File.WriteAllText(path, JsonSerializer.Serialize(internalIdentity, Json.Options));
    Check(BuildIdentity.Load(path) == internalIdentity, "Load SemVer internal build identity");
    File.WriteAllText(path, JsonSerializer.Serialize(internalIdentity with { Version = "1.3.0-internal.142" }, Json.Options));
    Reject(() => BuildIdentity.Load(path), "Reject internal version without commit metadata");
    Check(BuildIdentity.Load(Path.Combine(directory, "absent.json")).Channel == "local", "Source builds are explicitly local");
    var release = new ReleaseInfo(1, identity.Version, identity.Channel, identity.Commit, null,
        "Installed release notes.", ["Back up your data."], []);
    var releasePath = Path.Combine(directory, "release-info.json");
    File.WriteAllText(releasePath, JsonSerializer.Serialize(release, Json.Options));
    Check(ReleaseInfo.Load(releasePath, identity).Notes == release.Notes, "Installed notes load offline");
    File.WriteAllText(releasePath, JsonSerializer.Serialize(new
    {
        release.MetadataFormatVersion, release.Version, release.Channel, release.Commit,
        release.ReleaseUrl, release.Notes, release.UpgradeNotes, release.Limitations
    }, Json.Options));
    Check(ReleaseInfo.Load(releasePath, identity).KnownIssues.Length == 0, "Older metadata does not require known issues");
    var withIssues = release with { KnownIssues = ["Some artwork loads slowly."] };
    File.WriteAllText(releasePath, JsonSerializer.Serialize(withIssues, Json.Options));
    Check(ReleaseInfo.Load(releasePath, identity).KnownIssues.SequenceEqual(withIssues.KnownIssues), "Known issues survive offline metadata loading");
    Reject(() => (release with { KnownIssues = [new string('x', 4001)] }).Validate(identity.Version, identity.Channel, identity.Commit),
        "Reject oversized issue metadata");
    Reject(() => release.Validate("1.0.0", identity.Channel, identity.Commit), "Reject notes for another image");
    Reject(() => (release with { MetadataFormatVersion = 2 }).Validate(identity.Version, identity.Channel, identity.Commit),
        "Metadata format is independent of database schema");
    Reject(() => (release with { ReleaseUrl = "https://example.invalid/" }).Validate(identity.Version, identity.Channel, identity.Commit),
        "Reject external release links");

    Check(DatabaseCompatibility.Initialize(directory).Version == 1, "Adopt unversioned schema");
    using (var db = new SqliteConnection($"Data Source={Path.Combine(directory, "romchecker.db")}"))
    {
        db.Open();
        using var command = db.CreateCommand();
        command.CommandText = "CREATE TABLE preservation_test(value TEXT); INSERT INTO preservation_test VALUES('keep');";
        command.ExecuteNonQuery();
        Check(DatabaseCompatibility.Initialize(directory).Version == 1, "Current schema is accepted");
        command.CommandText = "SELECT value FROM preservation_test";
        Check((string?)command.ExecuteScalar() == "keep", "Schema adoption must preserve data");
        command.CommandText = "PRAGMA user_version=2";
        command.ExecuteNonQuery();
        Reject(() => DatabaseCompatibility.Initialize(directory), "Reject future schema");
        command.CommandText = "PRAGMA user_version";
        Check(Convert.ToInt32(command.ExecuteScalar()) == 2, "Never downgrade the schema marker");
    }

    Check(UpdateChecker.Evaluate(identity, "1.3.0-development.143", "development", new string('b', 40), 143, 1).Status == "available", "Newer development version");
    Reject(() => UpdateChecker.Evaluate(identity, identity.Version, "development", identity.Commit, 9999, 1), "Reject inconsistent development version and counter");
    Check(UpdateChecker.Evaluate(identity, "1.2.0-development.9999", "development", new string('b', 40), 9999, 1).Status == "current", "Older base version cannot create update");
    Check(UpdateChecker.Evaluate(identity, "1.4.0-development.1", "development", new string('b', 40), 1, 2).SchemaCompatible == false, "Warn for schema changes");
    Reject(() => UpdateChecker.Evaluate(identity, "1.3.0-beta.1", "beta", new string('b', 40), 1, 1), "Never cross channels");
    Reject(() => UpdateChecker.Evaluate(identity, identity.Version, "development", new string('b', 40), 142, 1), "Reject conflicting source identity");
    var stable = identity with { Version = "1.3.0", Channel = "stable" };
    Check(UpdateChecker.Evaluate(stable, stable.Version, "stable", stable.Commit, 9999, 1).Status == "current", "Build counter alone cannot create update");
    Check(UpdateChecker.Evaluate(stable, "1.3.1", "stable", new string('b', 40), 1, 1).Status == "available", "Stable version comparison");
    var beta = identity with { Version = "1.3.0-beta.9", Channel = "beta" };
    Check(UpdateChecker.Evaluate(beta, "1.3.0-beta.10", "beta", new string('b', 40), 1, 1).Status == "available", "Numeric beta comparison");
    var promoted = UpdateChecker.EvaluateManifest(identity, "beta", "1.3.0-beta.1",
        "1.3.0-internal.143+bbbbbbb", new string('b', 40), 143, "sha256:" + new string('c', 64),
        "https://github.com/Phthisicus/ROM-Checker/releases/tag/v1.3.0-beta.1",
        "1.3.0-beta.1", 1, DateTimeOffset.Parse("2026-11-11T12:00:00Z"));
    Check(promoted.Status == "available" && promoted.Version == "1.3.0-beta.1"
        && promoted.BuildVersion == "1.3.0-internal.143+bbbbbbb",
        "Promoted channel identity remains separate from immutable image identity");
    var samePromotion = UpdateChecker.EvaluateManifest(internalIdentity, "beta", "1.3.0-beta.1",
        internalIdentity.Version, internalIdentity.Commit, 142, "sha256:" + new string('c', 64),
        "https://github.com/Phthisicus/ROM-Checker/releases/tag/v1.3.0-beta.1",
        "1.3.0-beta.1", 1, DateTimeOffset.Parse("2026-11-11T12:00:00Z"));
    Check(samePromotion.Status == "current" && samePromotion.Version == "1.3.0-beta.1",
        "An exact promoted digest reports the channel version without rebuilding");
    Reject(() => UpdateChecker.EvaluateManifest(identity, "beta", "1.4.0-beta.1",
        "1.3.0-internal.143+bbbbbbb", new string('b', 40), 143, "sha256:" + new string('c', 64),
        "https://github.com/Phthisicus/ROM-Checker/releases/tag/v1.4.0-beta.1",
        "1.4.0-beta.1", 1, DateTimeOffset.Parse("2026-11-11T12:00:00Z")),
        "Reject release versions unrelated to the immutable build");
    Check(UpdateChecker.EvaluateManifest(identity, "stable", "1.4.0",
        "1.4.0-internal.1+bbbbbbb", new string('b', 40), 1, "sha256:" + new string('c', 64),
        "https://github.com/Phthisicus/ROM-Checker/releases/tag/v1.4.0",
        "1.4.0", 1, DateTimeOffset.Parse("2026-11-11T12:00:00Z")).Status == "available",
        "A newer stable release is available even when its source build number is lower");
    Check(UpdateChecker.EvaluateManifest(identity, "stable", "1.2.0",
        "1.2.0-internal.999+bbbbbbb", new string('b', 40), 999, "sha256:" + new string('c', 64),
        "https://github.com/Phthisicus/ROM-Checker/releases/tag/v1.2.0",
        "1.2.0", 1, DateTimeOffset.Parse("2026-11-11T12:00:00Z")).Status == "current",
        "A higher build counter cannot make an older release target an update");

    var registry = new RegistryFixture();
    using var http = new HttpClient(registry);
    var checker = new UpdateChecker(http, identity, NullLogger<UpdateChecker>.Instance);
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", null);
    Check((await checker.Check(default)).Status == "disabled" && registry.Requests == 0, "Disabled checks must not contact registry");
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", "true");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_USERNAME", "fixture");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_TOKEN", "fixture-token");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHANNEL", "internal");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHECK_INTERVAL_HOURS", "12");
    var available = await checker.Check(default);
    Check(available.Status == "available" && available.Version == "1.3.0-internal.143+bbbbbbb"
        && available.ImageDigest == "sha256:" + new string('c', 64)
        && available.ImageRepository == "ghcr.io/phthisicus/rom-checker",
        "Registry update manifest reports promoted version and exact application digest");
    Check(registry.DownloadHadNoCredentials, "Do not forward credentials to signed CDN");
    registry.WrongManifestIdentity = true;
    try { await checker.Check(default); throw new Exception("Mismatched channel manifest identity must fail."); }
    catch (RequestException ex) { Check(ex.Status == 502, "Reject manifest that does not match the image build identity"); }
    registry.WrongManifestIdentity = false;

    var builder = Host.CreateApplicationBuilder();
    builder.Services.AddSingleton(checker);
    using var host = builder.Build();
    var clock = new TestClock();
    using var monitor = new UpdateMonitor(host.Services.GetRequiredService<IServiceScopeFactory>(), identity,
        NullLogger<UpdateMonitor>.Instance, clock);
    Check(monitor.IntervalHours == 12, "Scheduled update interval is configurable");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHECK_INTERVAL_HOURS", "0");
    Reject(() => new UpdateMonitor(host.Services.GetRequiredService<IServiceScopeFactory>(), identity,
        NullLogger<UpdateMonitor>.Instance, clock), "Reject out-of-range scheduled update interval");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHECK_INTERVAL_HOURS", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", null);
    var requests = registry.Requests;
    Check((await monitor.Check(default)).Status == "disabled" && requests == registry.Requests, "Cached checks respect opt-in");
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", "true");
    await monitor.Check(default);
    requests = registry.Requests;
    await Task.WhenAll(monitor.Check(default), monitor.Check(default));
    Check(requests == registry.Requests, "Concurrent checks are shared and rate limited");
    Check(monitor.Status.LastSuccessUtc == clock.GetUtcNow(), "Successful checks expose their timestamp");
    registry.Fail = true;
    clock.Advance(TimeSpan.FromMinutes(2));
    var stale = await monitor.Check(default);
    Check(stale.Status == "error" && stale.Stale && stale.Result?.Status == "available"
        && stale.LastSuccessUtc < stale.LastAttemptUtc, "Failed checks retain timestamped stale results, never success");
    try { await checker.Check(default); throw new Exception("Registry failure must not look current"); }
    catch (RequestException ex) { Check(ex.Status == 502, "Explicit update failure status"); }
    Console.WriteLine($"Build identity, schema and update tests: {assertions} assertions passed.");
}
finally
{
    Environment.SetEnvironmentVariable("ROMCHECKER_VERSION", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_USERNAME", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_TOKEN", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHANNEL", null);
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_CHECK_INTERVAL_HOURS", null);
    SqliteConnection.ClearAllPools();
    Directory.Delete(directory, true);
}

sealed class RegistryFixture : HttpMessageHandler
{
    public int Requests { get; private set; }
    public bool DownloadHadNoCredentials { get; private set; }
    public bool Fail { get; set; }
    public bool WrongManifestIdentity { get; set; }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests++;
        if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
        object body;
        if (request.RequestUri!.Host == "pkg-containers.githubusercontent.com")
        {
            DownloadHadNoCredentials = request.Headers.Authorization is null;
            body = new { config = new { Labels = new Dictionary<string, string>
            {
                ["io.romchecker.manifest-format-version"] = "1",
                ["io.romchecker.channel"] = "internal",
                ["io.romchecker.version"] = "1.3.0-internal.143+bbbbbbb",
                ["io.romchecker.build-version"] = "1.3.0-internal.143+bbbbbbb",
                ["io.romchecker.image"] = "ghcr.io/phthisicus/rom-checker",
                ["io.romchecker.image-tag"] = "1.3.0-internal.143-bbbbbbb",
                ["io.romchecker.image-digest"] = "sha256:" + new string('c', 64),
                ["io.romchecker.schema-version"] = "1",
                ["io.romchecker.commit"] = new string(WrongManifestIdentity ? 'a' : 'b', 40),
                ["io.romchecker.build-number"] = "143",
                ["io.romchecker.published-utc"] = "2026-11-11T12:00:00Z",
                ["io.romchecker.release-notes-url"] = "https://github.com/Phthisicus/ROM-Checker/commit/" + new string('b', 40)
            } } };
        }
        else if (request.RequestUri.AbsolutePath == "/token")
        {
            if (request.Headers.Authorization?.Scheme != "Basic") throw new Exception("Expected private-package authentication");
            body = new { token = "fixture-registry-token" };
        }
        else
        {
            if (request.Headers.Authorization?.ToString() != "Bearer fixture-registry-token") throw new Exception("Expected scoped registry token");
            if (request.RequestUri.AbsolutePath.Contains("/blobs/"))
            {
                var redirect = new HttpResponseMessage(HttpStatusCode.TemporaryRedirect);
                redirect.Headers.Location = new Uri("https://pkg-containers.githubusercontent.com/config");
                return Task.FromResult(redirect);
            }
            body = new { config = new { digest = "sha256:" + new string('d', 64) } };
        }
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), System.Text.Encoding.UTF8, "application/json")
        });
    }
}

sealed class TestClock : TimeProvider
{
    private DateTimeOffset now = DateTimeOffset.Parse("2026-11-11T12:00:00Z");
    public override DateTimeOffset GetUtcNow() => now;
    public void Advance(TimeSpan interval) => now += interval;
}
