namespace RomChecker.Web.Features.Settings;

public static class SettingsEndpoints
{
    public static void MapSettings(this RouteGroupBuilder api, WebOptions options)
    {
        var root = options.Root;
        var pathBase = options.PathBase;
        var engine = options.EngineDirectory;
        api.MapGet("/info", (BuildIdentity build, DatabaseCompatibility schema) => new
        {
            name = "ROM Checker", version = build.Version, commit = build.Commit,
            buildNumber = build.BuildNumber, buildAttempt = build.BuildAttempt, channel = build.Channel,
            builtUtc = build.BuiltUtc, workflowUrl = build.WorkflowUrl, schema,
            library = root, pathBase, platform = OperatingSystem.IsWindows() ? "Windows" : "Linux",
            antivirus = OperatingSystem.IsWindows() ? "Windows Defender" : "ClamAV"
        });
        api.MapGet("/diagnostics/build", (BuildIdentity build, DatabaseCompatibility schema) =>
            Results.File(System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(new { build, schema }, Json.Options),
                "application/json", "romchecker-build-diagnostics.json"));
        api.MapPost("/updates/check", async (UpdateChecker updates, CancellationToken cancellation) =>
            Results.Ok(await updates.Check(cancellation)));
        api.MapGet("/consoles", () => Results.File(Path.Combine(engine, "web", "engine", "consoles.json"), "application/json; charset=utf-8"));
        api.MapGet("/settings", (Store store) => store.Settings());
        api.MapGet("/settings/integrations", () => new
        {
            virusTotal = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ROMSORTER_VIRUSTOTAL_KEY")),
            malwareBazaar = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("ROMSORTER_MALWAREBAZAAR_KEY")),
            approvedSmbHosts = (Environment.GetEnvironmentVariable("ROMCHECKER_SMB_HOSTS") ?? "")
                .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
        });
        api.MapPut("/settings", (EngineSettings settings, Store store, SettingsValidator validator) =>
        {
            validator.Validate(settings);
            store.SaveSettings(settings);
            return Results.Ok(settings);
        });
    }
}
