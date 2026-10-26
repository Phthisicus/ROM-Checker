namespace RomChecker.Web.Features.Jobs;

public sealed record JobAction(
    string Feature,
    bool ChangesFiles = false,
    string[]? SourceActions = null,
    bool PreserveSourceSettings = false,
    bool RequiresJournal = false);

public static class JobActions
{
    private static readonly string[] ResultPreviews = ["scan", "inventory", "workflow", "plan"];
    private static readonly IReadOnlyDictionary<string, JobAction> Definitions =
        new Dictionary<string, JobAction>(StringComparer.Ordinal)
        {
            ["scan"] = new("Verification"),
            ["inventory"] = new("Organization"),
            ["plan"] = new("Organization", SourceActions: ResultPreviews),
            ["apply"] = new("Organization", ChangesFiles: true, SourceActions: ResultPreviews, PreserveSourceSettings: true),
            ["unpack"] = new("Archives", ChangesFiles: true),
            ["workflow"] = new("Workflows", ChangesFiles: true),
            ["history"] = new("Recovery"),
            ["undo-preview"] = new("Recovery", RequiresJournal: true),
            ["undo"] = new("Recovery", ChangesFiles: true, RequiresJournal: true),
            ["cleanup-preview"] = new("Archives"),
            ["cleanup"] = new("Archives", ChangesFiles: true, SourceActions: ["cleanup-preview"])
        };

    public static JobAction Get(string? action) =>
        action is not null && Definitions.TryGetValue(action, out var definition)
            ? definition : throw new RequestException("Unknown job action.");
}
