using System.Collections.Concurrent;
using SMBLibrary;
using SMBLibrary.Client;
using SmbAttributes = SMBLibrary.FileAttributes;

namespace RomChecker.Web.Features.Storage;

public sealed class SmbSession(SMB2Client client, ISMBFileStore files) : IDisposable
{
    public SemaphoreSlim Gate { get; } = new(1, 1);
    public DateTimeOffset Used { get; set; } = DateTimeOffset.UtcNow;
    public void Dispose() { files.Disconnect(); client.Logoff(); client.Disconnect(); }
    private static void Check(NTStatus status)
    {
        if (status != NTStatus.STATUS_SUCCESS) throw new RequestException($"SMB operation failed ({status}).", 502);
    }
    private object Open(string path, bool directory)
    {
        Check(files.CreateFile(out var handle, out _, path.Replace('/', '\\'),
            AccessMask.GENERIC_READ | AccessMask.SYNCHRONIZE,
            directory ? SmbAttributes.Directory : SmbAttributes.Normal,
            ShareAccess.Read, CreateDisposition.FILE_OPEN,
            (directory ? CreateOptions.FILE_DIRECTORY_FILE : CreateOptions.FILE_NON_DIRECTORY_FILE)
                | CreateOptions.FILE_OPEN_REPARSE_POINT, null));
        try
        {
            Check(files.GetFileInformation(out var information, handle, FileInformationClass.FileBasicInformation));
            if (((FileBasicInformation)information).FileAttributes.HasFlag(SmbAttributes.ReparsePoint))
                throw new RequestException("SMB links and junctions cannot be imported.");
            return handle;
        }
        catch { files.CloseFile(handle); throw; }
    }
    public StorageEntry[] Browse(string path, int maximum = 100000)
    {
        path = StoragePaths.Relative(path, true);
        // Resolve each ancestor without following a remote junction.
        var parts = path.Split('/', StringSplitOptions.RemoveEmptyEntries);
        for (var i = 1; i < parts.Length; i++) { var ancestor = Open(string.Join('/', parts.Take(i)), true); Check(files.CloseFile(ancestor)); }
        var handle = Open(path, true);
        try
        {
            var result = new List<StorageEntry>();
            // SMBLibrary accumulates directory pages and returns NO_MORE_FILES with the final list.
            var status = files.QueryDirectory(out var entries, handle, "*", FileInformationClass.FileDirectoryInformation);
            if (status != NTStatus.STATUS_NO_MORE_FILES) Check(status);
            foreach (var value in entries.Cast<FileDirectoryInformation>())
            {
                if (value.FileName is "." or ".." || value.FileAttributes.HasFlag(SmbAttributes.ReparsePoint)) continue;
                if (result.Count >= maximum) throw new RequestException("SMB directory contains too many entries; select a smaller directory.", 413);
                var relative = path.Length == 0 ? value.FileName : path + "/" + value.FileName;
                StoragePaths.Relative(relative);
                result.Add(new(value.FileName, relative, value.FileAttributes.HasFlag(SmbAttributes.Directory), value.EndOfFile));
            }
            return result.OrderByDescending(e => e.Directory).ThenBy(e => e.Name, StringComparer.Ordinal).ToArray();
        }
        finally { Check(files.CloseFile(handle)); }
    }
    public async Task Copy(StorageEntry entry, string destination, BatchStore store, CancellationToken token)
    {
        var handle = Open(entry.Path, false);
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            await using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true);
            long offset = 0;
            while (offset < entry.Size)
            {
                token.ThrowIfCancellationRequested();
                var length = (int)Math.Min(Math.Min(client.MaxReadSize, 1024 * 1024), entry.Size - offset);
                var status = files.ReadFile(out var buffer, handle, offset, length);
                Check(status);
                if (buffer.Length == 0) throw new RequestException("SMB source changed or ended unexpectedly.", 409);
                store.Capacity(buffer.Length);
                await output.WriteAsync(buffer, token);
                offset += buffer.Length;
            }
            Check(files.GetFileInformation(out var info, handle, FileInformationClass.FileStandardInformation));
            if (((FileStandardInformation)info).EndOfFile != entry.Size || offset != entry.Size)
                throw new RequestException("SMB file changed during import. Retry in a new batch.", 409);
        }
        finally { Check(files.CloseFile(handle)); }
    }
}

public sealed class SmbSessions(StorageOptions options) : IDisposable
{
    private readonly ConcurrentDictionary<string, SmbSession> sessions = new();
    private readonly SemaphoreSlim connections = new(1, 1);
    public SmbSession Get(string id)
    {
        if (!sessions.TryGetValue(StoragePaths.Id(id), out var session)) throw new RequestException("SMB connection expired. Connect again.", 410);
        session.Used = DateTimeOffset.UtcNow;
        return session;
    }
    public async Task<string> Connect(SmbConnectionRequest request)
    {
        if (!options.SmbHosts.Contains(request.Server, StringComparer.OrdinalIgnoreCase))
            throw new RequestException("SMB server is not approved. Add its exact hostname or IP to ROMCHECKER_SMB_HOSTS.", 403);
        if (string.IsNullOrWhiteSpace(request.Share) || request.Share.Length > 80 || request.Share.Any(c => c < 32 || "\\/:\"".Contains(c))
            || string.IsNullOrEmpty(request.Username) || request.Username.Length > 256
            || request.Password is null || request.Domain is null || request.Password.Length > 1024 || request.Domain.Length > 256)
            throw new RequestException("Invalid SMB connection details.");
        await connections.WaitAsync();
        try
        {
            foreach (var item in sessions.Where(s => s.Value.Used < DateTimeOffset.UtcNow.AddMinutes(-30)))
                if (item.Value.Gate.Wait(0))
                    try { if (sessions.TryRemove(item.Key, out var removed)) removed.Dispose(); }
                    finally { item.Value.Gate.Release(); }
            if (sessions.Count >= 8) throw new RequestException("Disconnect unused SMB connections first.", 429);
            var client = new SMB2Client(15000, false, false);
            try
            {
                if (!client.Connect(request.Server, SMBTransportType.DirectTCPTransport)) throw new RequestException("Could not connect to SMB server on port 445.", 502);
                var status = client.Login(request.Domain, request.Username, request.Password);
                if (status != NTStatus.STATUS_SUCCESS) throw new RequestException($"SMB login failed ({status}).", 400);
                var files = client.TreeConnect(request.Share, out status);
                if (status != NTStatus.STATUS_SUCCESS) throw new RequestException($"SMB share is unavailable ({status}).", 502);
                var id = Guid.NewGuid().ToString("N");
                sessions[id] = new(client, files);
                return id;
            }
            catch { client.Disconnect(); throw; }
        }
        finally { connections.Release(); }
    }
    public async Task Disconnect(string id)
    {
        var session = Get(id);
        if (!await session.Gate.WaitAsync(0)) throw new RequestException("SMB connection is importing. Wait for it to finish.", 409);
        try { if (sessions.TryRemove(id, out _)) session.Dispose(); }
        finally { session.Gate.Release(); }
    }
    public void Dispose() { foreach (var session in sessions.Values) session.Dispose(); }
}
