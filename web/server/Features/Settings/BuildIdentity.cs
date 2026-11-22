using System.Text.Json;
using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Settings;

public sealed record BuildIdentity(string Version, long BuildNumber, int BuildAttempt, string Channel,
    string Commit, DateTimeOffset? BuiltUtc, string? WorkflowUrl, int SchemaVersion, int MetadataFormatVersion = 1)
{
    public static BuildIdentity Load(string path)
    {
        if (!File.Exists(path))
        {
            if (Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true")
                throw new InvalidOperationException("The container is missing its baked build-info.json.");
            return new("0.0.0-local", 0, 0, "local", "development", null, null, DatabaseCompatibility.Current);
        }
        var value = JsonSerializer.Deserialize<BuildIdentity>(File.ReadAllText(path), Json.Options)
            ?? throw new InvalidOperationException("The baked build identity is empty.");
        var version = value.Version ?? "";
        var prerelease = Regex.Match(version,
            @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-(?<channel>local|development|internal|beta|rc)\.(?<number>[1-9]\d*)(?:\+(?<build>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$");
        var isLocal = value.Channel == "local" && version == "0.0.0-local";
        var isStable = value.Channel == "stable" && Regex.IsMatch(version, @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$");
        var isInternal = value.Channel == "internal" && prerelease.Success
            && prerelease.Groups["channel"].Value == "internal"
            && prerelease.Groups["number"].Value == value.BuildNumber.ToString(System.Globalization.CultureInfo.InvariantCulture)
            && prerelease.Groups["build"].Value == (value.Commit ?? "").AsSpan(0, Math.Min(7, (value.Commit ?? "").Length)).ToString();
        var isBetaOrRc = (value.Channel is "beta" or "rc") && prerelease.Success
            && prerelease.Groups["channel"].Value == value.Channel
            && !prerelease.Groups["build"].Success;
        var isLegacyDevelopment = value.Channel == "development"
            && Regex.IsMatch(version, @"^\d+\.\d+\.\d+-development\.[1-9]\d*$");
        if (value.Channel is not ("local" or "development" or "internal" or "beta" or "rc" or "stable")
            || value.MetadataFormatVersion != 1
            || value.SchemaVersion != DatabaseCompatibility.Current
            || !(isLocal || isStable || isInternal || isBetaOrRc || isLegacyDevelopment)
            || value.BuildNumber < 0 || value.BuildAttempt < 0
            || (value.Channel != "local" && (value.BuildNumber < 1 || value.BuildAttempt < 1 || value.BuiltUtc is null
                || !Regex.IsMatch(value.Commit ?? "", "^[a-f0-9]{40}$")
                || !Regex.IsMatch(value.WorkflowUrl ?? "", @"^https://github\.com/Phthisicus/ROM-Checker/actions/runs/\d+$")
                || (value.Channel == "development" && !version.EndsWith($"-development.{value.BuildNumber}", StringComparison.Ordinal)))))
            throw new InvalidOperationException("The baked build identity is invalid.");
        return value;
    }
}
