using System.Text.Json;
using System.Text.Json.Serialization;

namespace RomChecker.Web.Features.Catalog;

public sealed record CatalogApproval([property: JsonPropertyName("sha256")] string SHA256, string Reason, string Actor, DateTimeOffset ApprovedUtc);
public sealed record CatalogEligibility(bool Eligible, string? Reason);
public sealed record CatalogHistory(string Id, string EntryId, DateTimeOffset CreatedUtc, string Actor,
    string Action, [property: JsonPropertyName("sha256")] string SHA256, string Detail);
public sealed record CatalogEntry
{
    public string Id { get; init; } = "";
    public string? BatchId { get; init; }
    public string CollectionId { get; init; } = "";
    public string GroupId { get; init; } = "";
    public string FileName { get; init; } = "";
    public string Console { get; init; } = "-";
    public string ConsoleName { get; init; } = "Unknown / Needs identification";
    public string Category { get; init; } = "Unknown_Check_Manually";
    public string RelativePath { get; init; } = "";
    public string OriginalRelative { get; init; } = "";
    public long Length { get; init; }
    [JsonPropertyName("sha256")]
    public string SHA256 { get; init; } = "";
    public DateTimeOffset? CheckedUtc { get; init; }
    public DateTimeOffset? CheckInvalidatedUtc { get; init; }
    public string CheckStatus { get; init; } = "unchecked";
    public string ReferenceStatus { get; init; } = "unmatched";
    public string IntegrityStatus { get; init; } = "Unknown";
    public string Security { get; init; } = "Not checked";
    public string Organization { get; init; } = "Pending";
    public string SyncStatus { get; init; } = "not-published";
    public string HoldReason { get; init; } = "";
    public bool PublishEligible { get; init; }
    public string? PublishBlockReason { get; init; }
    public CatalogApproval? Approval { get; init; }
    public JsonElement Evidence { get; init; } = JsonSerializer.SerializeToElement(new { });
    public string? DuplicateOf { get; init; }
    public bool Missing { get; init; }
    public DateTimeOffset UpdatedUtc { get; init; }
    public DateTime FileModifiedUtc { get; init; }
}
public sealed record CatalogQuery(string? Q = null, string? Console = null, string? Category = null,
    string? Checks = null, string? Reference = null, bool? Attention = null, string? Publication = null,
    int Page = 1, int Size = 100, string? SyncStatus = null, string? Sort = null, bool? Duplicates = null);
public sealed record CatalogGroup(string Key, string Name, int Total, int Checked, int Attention, string[] Ids);
public sealed record CatalogConsole(string Key, string Name);
public sealed record CatalogCounts(int Total, int Checked, int Unchecked, int Attention, int Eligible, int Missing);
public sealed record CatalogPage(CatalogEntry[] Items, int Total, int Filtered, int Page, int Size,
    CatalogGroup[] Groups, string[] Ids, string[] Categories, CatalogCounts Counts, CatalogConsole[]? Consoles = null);
public sealed record CatalogApproveRequest(string[] Ids, string Reason, bool Confirm = false, int MaxSelection = 1000,
    [property: JsonPropertyName("sha256")] Dictionary<string, string>? SHA256 = null);
public sealed record CatalogVerifyRequest(string[] Ids, EngineSettings? Settings = null,
    bool Organize = false, bool Confirm = false, int MaxSelection = 1000);
public sealed record CatalogVerificationStep(string? BatchId, string[] Ids, string Status = "queued", string? JobId = null,
    string[]? CollectionIds = null, bool Detected = false);
public sealed record CatalogVerification(string Id, DateTimeOffset CreatedUtc, string Status,
    CatalogVerifyRequest Request, CatalogVerificationStep[] Steps, string? Error = null);
