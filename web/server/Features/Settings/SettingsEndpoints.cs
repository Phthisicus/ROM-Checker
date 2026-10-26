namespace RomChecker.Web.Features.Settings;

public static class SettingsEndpoints
{
    public static void MapSettings(this RouteGroupBuilder api, WebOptions options)
    {
        var root = options.Root;
        var pathBase = options.PathBase;
        var engine = options.EngineDirectory;
        api.MapGet("/info", () => new
        {
            name = "ROM Checker", version = (Environment.GetEnvironmentVariable("ROMCHECKER_VERSION") ?? "0.2.0-dev"), commit = (Environment.GetEnvironmentVariable("ROMCHECKER_COMMIT") ?? "development"),
            library = root, pathBase, platform = OperatingSystem.IsWindows() ? "Windows" : "Linux",
            antivirus = OperatingSystem.IsWindows() ? "Windows Defender" : "ClamAV"
        });
        api.MapGet("/catalog", () => Results.File(Path.Combine(engine, "web", "engine", "consoles.json"), "application/json; charset=utf-8"));
        api.MapGet("/settings", (Store store) => store.Settings());
        api.MapPut("/settings", (EngineSettings settings, Store store, SettingsValidator validator) =>
        {
            validator.Validate(settings);
            store.SaveSettings(settings);
            return Results.Ok(settings);
        });
    }
}
