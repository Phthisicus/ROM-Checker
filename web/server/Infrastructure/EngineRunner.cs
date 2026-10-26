using System.Diagnostics;
using System.Text;
using System.Text.Json;
using RomChecker.Web.Features.Jobs;
using RomChecker.Web.Features.Library;

namespace RomChecker.Web.Infrastructure;

public sealed class EngineRunner(WebOptions options, LibraryPaths paths)
{
    public async Task Run(Job job, string directory, string? sourceDirectory, CancellationToken cancellation)
    {
        paths.AssertPath(options.Root, true);
        Directory.CreateDirectory(directory);
        var requestPath = Path.Combine(directory, "request.json");
        await File.WriteAllTextAsync(requestPath, JsonSerializer.Serialize(new
        {
            job.Action, Feature = JobActions.Get(job.Action).Feature,
            Root = options.Root, DataDirectory = options.Data, job.Settings,
            SourceDirectory = sourceDirectory,
            job.Request.Journal, job.Request.Reviews
        }, Json.Engine), cancellation);
        var start = new ProcessStartInfo(options.PowerShell)
        {
            WorkingDirectory = options.EngineDirectory, UseShellExecute = false,
            RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, CreateNoWindow = true
        };
        foreach (var arg in new[] { "-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
            "-File", Path.Combine(options.EngineDirectory, "web", "engine", "Invoke-WebJob.ps1"), "-RequestPath", requestPath })
            start.ArgumentList.Add(arg);
        start.Environment["TERM"] = "dumb";
        start.Environment["APPDATA"] = Path.Combine(options.Data, "config");
        start.Environment["XDG_CONFIG_HOME"] = Path.Combine(options.Data, "config");
        start.Environment.Remove("ROMCHECKER_PASSWORD");
        using var process = Process.Start(start) ?? throw new InvalidOperationException("PowerShell could not start.");
        process.StandardInput.Close();
        using var registration = cancellation.Register(() =>
        {
            try { if (!process.HasExited) process.Kill(true); }
            catch (InvalidOperationException) { /* Process exited before cancellation. */ }
        });
        await using var log = new StreamWriter(Path.Combine(directory, "output.log"), false, Encoding.UTF8) { AutoFlush = true };
        var logGate = new SemaphoreSlim(1);
        long written = 0;
        async Task Drain(StreamReader reader, string prefix)
        {
            while (await reader.ReadLineAsync() is { } line)
            {
                await logGate.WaitAsync(CancellationToken.None);
                try
                {
                    if (written < 16 * 1024 * 1024)
                    {
                        await log.WriteLineAsync(prefix + line);
                        written += Encoding.UTF8.GetByteCount(line) + prefix.Length + 1;
                        if (written >= 16 * 1024 * 1024) await log.WriteLineAsync("Log limit reached; later output omitted.");
                    }
                }
                finally { logGate.Release(); }
            }
        }
        await Task.WhenAll(Drain(process.StandardOutput, ""), Drain(process.StandardError, "ERROR: "),
            process.WaitForExitAsync(CancellationToken.None));
        cancellation.ThrowIfCancellationRequested();
        if (process.ExitCode != 0) throw new InvalidOperationException($"Engine exited with code {process.ExitCode}. See the job log for details.");
    }
}
