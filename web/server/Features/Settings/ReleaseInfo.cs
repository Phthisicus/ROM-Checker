using System.Text.Json;
using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Settings;

public sealed record ReleaseInfo(int MetadataFormatVersion, string Version, string Channel, string Commit,
    string? ReleaseUrl, string Notes, string[] UpgradeNotes, string[] Limitations)
{
    public static ReleaseInfo Load(string path, BuildIdentity build)
    {
        if (!File.Exists(path) && build.Channel == "local")
            return new(1, build.Version, build.Channel, build.Commit, null,
                "Local source build. Published release notes are not available.", [], []);
        var value = JsonSerializer.Deserialize<ReleaseInfo>(File.ReadAllText(path), Json.Options)
            ?? throw new InvalidOperationException("Release information is empty.");
        return value.Validate(build.Version, build.Channel, build.Commit);
    }

    public ReleaseInfo Validate(string version, string channel, string commit)
    {
        if (MetadataFormatVersion != 1 || Version != version || Channel != channel || Commit != commit
            || string.IsNullOrWhiteSpace(Notes) || Notes.Length > 512_000
            || UpgradeNotes is null || Limitations is null
            || UpgradeNotes.Concat(Limitations).Any(text => text is null || text.Length > 4000)
            || (ReleaseUrl is not null && !Regex.IsMatch(ReleaseUrl,
                @"^https://github\.com/Phthisicus/ROM-Checker/(releases/tag/v\d+\.\d+\.\d+(?:-beta\.\d+)?|commit/[a-f0-9]{40})$")))
            throw new InvalidOperationException("Release information does not match the image identity or supported format.");
        return this;
    }
}
