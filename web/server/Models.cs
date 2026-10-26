using System.Text.Json;

namespace RomChecker.Web;

public sealed record EngineSettings
{
    public string Console { get; init; } = "All";
    public string Layout { get; init; } = "ByConsole";
    public string DatFolder { get; init; } = "";
    public bool SortByCategory { get; init; } = true;
    public bool DefenderScan { get; init; } = true;
    public bool Strict { get; init; }
    public bool RequireDatMatch { get; init; } = true;
    public bool MoveBSandST { get; init; }
    public bool ProtectAppFolders { get; init; } = true;
    public bool MoveCompanions { get; init; } = true;
    public bool KeepGameFolders { get; init; } = true;
    public string DuplicateMode { get; init; } = "Move";
    public bool CleanEmptyFolders { get; init; } = true;
    public bool UseFolderHints { get; init; } = true;
    public int HashLimitMB { get; init; } = 4096;
    public bool AutoDat { get; init; } = true;
    public string Hasheous { get; init; } = "All";
    public bool IdentifyUnknown { get; init; } = true;
    public bool RetailOnly { get; init; } = true;
    public string OnlineCheck { get; init; } = "Off";
    public bool ResumeScans { get; init; } = true;
    public int ArchiveMaxMB { get; init; } = 16384;
    public int ArchiveMaxEntries { get; init; } = 10000;
    public int ArchiveMaxDepth { get; init; } = 3;
    public int ArchiveTimeoutSeconds { get; init; } = 300;
}

public sealed record Review(string Path, string Decision);
public sealed record JobRequest(string Action, string? SourceId = null, string? Journal = null,
    Review[]? Reviews = null, bool Confirm = false);
public sealed record Job(string Id, string Action, string Status, DateTimeOffset Created,
    DateTimeOffset? Finished, string? Error, JobRequest Request, EngineSettings Settings);
public sealed record LoginRequest(string Password);
public sealed record WebOptions(string Root, string Data, string EngineDirectory, string PowerShell,
    string Password, string PathBase, TimeSpan JobTimeout);

public static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web);
    public static readonly JsonSerializerOptions Engine = new() { WriteIndented = true };
    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);
}

public sealed class RequestException(string message, int status = 400) : Exception(message)
{
    public int Status { get; } = status;
}
