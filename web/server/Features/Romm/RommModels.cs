using System.Text.Json;

namespace RomChecker.Web.Features.Romm;

public sealed record RommPlatformMapping(string Console, int PlatformId, string Slug);
public sealed record RommConfig(string Url = "", string Token = "", RommPlatformMapping[]? PlatformMappings = null,
    bool AutoPublish = false, string ConnectionId = "");
public sealed record RommSelection(string[] Ids, bool Confirm = false);
public sealed record RommImport(int[] RomIds, bool Confirm = false);
public sealed record RommItem(string EntryId, string Status = "queued", string? Error = null,
    int? RommId = null, string? Fingerprint = null, string? ExportPath = null, string? BatchId = null, string? DetectionJobId = null);
public sealed record RommJob(string Id, string Kind, string Status, DateTimeOffset Created,
    DateTimeOffset? Finished, string? Error, string ConnectionId, RommItem[] Items, DateTimeOffset? AttemptStarted = null);
public sealed record RommLink(string EntryId, int? RommId, string Status, JsonElement Metadata,
    DateTimeOffset Updated, string Fingerprint, string ConnectionId, string? ExportPath = null);
public sealed record RommPlatform(int Id, string Name, string Slug);
public sealed record RemoteRom(int Id, string Name, int PlatformId);
