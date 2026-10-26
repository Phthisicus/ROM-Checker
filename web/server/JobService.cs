using System.Text.Json;
using System.Threading.Channels;
using RomChecker.Web.Infrastructure;
using RomChecker.Web.Features.Jobs;
using RomChecker.Web.Features.Library;
using RomChecker.Web.Features.Settings;

namespace RomChecker.Web;

public sealed class JobService(Store store, WebOptions options, SettingsValidator validator,
    LibraryPaths paths, EngineRunner runner, ILogger<JobService> logger) : BackgroundService
{
    private readonly Channel<string> queue = Channel.CreateUnbounded<string>(
        new UnboundedChannelOptions { SingleReader = true });
    private readonly object gate = new();
    private string? activeId;
    private CancellationTokenSource? activeCancellation;
    public string DirectoryFor(string id)
    {
        _ = store.Get(id);
        return Path.Combine(options.Data, "jobs", id);
    }
    public Job Submit(JobRequest request)
    {
        var action = JobActions.Get(request.Action);
        if (action.ChangesFiles && !request.Confirm)
            throw new RequestException("Explicit confirmation is required for file changes.");
        var settings = store.Settings();
        validator.Validate(settings);
        if (action.SourceActions is { } allowedSources)
        {
            var source = store.Get(request.SourceId ?? "");
            if (source.Status is not ("completed" or "completed-with-warnings"))
                throw new RequestException("Source job did not complete successfully.");
            if (!allowedSources.Contains(source.Action))
                throw new RequestException("Source job is not a suitable preview.");
            if (action.PreserveSourceSettings) settings = source.Settings;
        }
        if (action.RequiresJournal
            && (string.IsNullOrWhiteSpace(request.Journal) || Path.GetFileName(request.Journal) != request.Journal))
            throw new RequestException("Choose a recovery journal.");
        if ((request.Reviews?.Length ?? 0) > 10000) throw new RequestException("Too many review decisions.");
        foreach (var review in request.Reviews ?? [])
        {
            paths.AssertPath(review.Path);
            if (review.Decision is not ("keep" or "original" or "quarantine"))
                throw new RequestException("Invalid review decision.");
        }
        lock (gate)
        {
            if (activeId is not null) throw new RequestException("Another job is active. Wait for it to finish.", 409);
            if (request.Action == "apply" && store.HasApplyAttempt(request.SourceId!))
                throw new RequestException("This preview has already been applied or attempted. Build a new preview.", 409);
            var job = new Job(Guid.NewGuid().ToString("N"), request.Action, "queued",
                DateTimeOffset.UtcNow, null, null, request, settings);
            store.Save(job);
            activeId = job.Id;
            if (!queue.Writer.TryWrite(job.Id)) throw new InvalidOperationException("Job queue is closed.");
            return job;
        }
    }
    public void Cancel(string id)
    {
        lock (gate)
        {
            var job = store.Get(id);
            if (activeId != id) throw new RequestException("Job is not active.", 409);
            // Do not terminate a process halfway through a journaled filesystem operation.
            if (JobActions.Get(job.Action).ChangesFiles)
                throw new RequestException("File-changing jobs cannot be cancelled safely. Allow them to finish.", 409);
            store.Save(job with { Status = "cancelling" });
            activeCancellation?.Cancel();
        }
    }
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var id in queue.Reader.ReadAllAsync(stoppingToken))
        {
            using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
            lock (gate) activeCancellation = cancellation;
            var job = store.Get(id);
            if (job.Status == "cancelling") cancellation.Cancel();
            store.Save(job with { Status = "running" });
            try
            {
                cancellation.CancelAfter(options.JobTimeout);
                await runner.Run(job, DirectoryFor(job.Id),
                    job.Request.SourceId is null ? null : DirectoryFor(job.Request.SourceId), cancellation.Token);
                var summary = await ReadJson(id, "summary.json");
                var warnings = summary.TryGetProperty("Warnings", out var count) && count.GetInt32() > 0;
                store.Save(job with { Status = warnings ? "completed-with-warnings" : "completed", Finished = DateTimeOffset.UtcNow });
            }
            catch (OperationCanceledException)
            {
                var userCancelled = store.Get(id).Status == "cancelling";
                store.Save(job with { Status = userCancelled ? "cancelled" : "interrupted", Finished = DateTimeOffset.UtcNow,
                    Error = userCancelled ? "Cancelled by user." : "Server shutdown or job time limit reached. Review recovery journals before retrying." });
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Job {JobId} failed", id);
                store.Save(job with { Status = "failed", Finished = DateTimeOffset.UtcNow, Error = ex.Message });
            }
            finally { lock (gate) { activeId = null; activeCancellation = null; } }
        }
    }
    public async Task<JsonElement> ReadJson(string id, string name)
    {
        var path = Path.Combine(DirectoryFor(id), name);
        if (!File.Exists(path)) return JsonSerializer.SerializeToElement<object?>(null);
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var document = await JsonDocument.ParseAsync(stream);
        return document.RootElement.Clone();
    }
    public async Task<string> Log(string id)
    {
        var path = Path.Combine(DirectoryFor(id), "output.log");
        if (!File.Exists(path)) return "";
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        if (stream.Length > 64000) stream.Seek(-64000, SeekOrigin.End);
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync();
    }
}
