namespace RomChecker.Web.Features.Jobs;

public static class JobsEndpoints
{
    public static void MapJobs(this RouteGroupBuilder api)
    {
        api.MapGet("/jobs", (Store store) => store.All());
        api.MapPost("/jobs", async (JobRequest request, JobService jobs) => Results.Accepted(value: await jobs.Submit(request)));
        api.MapGet("/jobs/{id}", async (string id, Store store, JobService jobs) =>
            new { job = store.Get(id), progress = await jobs.ReadJson(id, "progress.json"), summary = await jobs.ReadJson(id, "summary.json") });
        api.MapPost("/jobs/{id}/cancel", (string id, JobService jobs) => { jobs.Cancel(id); return Results.Accepted(); });
        api.MapGet("/jobs/{id}/log", async (string id, JobService jobs) => Results.Text(await jobs.Log(id)));
        api.MapGet("/jobs/{id}/events", async (string id, HttpContext context, Store store, JobService jobs) =>
        {
            _ = store.Get(id);
            context.Response.ContentType = "text/event-stream";
            context.Response.Headers["X-Accel-Buffering"] = "no";
            while (!context.RequestAborted.IsCancellationRequested)
            {
                var job = store.Get(id);
                var progress = await jobs.ReadJson(id, "progress.json");
                await context.Response.WriteAsync($"data: {Json.Serialize(new { job, progress })}\n\n", context.RequestAborted);
                await context.Response.Body.FlushAsync(context.RequestAborted);
                if (job.Status is not ("running" or "queued" or "cancelling")) break;
                await Task.Delay(1000, context.RequestAborted);
            }
        });
    }
}
