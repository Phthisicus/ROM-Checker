namespace RomChecker.Web.Features.Catalog;

public sealed class CatalogVerificationService(CanonicalCatalog catalog, CatalogDatabase database,
    JobService jobs, Store store, ILogger<CatalogVerificationService> logger) : BackgroundService
{
    private readonly SemaphoreSlim signal = new(0, 1);
    public CatalogVerification Enqueue(CatalogVerifyRequest request)
    {
        CanonicalCatalog.ValidateSelection(request.Ids, request.MaxSelection);
        if (request.Organize && !request.Confirm) throw new RequestException("Explicit confirmation is required for organization.");
        request = request with { Settings = request.Settings ?? store.Settings() };
        var all = catalog.Entries();
        var allById = all.ToDictionary(entry => entry.Id);
        var chosen = request.Ids.Select(id => allById.TryGetValue(id, out var entry)
            ? entry : throw new RequestException("Catalog file not found.", 404)).ToArray();
        if (chosen.Any(entry => entry.Missing)) throw new RequestException("Selection contains missing files.", 409);
        var units = chosen.Where(entry => entry.GroupId.Length > 0).Select(entry => (entry.BatchId, entry.GroupId)).ToHashSet();
        var selectedIds = request.Ids.ToHashSet();
        var expanded = all.Where(entry => selectedIds.Contains(entry.Id) || units.Contains((entry.BatchId, entry.GroupId))).ToArray();
        if (expanded.Length > request.MaxSelection)
            throw new RequestException("Linked-unit expansion exceeds maxSelection. Increase the explicit limit or select fewer files.");
        var steps = expanded.GroupBy(entry => entry.BatchId)
            .Select(group => new CatalogVerificationStep(group.Key, group.Select(entry => entry.Id).ToArray())).ToArray();
        var run = new CatalogVerification(Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, "queued", request, steps);
        database.SaveVerification(run);
        foreach (var entry in expanded) catalog.Audit(entry.Id, "verification-queued", $"Scope {run.Id}; organize={request.Organize}.");
        if (signal.CurrentCount == 0) signal.Release();
        return run;
    }
    public CatalogVerification[] All() => database.Verifications().Reverse().ToArray();
    public CatalogVerification Get(string id) => All().FirstOrDefault(run => run.Id == id)
        ?? throw new RequestException("Catalog verification not found.", 404);
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var pending = database.Verifications().FirstOrDefault(run => run.Status is "queued" or "running");
                if (pending is null)
                {
                    await signal.WaitAsync(TimeSpan.FromSeconds(5), stoppingToken);
                    continue;
                }
                await Execute(pending, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                logger.LogError(ex, "Catalog verification dispatcher failed");
                await Task.Delay(TimeSpan.FromSeconds(5), stoppingToken);
            }
        }
    }
    private async Task Execute(CatalogVerification run, CancellationToken token)
    {
        run = run with { Status = "running" };
        database.SaveVerification(run);
        try
        {
            for (var index = 0; index < run.Steps.Length; index++)
            {
                var step = run.Steps[index];
                if (step.Status == "completed") continue;
                if (step.Status == "detecting")
                {
                    await EnsureJob(step.JobId!, new("detect", BatchId: step.BatchId, Settings: run.Request.Settings), token);
                    await WaitForJob(step.JobId!, token);
                    await catalog.Refresh(token);
                    step = step with { Status = "queued", JobId = null, Detected = true };
                    run.Steps[index] = step;
                    database.SaveVerification(run);
                }
                if (step.Status == "queued")
                {
                    await catalog.Refresh(token);
                    var entries = step.Ids.Select(catalog.Get).ToArray();
                    if (!step.Detected)
                    {
                        step = step with { Status = "detecting", JobId = Guid.NewGuid().ToString("N") };
                        run.Steps[index] = step;
                        database.SaveVerification(run);
                        await EnsureJob(step.JobId!, new("detect", BatchId: step.BatchId, Settings: run.Request.Settings), token);
                        await WaitForJob(step.JobId!, token);
                        await catalog.Refresh(token);
                        step = step with { Status = "queued", JobId = null, Detected = true };
                        run.Steps[index] = step;
                        database.SaveVerification(run);
                        entries = step.Ids.Select(catalog.Get).ToArray();
                    }
                    if (entries.Any(entry => entry.CollectionId.Length == 0 || entry.Missing))
                        throw new RequestException("Some selected files could not be detected. Refresh the library and review their paths.", 409);
                    var groups = entries.Where(entry => entry.GroupId.Length > 0).Select(entry => entry.GroupId).ToHashSet();
                    var stepIds = step.Ids.ToHashSet();
                    var expanded = catalog.Entries().Where(entry => entry.BatchId == step.BatchId &&
                        (stepIds.Contains(entry.Id) || groups.Contains(entry.GroupId))).ToArray();
                    var expandedIds = expanded.Select(entry => entry.Id).ToArray();
                    var scopeCount = run.Steps.Where((_, otherIndex) => otherIndex != index).SelectMany(other => other.Ids)
                        .Concat(expandedIds).Distinct().Count();
                    if (scopeCount > run.Request.MaxSelection)
                        throw new RequestException("Detection found linked files beyond maxSelection. Increase the explicit scope limit and retry.", 409);
                    if (expanded.Any(entry => entry.Missing || entry.CollectionId.Length == 0))
                        throw new RequestException("A linked file is missing or unresolved. The complete unit was not verified.", 409);
                    entries = expanded;
                    step = step with { Status = "running", JobId = Guid.NewGuid().ToString("N"),
                        Ids = expandedIds, CollectionIds = entries.Select(entry => entry.CollectionId).ToArray() };
                    run.Steps[index] = step;
                    database.SaveVerification(run);
                }
                await EnsureJob(step.JobId!, new("verify", Confirm: run.Request.Confirm, BatchId: step.BatchId,
                    Settings: run.Request.Settings, Selection: step.CollectionIds, Organize: run.Request.Organize), token);
                await WaitForJob(step.JobId!, token);
                await catalog.Refresh(token);
                run.Steps[index] = step with { Status = "completed" };
                database.SaveVerification(run);
                foreach (var id in step.Ids) catalog.Audit(id, "verification-completed", $"Scope {run.Id}; job {step.JobId}.");
            }
            database.SaveVerification(run with { Status = "completed" });
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            // The persisted step/job IDs are intentionally retained for restart reconciliation.
            throw;
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Catalog verification {RunId} failed", run.Id);
            database.SaveVerification(run with { Status = "failed", Error = ex.Message });
            foreach (var id in run.Steps.SelectMany(step => step.Ids))
                catalog.Audit(id, "verification-failed", $"Scope {run.Id}: {ex.Message}");
        }
    }
    private async Task<Job> EnsureJob(string id, JobRequest request, CancellationToken token)
    {
        try { return store.Get(id); }
        catch (RequestException ex) when (ex.Status == 404) { }
        while (true)
        {
            token.ThrowIfCancellationRequested();
            try { return await jobs.Submit(request, id); }
            catch (RequestException ex) when ((ex.Status is 409 or 503) &&
                (ex.Message.StartsWith("Another job is active", StringComparison.Ordinal) ||
                 ex.Message.StartsWith("Job recovery is still", StringComparison.Ordinal)))
            { await Task.Delay(TimeSpan.FromSeconds(1), token); }
        }
    }
    private async Task WaitForJob(string id, CancellationToken token)
    {
        while (true)
        {
            var job = store.Get(id);
            if ((job.Status is "completed" or "completed-with-warnings") && !jobs.IsActive(id))
            {
                // JobService clears its active slot after finalizing the stored job.
                return;
            }
            if (job.Status is "failed" or "interrupted" or "cancelled")
                throw new RequestException($"Verification job {id} {job.Status}: {job.Error}", 409);
            await Task.Delay(TimeSpan.FromSeconds(1), token);
        }
    }
}
