using System.Collections.Concurrent;
using System.Text.Json;

namespace RomChecker.Web.Features.Storage;

public sealed class BatchStore(StorageOptions options)
{
    private readonly ConcurrentDictionary<string, SemaphoreSlim> locks = new();
    public string DirectoryFor(string id) => Path.Combine(options.Root, "batches", StoragePaths.Id(id));
    public string Tree(string id, string tree) => tree is "originals" or "processed"
        ? Path.Combine(DirectoryFor(id), tree) : throw new RequestException("Unknown storage tree.");
    public SemaphoreSlim Gate(string id) => locks.GetOrAdd(StoragePaths.Id(id), _ => new(1, 1));
    public Batch Get(string id) => Read<Batch>(Path.Combine(DirectoryFor(id), "batch.json"))
        ?? throw new RequestException("Batch not found.", 404);
    public Batch[] All() => Directory.Exists(Path.Combine(options.Root, "batches"))
        ? Directory.EnumerateDirectories(Path.Combine(options.Root, "batches"))
            .Select(dir => Get(Path.GetFileName(dir))).OrderByDescending(b => b.Created).ToArray() : [];

    public static T? Read<T>(string path)
    {
        if (!File.Exists(path)) return default;
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        return JsonSerializer.Deserialize<T>(stream, Json.Options);
    }
    public static void Write<T>(string path, T value)
    {
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, Json.Serialize(value));
        File.Move(temporary, path, true);
    }
    public void Save(Batch batch) => Write(Path.Combine(DirectoryFor(batch.Id), "batch.json"), batch);
    public void Available(Batch batch, params string[] states)
    {
        if (!states.Contains(batch.Status) || batch.Lease is not null)
            throw new RequestException($"Batch is {batch.Status}; this operation is not allowed.", 409);
    }
    public void Capacity(long bytes)
    {
        if (bytes < 0 || new DriveInfo(options.Root).AvailableFreeSpace - bytes < options.ReserveBytes)
            throw new RequestException("Not enough free storage; reserved free space must remain available.", 507);
    }
    public Batch Create(string name)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Length > 120) throw new RequestException("Choose a batch name (1-120 characters).");
        if (All().Length >= 200) throw new RequestException("Storage is limited to 200 batches. Delete unused batches first.", 409);
        var batch = new Batch(Guid.NewGuid().ToString("N"), name.Trim(), "uploading", DateTimeOffset.UtcNow);
        Directory.CreateDirectory(Tree(batch.Id, "originals"));
        Directory.CreateDirectory(Path.Combine(DirectoryFor(batch.Id), "uploads"));
        Directory.CreateDirectory(Path.Combine(DirectoryFor(batch.Id), "parts"));
        Save(batch);
        return batch;
    }
    public UploadState[] Uploads(string id) => Directory.EnumerateFiles(Path.Combine(DirectoryFor(id), "uploads"), "*.json")
        .Select(file => Read<UploadState>(file)!).ToArray();
    public UploadState Upload(string id, string fileId) => Read<UploadState>(UploadPath(id, fileId))
        ?? throw new RequestException("Upload not found.", 404);
    public string UploadPath(string id, string fileId) => Path.Combine(DirectoryFor(id), "uploads", StoragePaths.Id(fileId) + ".json");
    public string Part(string id, string fileId) => Path.Combine(DirectoryFor(id), "parts", StoragePaths.Id(fileId));
    public void Recover()
    {
        Directory.CreateDirectory(Path.Combine(options.Root, "batches"));
        foreach (var batch in All())
        {
            var uploads = Uploads(batch.Id);
            if (uploads.Length > 0)
                Save(batch with { Files = uploads.Length, Bytes = uploads.Sum(u => u.Size) });
            if (batch.Status == "preparing" && Directory.Exists(Tree(batch.Id, "processed")))
            {
                Save(batch with { Status = "ready", Prepared = true, Error = null });
                continue;
            }
            if (batch.Status is "importing" or "preparing")
            {
                var originals = StoragePaths.Files(Tree(batch.Id, "originals")).Select(file => new FileInfo(file.Full)).ToArray();
                Save(batch with
                {
                    Status = "failed", Files = originals.Length, Bytes = originals.Sum(file => file.Length),
                    Error = "Storage restarted during transfer/preparation. Originals were retained; retry preparation or delete this incomplete batch."
                });
            }
        }
    }
}
