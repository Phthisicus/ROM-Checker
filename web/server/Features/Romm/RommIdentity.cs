using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using RomChecker.Web.Features.Storage;

namespace RomChecker.Web.Features.Romm;

public static class RommIdentity
{
    public static string FilePath(JsonElement remote, JsonElement file, bool multiple)
    {
        var name = StoragePaths.Relative(RommClient.Text(file, "file_name"));
        if (name.Contains('/')) throw new RequestException("RomM file_name must be a basename.");
        if (!multiple) return name;
        var root = RommClient.Text(remote, "full_path").TrimEnd('/');
        if (root.Length == 0) root = RommClient.Text(remote, "fs_path").TrimEnd('/') + "/" + RommClient.Text(remote, "fs_name");
        var full = RommClient.Text(file, "file_path").TrimEnd('/') + "/" + name;
        if (!full.StartsWith(root + "/", StringComparison.Ordinal))
            throw new RequestException("RomM supplied a file outside its game's folder.");
        return StoragePaths.Relative(full[(root.Length + 1)..]);
    }

    public static RommRemoteSnapshot Snapshot(JsonElement remote)
    {
        var platform = RommClient.Number(remote, "platform_id");
        if (platform < 1 || !remote.TryGetProperty("files", out var files) || files.ValueKind != JsonValueKind.Array
            || files.GetArrayLength() is 0 or > 100000)
            throw new RequestException("RomM must provide a platform and individual file metadata for safe synchronization.", 409);
        var identities = files.EnumerateArray().Select(file =>
        {
            var sha1 = RommClient.Text(file, "sha1_hash").ToUpperInvariant();
            if (sha1.Length != 40 || !sha1.All(Uri.IsHexDigit)
                || !long.TryParse(RommClient.Text(file, "file_size_bytes"), out var size) || size < 0
                || RommClient.Number(file, "id") < 1)
                throw new RequestException("RomM file hashes, sizes or IDs are incomplete. Scan RomM before synchronizing.", 409);
            return new RommFileIdentity(FilePath(remote, file, files.GetArrayLength() > 1), size, sha1);
        }).OrderBy(file => file.Path, StringComparer.Ordinal).ToArray();
        if (identities.Select(file => file.Path).Distinct(StringComparer.OrdinalIgnoreCase).Count() != identities.Length)
            throw new RequestException("RomM supplied colliding file paths.", 409);
        return new(platform, identities, Digest(new { platform, files = identities }),
            ContentKey(platform, identities));
    }
    public static string ContentKey(int platform, IEnumerable<RommFileIdentity> files) =>
        Digest(new { platform, files = files.Select(file => new { file.Size, file.SHA1 })
            .OrderBy(file => file.SHA1, StringComparer.Ordinal).ThenBy(file => file.Size).ToArray() });
    public static string ObservedVersion(JsonElement remote)
    {
        try { return Snapshot(remote).Fingerprint; }
        catch (RequestException ex) when (ex.Status == 409)
        {
            // An unindexed version may be explicitly ignored, but never trusted or imported.
            return "unindexed:" + Digest(new { platform = RommClient.Text(remote, "platform_id"),
                files = remote.TryGetProperty("files", out var files) ? files.GetRawText() : "" });
        }
    }
    private static string Digest(object value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Json.Serialize(value))));
}
