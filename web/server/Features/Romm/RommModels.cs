using System.Text.Json;
using System.Text.Json.Serialization;

namespace RomChecker.Web.Features.Romm;

public sealed record RommPlatformMapping(string Console, int PlatformId, string Slug);
public sealed record RommConfig(string Url = "", string Token = "", RommPlatformMapping[]? PlatformMappings = null,
    bool AutoPublish = false, string ConnectionId = "", RommPublishRules? PublishRules = null,
    RommSyncSettings? Sync = null);
public sealed record RommSyncSettings(bool AutoImport = false, int[]? PlatformIds = null,
    bool RefreshMetadata = false, int IntervalMinutes = 60);
public sealed record RommFileIdentity(string Path, long Size, [property: JsonPropertyName("sha1")] string SHA1);
public sealed record RommRemoteSnapshot(int PlatformId, RommFileIdentity[] Files, string Fingerprint, string ContentKey);
public sealed record RommRemoteState(string ConnectionId, int RommId, string Name, RommRemoteSnapshot? Snapshot,
    string Status, string? Detail, DateTimeOffset Updated, string[] EntryIds, string? IgnoredFingerprint = null);
public sealed record RommConflictAction(string Action, bool Confirm = false);
public sealed record RommPublishRules(string ReferenceRequirement = "eligible", string[]? Consoles = null,
    string[]? Regions = null, string[]? Categories = null, string[]? BatchIds = null,
    bool AllowFilenameRegions = false, bool IncludeUnknownRegions = false);
public sealed record RommRulePreviewRequest(RommPublishRules? Rules = null, int Page = 1, int Size = 50);
public sealed record RommRuleGroup(string Id, string Name, int Files, string Console, string? BatchId,
    Catalog.CatalogRegionEvidence[] Regions, string Status, string Reason, string[] EntryIds);
public sealed record RommRulePreview(int Total, int Matched, int Ready, int Excluded, int Pending, int Linked, int Failed,
    int Page, int Size, RommRuleGroup[] Items);
public sealed record RommSelection(string[] Ids, bool Confirm = false);
public sealed record RommImport(int[] RomIds, bool Confirm = false, bool ImportChanged = false);
public sealed record RommItem(string EntryId, string Status = "queued", string? Error = null,
    int? RommId = null, string? Fingerprint = null, string? ExportPath = null, string? BatchId = null, string? DetectionJobId = null,
    RommRemoteSnapshot? RemoteSnapshot = null, bool BatchCreationPending = false, string? BatchName = null);
public sealed record RommJob(string Id, string Kind, string Status, DateTimeOffset Created,
    DateTimeOffset? Finished, string? Error, string ConnectionId, RommItem[] Items, DateTimeOffset? AttemptStarted = null,
    bool Automatic = false);
public sealed record RommLink(string EntryId, int? RommId, string Status, JsonElement Metadata,
    DateTimeOffset Updated, string Fingerprint, string ConnectionId, string? ExportPath = null);
public sealed record RommPlatform(int Id, string Name, string Slug);
public sealed record RemoteRom(int Id, string Name, int PlatformId);
