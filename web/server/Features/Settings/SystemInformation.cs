using System.Diagnostics;
using System.Runtime.InteropServices;

namespace RomChecker.Web.Features.Settings;

public sealed record SystemInformation(string Scope, string OperatingSystem, string Architecture,
    string Runtime, DateTimeOffset StartedUtc, double UptimeSeconds)
{
    private static readonly DateTimeOffset Started = Process.GetCurrentProcess().StartTime.ToUniversalTime();

    public static SystemInformation Read() => new(
        Environment.GetEnvironmentVariable("DOTNET_RUNNING_IN_CONTAINER") == "true" ? "Container" : "Application process",
        RuntimeInformation.OSDescription, RuntimeInformation.ProcessArchitecture.ToString(),
        RuntimeInformation.FrameworkDescription, Started, Math.Max(0, (DateTimeOffset.UtcNow - Started).TotalSeconds));
}
