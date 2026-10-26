namespace RomChecker.Web.Features.Reports;

public static class ReportsEndpoints
{
    public static void MapReports(this RouteGroupBuilder api)
    {
        api.MapGet("/jobs/{id}/artifacts/{name}", (string id, string name, JobService jobs) =>
        {
            if (name is not ("results.json" or "cleanup.json" or "history.json" or "output.log" or "summary.json" or "report.html" or "report.csv"))
                throw new RequestException("Artifact not found.", 404);
            var path = Path.Combine(jobs.DirectoryFor(id), name);
            return File.Exists(path) ? Results.File(path, name.EndsWith(".json") ? "application/json; charset=utf-8" : "text/plain; charset=utf-8",
                $"{id}-{name}") : Results.NotFound();
        });
    }
}
