namespace RomChecker.Web.Features.Romm;

public static class RommEndpoints
{
    public static void MapRomm(this RouteGroupBuilder api)
    {
        api.MapGet("/romm/config", (RommStore store, RommService service) =>
        {
            var config = store.Config();
            return new { config.Url, configured = config.Token.Length > 0, platformMappings = config.PlatformMappings ?? [],
                config.AutoPublish, service.ExportRoot, transport = "shared-library" };
        });
        api.MapPut("/romm/config", async (RommConfig request, RommService service) =>
        {
            await service.SaveConfig(request);
            return Results.NoContent();
        });
        api.MapPost("/romm/test", async (RommStore store, RommClient client, CancellationToken token) =>
        {
            var config = store.Config();
            var platforms = await client.Platforms(config, token);
            var spec = await client.Get(config, "openapi.json", token);
            if (!spec.TryGetProperty("paths", out var paths)) throw new RequestException("RomM's OpenAPI schema has no endpoint definitions.", 502);
            bool Has(string path) => paths.TryGetProperty(path, out _);
            var scans = Has("/api/tasks/scan");
            var hashes = Has("/api/roms/by-hash");
            return new { version = spec.TryGetProperty("info", out var info) ? RommClient.Text(info, "version") : "",
                platforms, capabilities = new { scans, hashes, sharedLibrary = true },
                compatible = scans && hashes,
                message = scans && hashes ? "Connection and required API capabilities confirmed. Mount the exported library in RomM before publishing."
                    : "This RomM version lacks required scan or exact-hash APIs. Upgrade before enabling publishing." };
        });
        api.MapGet("/romm/links", (RommService service) => service.Links());
        api.MapGet("/romm/artwork/{entryId}", async (string entryId, RommService service, RommStore store,
            RommClient client, CancellationToken token) =>
        {
            var link = service.Links().FirstOrDefault(link => link.EntryId == entryId && link.Status == "linked");
            if (link is null) return Results.NotFound();
            var config = store.Config();
            var root = RommClient.ValidateUrl(config.Url);
            var path = RommClient.Text(link.Metadata, "path_cover_small");
            if (path.Length == 0) path = RommClient.Text(link.Metadata, "path_cover_large");
            if (path.Length == 0) path = RommClient.Text(link.Metadata, "url_cover");
            if (path.Length == 0 || !Uri.TryCreate(root, path, out var image)
                || image.Scheme != root.Scheme || image.Host != root.Host || image.Port != root.Port
                || !string.IsNullOrEmpty(image.UserInfo))
                return Results.NotFound();
            using var response = await client.Send(config, image.AbsoluteUri, HttpMethod.Get, token);
            if (!response.IsSuccessStatusCode) return Results.NotFound();
            var type = response.Content.Headers.ContentType?.MediaType;
            if (type is not ("image/png" or "image/jpeg" or "image/webp" or "image/gif"))
                throw new RequestException("RomM artwork format is not supported.", 502);
            await using var input = await response.Content.ReadAsStreamAsync(token);
            using var output = new MemoryStream();
            var buffer = new byte[65536];
            int count;
            while ((count = await input.ReadAsync(buffer, token)) > 0)
            {
                if (output.Length + count > 5 * 1024 * 1024) throw new RequestException("RomM artwork exceeds 5 MiB.", 502);
                await output.WriteAsync(buffer.AsMemory(0, count), token);
            }
            return Results.File(output.ToArray(), type);
        });
        api.MapGet("/romm/jobs", (RommStore store) => store.Jobs().Take(200));
        api.MapPost("/romm/preview", (RommSelection request, RommService service) => service.Preview(request.Ids));
        api.MapPost("/romm/publish", (RommSelection request, RommService service) => service.Queue("publish", request.Ids, request.Confirm));
        api.MapPost("/romm/metadata", (RommSelection request, RommService service) => service.Queue("metadata", request.Ids, request.Confirm));
        api.MapPost("/romm/import", (RommImport request, RommService service) => service.QueueImport(request.RomIds, request.Confirm));
        api.MapPost("/romm/jobs/{id}/retry", (string id, RommService service) => service.Retry(id));
        api.MapGet("/romm/roms", async (string? q, int? page, RommStore store, RommClient client, CancellationToken token) =>
        {
            var number = Math.Clamp(page ?? 1, 1, 100000);
            var result = await client.Get(store.Config(), $"api/roms?limit=50&offset={(number - 1) * 50}&search_term={Uri.EscapeDataString(q ?? "")}", token);
            return new { items = RommClient.Array(result).Select(item => new RemoteRom(RommClient.Number(item, "id"),
                    RommClient.Text(item, "name"), RommClient.Number(item, "platform_id"))),
                total = RommClient.Number(result, "total"), page = number, size = 50 };
        });
    }
}
