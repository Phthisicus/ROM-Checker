using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace RomChecker.Web.Features.Romm;

public sealed class RommClient(IHttpClientFactory factory)
{
    public static Uri ValidateUrl(string url)
    {
        if (!Uri.TryCreate(url.TrimEnd('/') + "/", UriKind.Absolute, out var uri)
            || uri.Scheme is not ("http" or "https") || !string.IsNullOrEmpty(uri.UserInfo)
            || !string.IsNullOrEmpty(uri.Query) || !string.IsNullOrEmpty(uri.Fragment))
            throw new RequestException("Use an http(s) RomM base URL without credentials, query, or fragment.");
        return uri;
    }
    public async Task<HttpResponseMessage> Send(RommConfig config, string path, HttpMethod method,
        CancellationToken token, object? body = null)
    {
        var baseUri = ValidateUrl(config.Url);
        if (string.IsNullOrWhiteSpace(config.Token)) throw new RequestException("Configure a RomM API token first.", 409);
        using var request = new HttpRequestMessage(method, new Uri(baseUri, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", config.Token);
        if (body is not null) request.Content = JsonContent.Create(body, options: Json.Options);
        HttpResponseMessage response;
        try { response = await factory.CreateClient("romm").SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token); }
        catch (HttpRequestException) { throw new RequestException("RomM is unreachable. Check its URL, network and TLS certificate.", 503); }
        if (response.IsSuccessStatusCode || response.StatusCode == HttpStatusCode.NotFound) return response;
        var status = (int)response.StatusCode;
        response.Dispose();
        // Do not echo remote bodies: they can contain credentials, paths, or untrusted HTML.
        throw new RequestException(status switch
        {
            401 or 403 => "RomM rejected authentication or the API token lacks the required scope.",
            409 => "RomM is busy or reports a conflict. Retry after reviewing the remote operation.",
            >= 300 and < 400 => "RomM redirected the request. Configure its final base URL; redirects are not followed.",
            _ => $"RomM request failed (HTTP {status}). Review RomM's logs."
        }, status is 401 or 403 ? 502 : 503);
    }
    public async Task<JsonElement> Get(RommConfig config, string path, CancellationToken token)
    {
        using var response = await Send(config, path, HttpMethod.Get, token);
        if (response.StatusCode == HttpStatusCode.NotFound) throw new RequestException("This RomM resource or API capability is unavailable (HTTP 404).", 404);
        // Metadata is bounded separately from streaming ROM downloads.
        if (response.Content.Headers.ContentLength > 16 * 1024 * 1024)
            throw new RequestException("RomM metadata response exceeds the 16 MiB limit.", 502);
        await using var stream = await response.Content.ReadAsStreamAsync(token);
        using var bounded = new MemoryStream();
        var buffer = new byte[65536];
        int read;
        while ((read = await stream.ReadAsync(buffer, token)) > 0)
        {
            if (bounded.Length + read > 16 * 1024 * 1024) throw new RequestException("RomM metadata response exceeds the 16 MiB limit.", 502);
            await bounded.WriteAsync(buffer.AsMemory(0, read), token);
        }
        try
        {
            using var document = JsonDocument.Parse(bounded.ToArray());
            return document.RootElement.Clone();
        }
        catch (JsonException) { throw new RequestException("RomM returned invalid JSON. Verify its URL and API compatibility.", 502); }
    }
    public static string Text(JsonElement value, string name) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(name, out var property) ? property.ToString() : "";
    public static int Number(JsonElement value, string name) => int.TryParse(Text(value, name), out var number) ? number : 0;
    public static JsonElement[] Array(JsonElement value) => value.ValueKind == JsonValueKind.Array
        ? value.EnumerateArray().Select(item => item.Clone()).ToArray()
        : value.ValueKind == JsonValueKind.Object && value.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray().Select(item => item.Clone()).ToArray() : throw new RequestException("Unexpected RomM list response.", 502);
    public async Task<RommPlatform[]> Platforms(RommConfig config, CancellationToken token) =>
        Array(await Get(config, "api/platforms", token))
            .Select(item => new RommPlatform(Number(item, "id"), Text(item, "name"), Text(item, "fs_slug").Length > 0 ? Text(item, "fs_slug") : Text(item, "slug"))).ToArray();
    public async Task<JsonElement?> ByHash(RommConfig config, string sha1, int platform, CancellationToken token)
    {
        if (sha1.Length != 40 || !sha1.All(Uri.IsHexDigit)) throw new RequestException("Complete SHA1 evidence is required to link RomM metadata.");
        JsonElement result;
        try { result = await Get(config, "api/roms/by-hash?sha1_hash=" + sha1, token); }
        catch (RequestException ex) when (ex.Status == 404) { return null; }
        if (Number(result, "platform_id") != platform) throw new RequestException("RomM hash lookup returned a different platform. Review platform mapping.", 409);
        var matches = string.Equals(Text(result, "sha1_hash"), sha1, StringComparison.OrdinalIgnoreCase);
        if (result.TryGetProperty("files", out var files) && files.ValueKind == JsonValueKind.Array)
            matches |= files.EnumerateArray().Any(file => string.Equals(Text(file, "sha1_hash"), sha1, StringComparison.OrdinalIgnoreCase));
        if (!matches) throw new RequestException("RomM returned no exact file hash evidence. Refusing title-only metadata linking.", 409);
        return result;
    }
    public async Task Scan(RommConfig config, int[] platforms, CancellationToken token)
    {
        using var response = await Send(config, "api/tasks/scan", HttpMethod.Post, token,
            new { type = "quick", platforms = platforms.Distinct().ToArray() });
        if (response.StatusCode == HttpStatusCode.NotFound)
            throw new RequestException("RomM does not support token-authenticated scan tasks. Upgrade RomM or run a scan there, then retry metadata linking.", 409);
    }
}
