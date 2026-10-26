using System.Text.Json;

namespace RomChecker.Web.Features.Library;

public static class LibraryEndpoints
{
    public static void MapLibrary(this RouteGroupBuilder api, WebOptions options)
    {
        var root = options.Root;
        api.MapGet("/folders", (string? path, LibraryPaths paths) =>
        {
            var directory = path is null ? root : Path.GetFullPath(Path.Combine(root, path));
            paths.AssertPath(directory, true);
            return new
            {
                path = Path.GetRelativePath(root, directory),
                folders = Directory.EnumerateDirectories(directory).Select(p => new DirectoryInfo(p))
                    .Where(d => !d.Attributes.HasFlag(FileAttributes.ReparsePoint) && !d.Name.StartsWith('_'))
                    .OrderBy(d => d.Name).Take(500)
                    .Select(d => new { name = d.Name, path = Path.GetRelativePath(root, d.FullName), fullPath = d.FullName }).ToArray()
            };
        });
        api.MapGet("/jobs/{id}/results", async (string id, string? q, string? category, string? console,
            int? page, int? size, JobService jobs) =>
        {
            var document = await jobs.ReadJson(id, "results.json");
            var items = document.ValueKind == JsonValueKind.Array ? document.EnumerateArray().ToArray() : [];
            string Field(JsonElement item, string key) => item.TryGetProperty(key, out var value) ? value.ToString() : "";
            var filtered = items.Where(item =>
                (string.IsNullOrEmpty(q) || $"{Field(item, "FileName")} {Field(item, "Reason")} {Field(item, "Folder")}".Contains(q, StringComparison.OrdinalIgnoreCase))
                && (string.IsNullOrEmpty(category) || Field(item, "Category") == category)
                && (string.IsNullOrEmpty(console) || Field(item, "Console") == console)).ToArray();
            var pageNumber = Math.Max(1, page ?? 1);
            var pageSize = Math.Clamp(size ?? 50, 1, 200);
            return new { total = filtered.Length, page = pageNumber, size = pageSize,
                categories = items.Select(i => Field(i, "Category")).Distinct().Order(),
                consoles = items.Select(i => Field(i, "Console")).Distinct().Order(),
                items = filtered.Skip((int)Math.Min((long)(pageNumber - 1) * pageSize, int.MaxValue)).Take(pageSize) };
        });
    }
}
