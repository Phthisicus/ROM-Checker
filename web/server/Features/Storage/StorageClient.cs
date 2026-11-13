using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace RomChecker.Web.Features.Storage;

public sealed class StorageClient
{
    private readonly HttpClient client;
    public bool Enabled { get; }
    public string Root { get; }
    public StorageClient(IHttpClientFactory factory, WebOptions options)
    {
        var address = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_URL");
        Enabled = !string.IsNullOrEmpty(address);
        Root = Path.GetFullPath(Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_ROOT") ?? "/storage");
        client = factory.CreateClient("storage");
        if (Enabled)
        {
            var relative = Path.GetRelativePath(options.Root, Root);
            var reverse = Path.GetRelativePath(Root, options.Root);
            bool Inside(string value) => !Path.IsPathRooted(value) && value != ".." && !value.StartsWith(".." + Path.DirectorySeparatorChar);
            if (Inside(relative) || Inside(reverse)) throw new InvalidOperationException("Storage and the mounted legacy library must not overlap.");
            var token = Environment.GetEnvironmentVariable("ROMCHECKER_STORAGE_TOKEN") ?? "";
            if (token.Length < 32) throw new InvalidOperationException("Set ROMCHECKER_STORAGE_TOKEN to at least 32 characters.");
            client.BaseAddress = new Uri(address!.TrimEnd('/') + "/internal/");
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }
    public string BatchRoot(string id) => Path.Combine(Root, "batches", StoragePaths.Id(id), "processed");
    public async Task<HttpResponseMessage> Send(HttpRequestMessage request, CancellationToken token)
    {
        if (!Enabled) throw new RequestException("Batch storage is not configured. Set ROMCHECKER_STORAGE_URL and deploy the storage service.", 503);
        try { return await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token); }
        catch (HttpRequestException) { throw new RequestException("Storage service is unreachable.", 503); }
    }
    public async Task<T> Get<T>(string path, CancellationToken token = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, path);
        using var response = await Send(request, token);
        await Check(response, token);
        return (await response.Content.ReadFromJsonAsync<T>(Json.Options, token))!;
    }
    public async Task Command(string path, object value, CancellationToken token = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(60));
        using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(value, options: Json.Options) };
        using var response = await Send(request, timeout.Token);
        await Check(response, timeout.Token);
    }
    private static async Task Check(HttpResponseMessage response, CancellationToken token)
    {
        if (response.IsSuccessStatusCode) return;
        using var data = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(token), cancellationToken: token);
        throw new RequestException(data.RootElement.TryGetProperty("error", out var error) ? error.GetString()! : "Storage request failed.", (int)response.StatusCode);
    }
    public async Task Proxy(HttpContext context, string path)
    {
        using var request = new HttpRequestMessage(new HttpMethod(context.Request.Method), path + context.Request.QueryString);
        if (context.Request.ContentLength is > 0 || context.Request.Method is "POST" or "PUT")
        {
            request.Content = new StreamContent(context.Request.Body);
            if (context.Request.ContentType is not null) request.Content.Headers.ContentType = MediaTypeHeaderValue.Parse(context.Request.ContentType);
            if (context.Request.ContentLength is long length) request.Content.Headers.ContentLength = length;
        }
        using var response = await Send(request, context.RequestAborted);
        context.Response.StatusCode = (int)response.StatusCode;
        context.Response.ContentType = response.Content.Headers.ContentType?.ToString();
        if (response.Content.Headers.ContentDisposition is { } disposition) context.Response.Headers.ContentDisposition = disposition.ToString();
        await response.Content.CopyToAsync(context.Response.Body, context.RequestAborted);
    }
}

public static class StorageGateway
{
    public static void MapStorage(this RouteGroupBuilder api)
    {
        api.MapGet("/storage/config", (StorageClient storage) => new { enabled = storage.Enabled, chunkBytes = StorageOptions.ChunkBytes });
        foreach (var route in new[] {
            ("GET", "batches"), ("POST", "batches"), ("GET", "batches/{id}"), ("DELETE", "batches/{id}"),
            ("POST", "batches/{id}/uploads"), ("PUT", "batches/{id}/uploads/{fileId}"),
            ("POST", "batches/{id}/prepare"), ("POST", "batches/{id}/rename"), ("GET", "batches/{id}/capacity"), ("GET", "batches/{id}/browse"), ("GET", "batches/{id}/download"),
            ("POST", "smb"), ("DELETE", "smb/{id}"), ("GET", "smb/{id}/browse"), ("POST", "batches/{id}/smb-import") })
            api.MapMethods("/storage/" + route.Item2, [route.Item1], async (HttpContext context, StorageClient storage) =>
            {
                var relative = context.Request.Path.Value!["/api/storage/".Length..];
                await storage.Proxy(context, relative);
            });
    }
}
