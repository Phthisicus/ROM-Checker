namespace RomChecker.Web.Features.Storage;

public sealed record Batch(string Id, string Name, string Status, DateTimeOffset Created,
    int Files = 0, long Bytes = 0, string? Error = null, string? Lease = null, bool Prepared = false);
public sealed record BatchRequest(string Name);
public sealed record UploadRequest(string Path, long Size, long Modified);
public sealed record UploadState(string Id, string Path, long Size, long Modified, long Offset, bool Complete);
public sealed record StorageEntry(string Name, string Path, bool Directory, long Size);
public sealed record StorageListing(string Path, StorageEntry[] Entries, int Page, bool More);
public sealed record LeaseRequest(string JobId);
public sealed record SmbConnectionRequest(string Server, string Share, string Username, string Password, string Domain = "");
public sealed record SmbImportRequest(string ConnectionId, string[] Paths);

public sealed class StorageOptions
{
    public string Root { get; } = Path.GetFullPath(Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_ROOT") ?? "/storage");
    public string Token { get; } = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_TOKEN") ?? "";
    public long MaxBytes { get; } = long.Parse(Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_MAX_BYTES") ?? "1099511627776");
    public int MaxFiles { get; } = int.Parse(Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_MAX_FILES") ?? "100000");
    public long ReserveBytes { get; } = long.Parse(Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_RESERVE_BYTES") ?? "1073741824");
    public const int ChunkBytes = 8 * 1024 * 1024;
    public string[] SmbHosts { get; } = (Environment.GetEnvironmentVariable("ROMCHECKER_SMB_HOSTS") ?? "")
        .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    public void Validate()
    {
        if (Token.Length < 32) throw new InvalidOperationException("ROMCHECKER_STORAGE_TOKEN must contain at least 32 characters.");
        if (MaxBytes < 1 || MaxFiles < 1 || ReserveBytes < 0) throw new InvalidOperationException("Invalid storage limits.");
    }
}
