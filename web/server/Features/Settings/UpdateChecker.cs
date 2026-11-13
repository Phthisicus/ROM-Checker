using System.Net.Http.Headers;
using System.Formats.Tar;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace RomChecker.Web.Features.Settings;

public sealed record UpdateResult(string Status, string Message, string? Version = null,
    string? Commit = null, long? BuildNumber = null, bool? SchemaCompatible = null,
    ReleaseInfo? Release = null, string? NotesError = null);

public sealed class UpdateChecker(HttpClient http, BuildIdentity current, ILogger<UpdateChecker> logger)
{
    private const string Package = "phthisicus/rom-checker";
    private const string Accept = "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json";

    public async Task<UpdateResult> Check(CancellationToken cancellation)
    {
        if (Environment.GetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES") != "true")
            return new("disabled", "Update checks are opt-in. Set ROMCHECKER_CHECK_UPDATES=true on the server. No request was sent.");
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
            var tag = current.Channel switch { "stable" => "latest", "beta" => "beta", _ => "development" };
            using var manifest = await Read($"manifests/{tag}", token, timeout.Token);
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
                var result = Evaluate(current, Label("org.opencontainers.image.version"), Label("io.romchecker.channel"),
                    Label("org.opencontainers.image.revision"), long.Parse(Label("io.romchecker.build-number"), System.Globalization.CultureInfo.InvariantCulture),
                    int.Parse(Label("io.romchecker.schema-version"), System.Globalization.CultureInfo.InvariantCulture));
                if (result.Status != "available") return result;
                try
                {
                    var release = await ReadRelease(result.Version!, result.Commit!, token, timeout.Token);
                    return result with { Release = release };
                }
                catch (Exception ex) when (IsReadFailure(ex, cancellation) || ex is InvalidDataException or IOException)
                {
                    logger.LogWarning(ex, "Release notes unavailable for {Version}", result.Version);
                    return result with { NotesError = "An image update was confirmed, but its release notes could not be retrieved. Retry later or review the source release before deploying." };
                }
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

    private async Task<ReleaseInfo> ReadRelease(string version, string commit, string token, CancellationToken cancellation)
    {
        using var manifest = await Read($"manifests/{version}-metadata", token, cancellation);
        var layers = manifest.RootElement.GetProperty("layers");
        if (layers.GetArrayLength() != 1) throw new InvalidOperationException("Release metadata must have one bounded layer.");
        var layer = layers[0];
        var size = layer.GetProperty("size").GetInt64();
        if (size is < 1 or > 2 * 1024 * 1024) throw new InvalidOperationException("Release metadata layer is too large.");
        var digest = Digest(layer.GetProperty("digest").GetString());
        var bytes = await ReadBytes($"blobs/{digest}", token, cancellation);
        if (bytes.LongLength != size || "sha256:" + Convert.ToHexStringLower(SHA256.HashData(bytes)) != digest)
            throw new InvalidOperationException("Release metadata layer digest does not match.");
        using var compressed = new MemoryStream(bytes);
        var mediaType = layer.GetProperty("mediaType").GetString();
        using Stream content = mediaType switch
        {
            "application/vnd.oci.image.layer.v1.tar+gzip" or "application/vnd.docker.image.rootfs.diff.tar.gzip"
                => new GZipStream(compressed, CompressionMode.Decompress),
            "application/vnd.oci.image.layer.v1.tar" => new MemoryStream(bytes),
            _ => throw new InvalidOperationException("Unsupported release metadata layer format.")
        };
        using var expanded = new MemoryStream();
        var buffer = new byte[8192];
        int count;
        while ((count = await content.ReadAsync(buffer, cancellation)) > 0)
        {
            if (expanded.Length + count > 2 * 1024 * 1024)
                throw new InvalidOperationException("Expanded release metadata is too large.");
            expanded.Write(buffer, 0, count);
        }
        expanded.Position = 0;
        using var tar = new TarReader(expanded);
        ReleaseInfo? release = null;
        while (tar.GetNextEntry() is { } entry)
        {
            if (entry.Name.TrimStart('.', '/') != "release-info.json") continue;
            if (release is not null || entry.EntryType is not (TarEntryType.RegularFile or TarEntryType.V7RegularFile)
                || entry.DataStream is null)
                throw new InvalidOperationException("Invalid release metadata entry.");
            release = await JsonSerializer.DeserializeAsync<ReleaseInfo>(entry.DataStream, Json.Options, cancellation);
        }
        return (release ?? throw new InvalidOperationException("Release information is missing."))
            .Validate(version, current.Channel, commit);
    }

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
