namespace RomChecker.Web.Features.Catalog;

public static class CatalogEndpoints
{
    public static IServiceCollection AddCatalog(this IServiceCollection services)
    {
        services.AddSingleton<CatalogDatabase>();
        services.AddSingleton<CanonicalCatalog>();
        services.AddSingleton<CatalogVerificationService>();
        services.AddHostedService(provider => provider.GetRequiredService<CatalogVerificationService>());
        services.AddHostedService<CatalogReconciler>();
        return services;
    }
    public static void MapCatalog(this RouteGroupBuilder api)
    {
        api.MapGet("/catalog", ([AsParameters] CatalogQuery query, CanonicalCatalog catalog) => catalog.List(query));
        api.MapGet("/catalog/verifications", (CatalogVerificationService service) => service.All());
        api.MapGet("/catalog/verifications/{id}", (string id, CatalogVerificationService service) => service.Get(id));
        api.MapGet("/catalog/{id}", (string id, CanonicalCatalog catalog) => catalog.Get(id));
        api.MapGet("/catalog/{id}/history", (string id, CanonicalCatalog catalog) => catalog.History(id));
        api.MapGet("/catalog/{id}/copies", (string id, CanonicalCatalog catalog) =>
        {
            var file = catalog.Get(id);
            return catalog.Entries().Where(entry => entry.Id == id ||
                file.SHA256.Length == 64 && entry.SHA256.Equals(file.SHA256, StringComparison.OrdinalIgnoreCase)).ToArray();
        });
        api.MapPost("/catalog/refresh", async (CanonicalCatalog catalog, CancellationToken token) =>
        {
            await catalog.Refresh(token, forceHash: true);
            return catalog.List(new());
        });
        api.MapPost("/catalog/approve", async (CatalogApproveRequest request, CanonicalCatalog catalog,
            HttpContext context) => await catalog.Approve(request, context.User.Identity?.Name ?? "Administrator", context.RequestAborted));
        api.MapPost("/catalog/verify", (CatalogVerifyRequest request, CatalogVerificationService service) =>
        {
            var run = service.Enqueue(request);
            return Results.Accepted($"/api/catalog/verifications/{run.Id}", run);
        });
    }
}

public sealed class CatalogReconciler(CanonicalCatalog catalog, JobService jobs, ILogger<CatalogReconciler> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try { if (!jobs.Busy) await catalog.Refresh(stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
            catch (Exception ex) { logger.LogError(ex, "Catalog refresh failed; previous library snapshot retained"); }
            try { await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken); }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { break; }
        }
    }
}
