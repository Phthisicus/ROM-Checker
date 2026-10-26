using System.Threading.Channels;

namespace RomChecker.Web.Features.Storage;

public sealed class BatchTransfers(BatchStore store, ILogger<BatchTransfers> logger) : BackgroundService
{
    private readonly Channel<(string Id, Func<CancellationToken, Task> Run)> queue =
        Channel.CreateBounded<(string, Func<CancellationToken, Task>)>(4);

    public void Enqueue(string id, Func<CancellationToken, Task> run)
    {
        if (!queue.Writer.TryWrite((id, run))) throw new RequestException("Transfer queue is full. Try again later.", 429);
    }

    public void Prepare(string id)
    {
        var batch = store.Get(id);
        store.Available(batch, "uploading", "ready", "failed");
        if (batch.Prepared) throw new RequestException("This batch already has a processing workspace.", 409);
        var uploads = store.Uploads(id);
        if (uploads.Any(u => !u.Complete)) throw new RequestException("Finish or retry incomplete uploads before preparing.", 409);
        if (!StoragePaths.Files(store.Tree(id, "originals")).Any()) throw new RequestException("Batch has no files.");
        store.Capacity(batch.Bytes);
        store.Save(batch with { Status = "preparing", Error = null });
        try { Enqueue(id, token => CopyOriginals(id, token)); }
        catch { store.Save(batch); throw; }
    }

    public async Task CopyOriginals(string id, CancellationToken token)
    {
        var root = store.Tree(id, "originals");
        var destination = store.Tree(id, "processed");
        // Only an unfinished preparation can leave this private staging tree.
        var staging = Path.Combine(store.DirectoryFor(id), "preparing");
        if (Directory.Exists(staging))
        {
            foreach (var _ in StoragePaths.Files(staging)) { }
            Directory.Delete(staging, true);
        }
        Directory.CreateDirectory(staging);
        foreach (var file in StoragePaths.Files(root))
        {
            token.ThrowIfCancellationRequested();
            store.Capacity(new FileInfo(file.Full).Length);
            var target = StoragePaths.Resolve(staging, file.Relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var source = File.OpenRead(file.Full);
            await using var output = new FileStream(target, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true);
            await source.CopyToAsync(output, token);
        }
        Directory.Move(staging, destination);
        store.Save(store.Get(id) with { Status = "ready", Prepared = true, Error = null });
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var item in queue.Reader.ReadAllAsync(stoppingToken))
            try { await item.Run(stoppingToken); }
            catch (Exception ex)
            {
                logger.LogError(ex, "Batch transfer {BatchId} failed", item.Id);
                store.Save(store.Get(item.Id) with { Status = "failed", Error = ex is OperationCanceledException
                    ? "Transfer interrupted. Completed originals are retained." : ex.Message });
            }
    }
}
