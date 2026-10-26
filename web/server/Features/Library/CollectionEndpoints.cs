using System.Text.Json;
using RomChecker.Web.Features.Storage;

namespace RomChecker.Web.Features.Library;

public static class CollectionEndpoints
{
    public static void MapCollections(this RouteGroupBuilder api)
    {
        api.MapGet("/collections/{id}/files", async (string id, string? q, string? console, string? filter,
            int? page, StorageClient storage, Store store, CancellationToken token) =>
        {
            _ = await storage.Get<Batch>($"batches/{StoragePaths.Id(id)}", token);
            var root = storage.BatchRoot(id);
            var path = Path.Combine(root, "_RomSorter", "collection.json");
            LibraryPaths.AssertPath(root, path);
            JsonElement[] rows = [];
            var document = await JobService.ReadFileJson(path);
            var detected = document.ValueKind == JsonValueKind.Array;
            if (detected)
            {
                rows = document.EnumerateArray().Select(row => row.Clone()).ToArray();
            }
            string Field(JsonElement row, string name) => row.TryGetProperty(name, out var value) ? value.ToString() : "";
            bool Checked(JsonElement row) => Field(row, "CheckedUtc").Length > 0;
            bool Attention(JsonElement row) => Field(row, "HoldReason").Length > 0 || Field(row, "Organization") == "Failed";
            var active = store.All().FirstOrDefault(job => job.Request.BatchId == id && job.Action == "verify" && job.Status is "queued" or "running" or "cancelling");
            var selected = active?.Request.Selection?.ToHashSet(StringComparer.Ordinal);
            var selectedGroups = rows.Where(row => selected?.Contains(Field(row, "CollectionId")) == true)
                .Select(row => Field(row, "GroupId")).ToHashSet(StringComparer.Ordinal);
            bool InProgress(JsonElement row) => active is not null && (selected is null || selected.Contains(Field(row, "CollectionId")) || selectedGroups.Contains(Field(row, "GroupId")));
            var groups = rows.GroupBy(row => Field(row, "Console")).OrderBy(group => group.Key == "-" ? "zzzz" : group.Key)
                .Select(group => new
                {
                    key = group.Key, name = Field(group.First(), "ConsoleName"),
                    folder = Field(group.First(), "ConsoleFolder"), total = group.Count(),
                    checkedFiles = group.Count(Checked), attention = group.Count(Attention),
                    organized = group.Count(row => Field(row, "Organization") == "Organized"),
                    ids = group.Select(row => Field(row, "CollectionId")).ToArray()
                }).ToArray();
            var filtered = rows.Where(row =>
                (string.IsNullOrEmpty(console) || Field(row, "Console") == console)
                && (string.IsNullOrEmpty(q) || $"{Field(row, "FileName")} {Field(row, "Reason")}".Contains(q, StringComparison.OrdinalIgnoreCase))
                && (filter switch { "attention" => Attention(row), "unchecked" => !Checked(row),
                    "completed" => Checked(row) && !Attention(row), "progress" => InProgress(row), _ => true }))
                .OrderByDescending(Attention).ThenBy(row => Field(row, "FileName"), StringComparer.OrdinalIgnoreCase).ToArray();
            var number = Math.Clamp(page ?? 1, 1, 100000);
            return new
            {
                detected, total = rows.Length, filtered = filtered.Length, page = number, size = 100,
                checkedFiles = rows.Count(Checked), attention = rows.Count(Attention),
                organized = rows.Count(row => Field(row, "Organization") == "Organized"),
                datMatches = rows.Count(row => Field(row, "DatMatch").Length > 0),
                onlineMatches = rows.Count(row => Field(row, "HashMatch").Length > 0),
                threats = rows.Count(row => Field(row, "Security") is "Malicious" or "Suspicious"),
                groups, items = filtered.Skip((number - 1) * 100).Take(100)
            };
        });
    }
}
