using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Settings;

public sealed record UpdateResult(string Status, string Message, string? Version = null,
    string? Commit = null, long? BuildNumber = null, bool? SchemaCompatible = null,
    ReleaseInfo? Release = null, string? NotesError = null, string? BuildVersion = null,
    string? ImageDigest = null, string? ReleaseNotesUrl = null, string? ImageTag = null,
    DateTimeOffset? PublishedUtc = null, string? ImageRepository = null);

public sealed class UpdateChecker(HttpClient http, BuildIdentity current, ILogger<UpdateChecker> logger)
{
    private const string Package = "phthisicus/rom-checker";
    private const string Accept = "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json";

    public async Task<UpdateResult> Check(CancellationToken cancellation)
    {
        if (Environment.GetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES") != "true")
            return new("disabled", "Update checks are opt-in. Set ROMCHECKER_CHECK_UPDATES=true on the server. No request was sent.");
        var channel = SelectedChannel;
        if (current.Channel == "local")
            return new("unavailable", "Local builds have no published update channel.");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            using var tokenRequest = new HttpRequestMessage(HttpMethod.Get,
                $"https://ghcr.io/token?service=ghcr.io&scope=repository:{Package}:pull");
            var user = Environment.GetEnvironmentVariable("ROMCHECKER_UPDATE_USERNAME");
            var secret = Environment.GetEnvironmentVariable("ROMCHECKER_UPDATE_TOKEN");
            if (!string.IsNullOrEmpty(user) || !string.IsNullOrEmpty(secret))
            {
                if (string.IsNullOrEmpty(user) || string.IsNullOrEmpty(secret))
                    throw new InvalidOperationException("Private registry checks require both ROMCHECKER_UPDATE_USERNAME and ROMCHECKER_UPDATE_TOKEN.");
                tokenRequest.Headers.Authorization = new AuthenticationHeaderValue("Basic",
                    Convert.ToBase64String(Encoding.UTF8.GetBytes($"{user}:{secret}")));
            }
            using var tokenResponse = await http.SendAsync(tokenRequest, timeout.Token);
            tokenResponse.EnsureSuccessStatusCode();
            using var tokenJson = JsonDocument.Parse(await tokenResponse.Content.ReadAsStringAsync(timeout.Token));
            var token = tokenJson.RootElement.GetProperty("token").GetString()
                ?? throw new InvalidOperationException("Registry did not return an access token.");
            if (channel is not ("stable" or "beta" or "internal"))
                return new("unavailable", $"The {channel} channel does not publish update manifests.");
            using var manifest = await Read($"manifests/{channel}-manifest", token, timeout.Token);
            JsonDocument? platformManifest = null;
            try
            {
                var root = manifest.RootElement;
                if (root.TryGetProperty("manifests", out var platforms))
                {
                    var architecture = RuntimeInformation.ProcessArchitecture switch
                    {
                        Architecture.X64 => "amd64", Architecture.Arm64 => "arm64",
                        _ => throw new InvalidOperationException("Update checks do not support this CPU architecture.")
                    };
                    var candidates = platforms.EnumerateArray().Where(item =>
                        item.TryGetProperty("platform", out var platform)
                        && platform.GetProperty("os").GetString() == "linux"
                        && platform.GetProperty("architecture").GetString() == architecture).ToArray();
                    if (candidates.Length != 1) throw new InvalidOperationException("No unique matching container platform was published.");
                    platformManifest = await Read($"manifests/{Digest(candidates[0].GetProperty("digest").GetString())}", token, timeout.Token);
                    root = platformManifest.RootElement;
                }
                using var config = await Read($"blobs/{Digest(root.GetProperty("config").GetProperty("digest").GetString())}", token, timeout.Token);
                var labels = config.RootElement.GetProperty("config").GetProperty("Labels");
                string Label(string key) => labels.GetProperty(key).GetString() ?? throw new InvalidOperationException($"Missing image label: {key}");
                if (Label("io.romchecker.manifest-format-version") != "1"
                    || Label("io.romchecker.channel") != channel
                    || !Regex.IsMatch(Label("io.romchecker.image-digest"), "^sha256:[a-f0-9]{64}$")
                    || !Regex.IsMatch(Label("io.romchecker.commit"), "^[a-f0-9]{40}$")
                    || !long.TryParse(Label("io.romchecker.build-number"), out var buildNumber) || buildNumber < 1
                    || !int.TryParse(Label("io.romchecker.schema-version"), out var schemaVersion) || schemaVersion < 1
                    || !DateTimeOffset.TryParse(Label("io.romchecker.published-utc"), System.Globalization.CultureInfo.InvariantCulture,
                        System.Globalization.DateTimeStyles.RoundtripKind, out var publishedUtc))
                    throw new InvalidOperationException("The update channel manifest is invalid.");
                var published = EvaluateManifest(current, channel, Label("io.romchecker.version"),
                    Label("io.romchecker.build-version"), Label("io.romchecker.commit"), buildNumber,
                    Label("io.romchecker.image-digest"), Label("io.romchecker.release-notes-url"),
                    Label("io.romchecker.image-tag"), schemaVersion, publishedUtc);
                var imageRepository = Label("io.romchecker.image");
                if (imageRepository != $"ghcr.io/{Package}")
                    throw new InvalidOperationException("The update channel manifest references an unexpected image repository.");
                return published with { ImageRepository = imageRepository };
            }
            finally { platformManifest?.Dispose(); }
        }
        catch (Exception ex) when (IsReadFailure(ex, cancellation))
        {
            logger.LogWarning(ex, "Channel update check failed for {Channel}", current.Channel);
            throw new RequestException("Update check failed. Check registry access, private-package credentials, and server logs. No deployment was changed.", 502);
        }
    }

    private static bool IsReadFailure(Exception ex, CancellationToken cancellation) =>
        ex is HttpRequestException or JsonException or KeyNotFoundException
            or InvalidOperationException or FormatException or OverflowException
            || ex is OperationCanceledException && !cancellation.IsCancellationRequested;

    private async Task<JsonDocument> Read(string path, string token, CancellationToken cancellation) =>
        JsonDocument.Parse(await ReadBytes(path, token, cancellation));

    private async Task<byte[]> ReadBytes(string path, string token, CancellationToken cancellation)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, $"https://ghcr.io/v2/{Package}/{path}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Headers.TryAddWithoutValidation("Accept", Accept);
        using var response = await http.SendAsync(request, cancellation);
        if (path.StartsWith("blobs/", StringComparison.Ordinal) && response.StatusCode == System.Net.HttpStatusCode.TemporaryRedirect)
        {
            var location = response.Headers.Location;
            if (location is null || location.Scheme != "https" || location.Host != "pkg-containers.githubusercontent.com")
                throw new InvalidOperationException("Untrusted registry blob redirect.");
            // Signed blob downloads use their own URL authorization, never the registry credential.
            using var download = await http.GetAsync(location, cancellation);
            download.EnsureSuccessStatusCode();
            return await download.Content.ReadAsByteArrayAsync(cancellation);
        }
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsByteArrayAsync(cancellation);
    }

    private static string Digest(string? value) => value is not null && Regex.IsMatch(value, "^sha256:[a-f0-9]{64}$")
        ? value : throw new InvalidOperationException("Invalid registry content digest.");

    private string SelectedChannel => Environment.GetEnvironmentVariable("ROMCHECKER_UPDATE_CHANNEL")
        ?? (current.Channel == "development" ? "development" : current.Channel);

    public static UpdateResult EvaluateManifest(BuildIdentity current, string channel, string version,
        string buildVersion, string commit, long buildNumber, string imageDigest, string releaseNotesUrl,
        string imageTag, int schema, DateTimeOffset publishedUtc)
    {
        if (channel is not ("stable" or "beta" or "internal")
            || !Regex.IsMatch(commit, "^[a-f0-9]{40}$")
            || buildNumber < 1
            || schema < 1
            || !Regex.IsMatch(imageDigest, "^sha256:[a-f0-9]{64}$")
            || !Regex.IsMatch(imageTag, "^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$")
            || !Uri.TryCreate(releaseNotesUrl, UriKind.Absolute, out var notesUri)
            || notesUri.Scheme != Uri.UriSchemeHttps
            || notesUri.Host != "github.com")
            throw new InvalidOperationException("The update channel manifest is invalid.");
        var releaseVersion = ParseChannelVersion(version, channel);
        var build = ParseBuildVersion(buildVersion);
        if (buildNumber != build.BuildNumber || !commit.StartsWith(build.Commit, StringComparison.Ordinal)
            || releaseVersion.Major != build.Major || releaseVersion.Minor != build.Minor
            || releaseVersion.Patch != build.Patch)
            throw new InvalidOperationException("The promoted release does not match its immutable build identity.");
        var compatible = schema == current.SchemaVersion;
        var installedTargetComparison = CompareCore((releaseVersion.Major, releaseVersion.Minor, releaseVersion.Patch),
            ParseCoreVersion(current.Version));
        if (buildNumber == current.BuildNumber && commit != current.Commit)
            throw new InvalidOperationException("The same build number points to different source commits.");
        var isSameBuild = buildNumber == current.BuildNumber && commit == current.Commit
            && buildVersion == current.Version;
        var available = installedTargetComparison > 0
            || installedTargetComparison == 0 && buildNumber > current.BuildNumber;
        return new(available ? "available" : "current",
            available
                ? compatible
                    ? $"Version {version} is available on the {channel} channel. Back up data before manually deploying; nothing was installed."
                    : $"Version {version} is available, but its schema differs. Review migration and rollback requirements before deploying."
                : isSameBuild
                    ? $"This build is promoted as {version} on the {channel} channel."
                    : $"This build is current or newer than the latest {channel} promotion.",
            version, commit, buildNumber, compatible, null, null, buildVersion, imageDigest, releaseNotesUrl,
            imageTag, publishedUtc);
    }

    private static (long Major, long Minor, long Patch, long BuildNumber, string Commit) ParseBuildVersion(string version)
    {
        var match = Regex.Match(version,
            @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-internal\.([1-9]\d*)\+([a-f0-9]{7})$");
        if (!match.Success) throw new InvalidOperationException("Invalid immutable internal build version.");
        return (long.Parse(match.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[4].Value, System.Globalization.CultureInfo.InvariantCulture), match.Groups[5].Value);
    }

    private static (long Major, long Minor, long Patch) ParseChannelVersion(string version, string channel)
    {
        var pattern = channel switch
        {
            "stable" => @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$",
            "beta" => @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-beta\.[1-9]\d*$",
            "internal" => @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)-internal\.[1-9]\d*\+[a-f0-9]{7}$",
            _ => throw new InvalidOperationException("Unknown update channel.")
        };
        var match = Regex.Match(version, pattern);
        if (!match.Success) throw new InvalidOperationException("Invalid update channel version.");
        return (long.Parse(match.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture));
    }

    private static int CompareCore((long Major, long Minor, long Patch) left,
        (long Major, long Minor, long Patch) right)
    {
        var major = left.Major.CompareTo(right.Major);
        if (major != 0) return major;
        var minor = left.Minor.CompareTo(right.Minor);
        return minor != 0 ? minor : left.Patch.CompareTo(right.Patch);
    }

    private static (long Major, long Minor, long Patch) ParseCoreVersion(string version)
    {
        var match = Regex.Match(version, @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-|$)");
        if (!match.Success) throw new InvalidOperationException("Invalid installed application version.");
        return (long.Parse(match.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[2].Value, System.Globalization.CultureInfo.InvariantCulture),
            long.Parse(match.Groups[3].Value, System.Globalization.CultureInfo.InvariantCulture));
    }

    public static UpdateResult Evaluate(BuildIdentity current, string version, string channel, string commit, long buildNumber, int schema)
    {
        if (channel != current.Channel || !Regex.IsMatch(commit, "^[a-f0-9]{40}$") || buildNumber < 1 || schema < 1
            || (channel == "development" && !version.EndsWith($"-development.{buildNumber}", StringComparison.Ordinal)))
            throw new InvalidOperationException("The update identity does not match the current channel.");
        var comparison = Compare(version, current.Version, channel);
        if (comparison == 0 && commit != current.Commit)
            throw new InvalidOperationException("The same application version points to different source commits.");
        if (comparison == 0 && schema != current.SchemaVersion)
            throw new InvalidOperationException("The same application version declares a different database schema.");
        var compatible = schema == DatabaseCompatibility.Current;
        return comparison > 0
            ? new("available", compatible
                ? "A newer version is available on this channel. Back up data before manually deploying; nothing was installed."
                : "A newer version is available, but its schema differs. Review migration and rollback requirements before deploying.",
                version, commit, buildNumber, compatible)
            : new("current", comparison < 0
                ? "The channel alias is older than this container. No downgrade is recommended."
                : "This container is current on its channel.", version, commit, buildNumber, compatible);
    }

    private static int Compare(string left, string right, string channel)
    {
        long[] Parts(string value)
        {
            var suffix = channel switch { "stable" => "", "beta" => @"-beta\.([1-9]\d*)", "development" => @"-development\.([1-9]\d*)", _ => throw new InvalidOperationException("Unknown update channel.") };
            var match = Regex.Match(value, @"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)" + suffix + "$");
            if (!match.Success) throw new InvalidOperationException("Invalid channel version.");
            return match.Groups.Cast<Group>().Skip(1).Select(group => long.Parse(group.Value, System.Globalization.CultureInfo.InvariantCulture)).ToArray();
        }
        var a = Parts(left);
        var b = Parts(right);
        for (var index = 0; index < a.Length; index++)
        {
            var comparison = a[index].CompareTo(b[index]);
            if (comparison != 0) return comparison;
        }
        return 0;
    }
}
