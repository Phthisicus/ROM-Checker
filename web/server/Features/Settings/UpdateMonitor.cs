namespace RomChecker.Web.Features.Settings;

public sealed record UpdateStatus(string Status, string Message, DateTimeOffset? LastAttemptUtc = null,
    DateTimeOffset? LastSuccessUtc = null, bool Stale = false, UpdateResult? Result = null);

public sealed class UpdateMonitor(IServiceScopeFactory scopes, BuildIdentity build,
    ILogger<UpdateMonitor> logger, TimeProvider time) : BackgroundService
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private UpdateStatus state = new("unavailable", "No update check has run yet.");
    public static bool Enabled => Environment.GetEnvironmentVariable("ROMCHECKER_CHECK_UPDATES") == "true";
    public static bool Scheduled => Environment.GetEnvironmentVariable("ROMCHECKER_SCHEDULED_UPDATES") == "true";

    public UpdateStatus Status => !Enabled
        ? new("disabled", "Update checks are opt-in. Set ROMCHECKER_CHECK_UPDATES=true on the server.")
        : build.Channel == "local" ? new("unavailable", "Local builds have no published update channel.")
        : Volatile.Read(ref state);

    public async Task<UpdateStatus> Check(CancellationToken cancellation)
    {
        if (!Enabled || build.Channel == "local") return Status;
        await gate.WaitAsync(cancellation);
        try
        {
            var now = time.GetUtcNow();
            if (state.LastAttemptUtc is { } last && now - last < TimeSpan.FromMinutes(1)) return Status;
            var previous = state;
            Volatile.Write(ref state, previous with { Status = "checking", Message = "Checking this image channel...", LastAttemptUtc = now });
            try
            {
                using var scope = scopes.CreateScope();
                var result = await scope.ServiceProvider.GetRequiredService<UpdateChecker>().Check(cancellation);
                Volatile.Write(ref state, new(result.Status, result.Message, now, time.GetUtcNow(), false, result));
            }
            catch (RequestException ex)
            {
                logger.LogWarning(ex, "Update check failed; retaining the last successful result");
                Volatile.Write(ref state, new("error", ex.Message, now, previous.LastSuccessUtc,
                    previous.Result is not null, previous.Result));
            }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
            {
                Volatile.Write(ref state, previous);
                throw;
            }
            return Status;
        }
        finally { gate.Release(); }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!Enabled || !Scheduled || build.Channel == "local") return;
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(Random.Shared.Next(5, 61)), time, stoppingToken);
            while (!stoppingToken.IsCancellationRequested)
            {
                await Check(stoppingToken);
                await Task.Delay(TimeSpan.FromMinutes(360 + Random.Shared.Next(-30, 31)), time, stoppingToken);
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested) { }
    }
}
