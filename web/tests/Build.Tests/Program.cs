using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Data.Sqlite;
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
    Check((await checker.Check(default)).Status == "available", "Registry index, platform config and signed blob path");
    Check(registry.DownloadHadNoCredentials, "Do not forward credentials to signed CDN");
    registry.Fail = true;
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
            if (request.RequestUri.AbsolutePath.Contains("/blobs/"))
            {
                var redirect = new HttpResponseMessage(HttpStatusCode.TemporaryRedirect);
                redirect.Headers.Location = new Uri("https://pkg-containers.githubusercontent.com/fixture");
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
