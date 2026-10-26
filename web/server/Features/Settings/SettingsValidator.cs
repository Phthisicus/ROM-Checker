using System.Text.Json;
using RomChecker.Web.Features.Library;

namespace RomChecker.Web.Features.Settings;

public sealed class SettingsValidator(WebOptions options, LibraryPaths paths)
{
    public void Validate(EngineSettings settings)
    {
        if (settings.Layout is not ("ByConsole" or "Validity" or "Emulator" or "Frontend" or "RetroArch" or "Classic")
            || settings.Hasheous is not ("Off" or "Unverified" or "All")
            || settings.OnlineCheck is not ("Off" or "Risky" or "Unverified" or "All")
            || settings.DuplicateMode is not ("Move" or "Report" or "Off")
            || string.IsNullOrWhiteSpace(settings.Console) || settings.Console.Length > 40)
            throw new RequestException("Invalid engine settings.");
        var catalog = JsonDocument.Parse(File.ReadAllText(Path.Combine(options.EngineDirectory, "web", "engine", "consoles.json")));
        using (catalog)
            if (settings.Console != "All" && !catalog.RootElement.EnumerateArray().Any(c => c.GetProperty("Key").GetString() == settings.Console))
                throw new RequestException("Unknown console filter.");
        if (settings.HashLimitMB is < 1 or > 1048576
            || settings.ArchiveMaxMB is < 1 or > 1048576
            || settings.ArchiveMaxEntries is < 1 or > 100000
            || settings.ArchiveMaxDepth is < 0 or > 10
            || settings.ArchiveTimeoutSeconds is < 10 or > 3600)
            throw new RequestException("Engine limits are out of range.");
        if (!string.IsNullOrEmpty(settings.DatFolder)) paths.AssertPath(settings.DatFolder, true);
    }
}
