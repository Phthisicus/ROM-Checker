using System.Text.Json;
using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Settings;

public sealed record BuildIdentity(string Version, long BuildNumber, int BuildAttempt, string Channel,
    string Commit, DateTimeOffset? BuiltUtc, string? WorkflowUrl, int SchemaVersion)
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
        if (value.Channel is not ("local" or "development" or "beta" or "stable")
            || value.SchemaVersion != DatabaseCompatibility.Current
            || value.Version is null || !Regex.IsMatch(value.Version, @"^\d+\.\d+\.\d+(?:-(?:local|development\.[1-9]\d*|beta\.[1-9]\d*))?$")
            || value.BuildNumber < 0 || value.BuildAttempt < 0
            || (value.Channel != "local" && (value.BuildNumber < 1 || value.BuildAttempt < 1 || value.BuiltUtc is null
                || !Regex.IsMatch(value.Commit ?? "", "^[a-f0-9]{40}$")
                || !Regex.IsMatch(value.WorkflowUrl ?? "", @"^https://github\.com/Phthisicus/ROM-Checker/actions/runs/\d+$")
                || (value.Channel == "development" && !value.Version.EndsWith($"-development.{value.BuildNumber}", StringComparison.Ordinal))
                || (value.Channel == "beta" && !value.Version.Contains("-beta.", StringComparison.Ordinal))
                || (value.Channel == "stable" && value.Version.Contains('-')))))
            throw new InvalidOperationException("The baked build identity is invalid.");
        return value;
    }
}
