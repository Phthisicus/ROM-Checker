using System.Net;
using System.Text;
using System.Text.Json;
using System.Formats.Tar;
using System.IO.Compression;
using System.Security.Cryptography;
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
    Check(BuildIdentity.Load(Path.Combine(directory, "absent.json")).Channel == "local", "Source builds are explicitly local");
    var release = new ReleaseInfo(1, identity.Version, identity.Channel, identity.Commit, null,
        "Installed release notes.", ["Back up your data."], []);
    var releasePath = Path.Combine(directory, "release-info.json");
    File.WriteAllText(releasePath, JsonSerializer.Serialize(release, Json.Options));
    Check(ReleaseInfo.Load(releasePath, identity).Notes == release.Notes, "Installed notes load offline");
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

    var registry = new RegistryFixture();
    using var http = new HttpClient(registry);
    var checker = new UpdateChecker(http, identity, NullLogger<UpdateChecker>.Instance);
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", null);
    Check((await checker.Check(default)).Status == "disabled" && registry.Requests == 0, "Disabled checks must not contact registry");
    Environment.SetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES", "true");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_USERNAME", "fixture");
    Environment.SetEnvironmentVariable("ROMCHECKER_UPDATE_TOKEN", "fixture-token");
    var available = await checker.Check(default);
    Check(available.Status == "available" && available.Release?.Notes == "Upcoming release notes.",
        "Registry index, platform config and bounded release metadata layer");
    Check(registry.DownloadHadNoCredentials, "Do not forward credentials to signed CDN");
    registry.BadMetadataDigest = true;
    var badNotes = await checker.Check(default);
    Check(badNotes.Status == "available" && badNotes.Release is null && badNotes.NotesError is not null,
        "Invalid notes digest cannot hide a confirmed image update or be accepted");
    registry.BadMetadataDigest = false;
    registry.WrongMetadataIdentity = true;
    Check((await checker.Check(default)).NotesError is not null, "Reject release notes belonging to another image");
    registry.WrongMetadataIdentity = false;

    var builder = Host.CreateApplicationBuilder();
    builder.Services.AddSingleton(checker);
    using var host = builder.Build();
    var clock = new TestClock();
    using var monitor = new UpdateMonitor(host.Services.GetRequiredService<IServiceScopeFactory>(), identity,
        NullLogger<UpdateMonitor>.Instance, clock);
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
    SqliteConnection.ClearAllPools();
    Directory.Delete(directory, true);
}

sealed class RegistryFixture : HttpMessageHandler
{
    public int Requests { get; private set; }
    public bool DownloadHadNoCredentials { get; private set; }
    public bool Fail { get; set; }
    public bool BadMetadataDigest { get; set; }
    public bool WrongMetadataIdentity { get; set; }
    private byte[]? savedMetadata;
    private bool savedWrongIdentity;
    private byte[] Metadata()
    {
        if (savedMetadata is not null && savedWrongIdentity == WrongMetadataIdentity) return savedMetadata;
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionMode.Compress, true))
        using (var tar = new TarWriter(gzip))
        {
            var value = new ReleaseInfo(1, "1.3.0-development.143", "development",
                new string(WrongMetadataIdentity ? 'a' : 'b', 40), null, "Upcoming release notes.", [], []);
            using var json = new MemoryStream(JsonSerializer.SerializeToUtf8Bytes(value, Json.Options));
            tar.WriteEntry(new PaxTarEntry(TarEntryType.RegularFile, "release-info.json") { DataStream = json });
        }
        savedWrongIdentity = WrongMetadataIdentity;
        return savedMetadata = output.ToArray();
    }
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests++;
        if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
        object body;
        if (request.RequestUri!.Host == "pkg-containers.githubusercontent.com")
        {
            DownloadHadNoCredentials = request.Headers.Authorization is null;
            if (request.RequestUri.AbsolutePath == "/release")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Metadata()) });
            body = new { config = new { Labels = new Dictionary<string, string>
            {
                ["org.opencontainers.image.version"] = "1.3.0-development.143",
                ["org.opencontainers.image.revision"] = new string('b', 40),
                ["io.romchecker.channel"] = "development", ["io.romchecker.build-number"] = "143",
                ["io.romchecker.schema-version"] = "1"
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
            var metadata = Metadata();
            var digest = "sha256:" + Convert.ToHexStringLower(SHA256.HashData(metadata));
            if (request.RequestUri.AbsolutePath.EndsWith("-metadata"))
            {
                body = new { layers = new[] { new { digest, size = metadata.Length,
                    mediaType = "application/vnd.oci.image.layer.v1.tar+gzip" } } };
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                    { Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json") });
            }
            if (request.RequestUri.AbsolutePath.Contains("/blobs/"))
            {
                var redirect = new HttpResponseMessage(HttpStatusCode.TemporaryRedirect);
                redirect.Headers.Location = new Uri("https://pkg-containers.githubusercontent.com/"
                    + (request.RequestUri.AbsolutePath.EndsWith(digest) ? "release" : "fixture"));
                if (BadMetadataDigest && request.RequestUri.AbsolutePath.EndsWith(digest))
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(new byte[metadata.Length]) });
                return Task.FromResult(redirect);
            }

            body = request.RequestUri.AbsolutePath.EndsWith("/development")
                ? (object)new { manifests = new[] { new { digest = "sha256:" + new string('c', 64), platform = new { os = "linux", architecture = System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.Arm64 ? "arm64" : "amd64" } } } }
                : new { config = new { digest = "sha256:" + new string('d', 64) } };
        }
        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        });
    }
}

sealed class TestClock : TimeProvider
{
    private DateTimeOffset now = DateTimeOffset.Parse("2026-11-11T12:00:00Z");
    public override DateTimeOffset GetUtcNow() => now;
    public void Advance(TimeSpan interval) => now += interval;
}
