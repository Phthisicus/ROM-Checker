using System.Security.Cryptography;
using System.Text;

namespace RomChecker.Web.Features.Storage;

public static class StorageHost
{
    public static async Task Run(string[] args)
    {
        var builder = WebApplication.CreateBuilder(args);
        var options = new StorageOptions();
        options.Validate();
        builder.Services.AddSingleton(options);
        builder.Services.AddSingleton<BatchStore>();
        builder.Services.AddSingleton<SmbSessions>();
        builder.Services.AddSingleton<BatchTransfers>();
        builder.Services.AddHostedService(p => p.GetRequiredService<BatchTransfers>());
        builder.WebHost.ConfigureKestrel(k =>
        {
            k.Limits.MaxRequestBodySize = StorageOptions.ChunkBytes;
            k.AllowSynchronousIO = true; // ZipArchive writes its central directory synchronously.
        });
        builder.Services.Configure<Microsoft.AspNetCore.Http.Json.JsonOptions>(o =>
            o.SerializerOptions.UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow);
        var app = builder.Build();
        using var transferSlots = new SemaphoreSlim(2, 2);
        app.Services.GetRequiredService<BatchStore>().Recover();
        app.Use(async (context, next) =>
        {
            var transfer = context.Request.Method == "PUT" || context.Request.Path.Value!.EndsWith("/download", StringComparison.Ordinal);
            var admitted = false;
            try
            {
                if (context.Request.Path != "/healthz")
                {
                    var supplied = context.Request.Headers.Authorization.ToString();
                    if (!CryptographicOperations.FixedTimeEquals(SHA256.HashData(Encoding.UTF8.GetBytes(supplied)),
                        SHA256.HashData(Encoding.UTF8.GetBytes("Bearer " + options.Token))))
                    { context.Response.StatusCode = 401; return; }
                }
                if (transfer)
                {
                    admitted = await transferSlots.WaitAsync(0, context.RequestAborted);
                    if (!admitted) throw new RequestException("Storage transfer capacity is busy. Retry shortly.", 429);
                }
                context.Response.Headers.CacheControl = "no-store";
                context.Response.Headers["X-Content-Type-Options"] = "nosniff";
                await next(context);
            }
            catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { context.Abort(); }
            catch (Exception ex)
            {
                app.Logger.LogError(ex, "Storage request failed");
                if (context.Response.HasStarted) { context.Abort(); return; }
                context.Response.StatusCode = ex is RequestException request ? request.Status : ex is BadHttpRequestException ? 400 : 500;
                await context.Response.WriteAsJsonAsync(new { error = ex is RequestException ? ex.Message : "Storage request failed. Check storage service logs." });
            }
            finally { if (admitted) transferSlots.Release(); }
        });
        app.MapGet("/healthz", () => new { status = "ok", role = "storage" });
        app.MapBatches();
        app.MapSmb();
        await app.RunAsync();
    }
}
