using System.Net;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.FileProviders;
using RomChecker.Web;
using RomChecker.Web.Infrastructure;
using RomChecker.Web.Features.Authentication;
using RomChecker.Web.Features.Jobs;
using RomChecker.Web.Features.Library;
using RomChecker.Web.Features.Reports;
using RomChecker.Web.Features.Settings;
using RomChecker.Web.Features.Storage;
using RomChecker.Web.Features.Romm;
using RomChecker.Web.Features.Catalog;

if (Environment.GetEnvironmentVariable("ROMCHECKER_ROLE") == "storage")
{
    await StorageHost.Run(args);
    return;
}

var builder = WebApplication.CreateBuilder(args);
var buildIdentity = BuildIdentity.Load(Path.Combine(AppContext.BaseDirectory, "build-info.json"));
string Env(string name, string fallback) => Environment.GetEnvironmentVariable(name) ?? fallback;
var root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Env("ROMCHECKER_LIBRARY", "/library")));
var data = Path.GetFullPath(Env("ROMCHECKER_DATA", "/data"));
var engine = Path.GetFullPath(Env("ROMCHECKER_ENGINE", Path.Combine(builder.Environment.ContentRootPath, "..", "..")));
var pathBase = Env("ROMCHECKER_PATH_BASE", "").TrimEnd('/');
if (pathBase.Length > 0 && (!pathBase.StartsWith('/') || pathBase.Contains("..")
    || pathBase.Any(c => !(char.IsAsciiLetterOrDigit(c) || c is '/' or '-' or '_'))))
    throw new InvalidOperationException("ROMCHECKER_PATH_BASE must be a URL path such as /romchecker.");
var password = Env("ROMCHECKER_PASSWORD", "");
if (password.Length < 16) throw new InvalidOperationException("Set ROMCHECKER_PASSWORD to at least 16 characters.");
if (!Directory.Exists(root)) throw new InvalidOperationException("ROMCHECKER_LIBRARY must be an existing directory.");
if (!File.Exists(Path.Combine(engine, "RomSorter.ps1"))) throw new InvalidOperationException("ROMCHECKER_ENGINE must contain RomSorter.ps1.");
var dataRelative = Path.GetRelativePath(root, data);
if (dataRelative == "." || !Path.IsPathRooted(dataRelative) && dataRelative != ".."
    && !dataRelative.StartsWith(".." + Path.DirectorySeparatorChar))
    throw new InvalidOperationException("Application data must be outside the ROM library.");
var options = new WebOptions(root, data, engine, Env("ROMCHECKER_POWERSHELL", "pwsh"), password, pathBase,
    TimeSpan.FromHours(double.Parse(Env("ROMCHECKER_JOB_TIMEOUT_HOURS", "24"), System.Globalization.CultureInfo.InvariantCulture)));
Directory.CreateDirectory(data);
var databaseCompatibility = DatabaseCompatibility.Initialize(data);
builder.Services.AddSingleton(buildIdentity);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton(ReleaseInfo.Load(Path.Combine(AppContext.BaseDirectory, "release-info.json"), buildIdentity));
builder.Services.AddSingleton(databaseCompatibility);
builder.Services.AddHttpClient<UpdateChecker>(client =>
    { client.Timeout = TimeSpan.FromSeconds(20); client.MaxResponseContentBufferSize = 2 * 1024 * 1024; })
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { AllowAutoRedirect = false });
builder.Services.AddSingleton<UpdateMonitor>();
builder.Services.AddHostedService(provider => provider.GetRequiredService<UpdateMonitor>());
builder.Services.AddSingleton(options);
builder.Services.AddSingleton<Store>();
builder.Services.AddSingleton<LibraryPaths>();
builder.Services.AddSingleton<SettingsValidator>();
builder.Services.AddSingleton<EngineRunner>();
builder.Services.AddHttpClient("storage", client => client.Timeout = Timeout.InfiniteTimeSpan)
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(10), AllowAutoRedirect = false });
builder.Services.AddSingleton<StorageClient>();
builder.Services.AddHttpClient("romm", client => client.Timeout = TimeSpan.FromMinutes(10))
    .ConfigurePrimaryHttpMessageHandler(() => new SocketsHttpHandler { ConnectTimeout = TimeSpan.FromSeconds(10), AllowAutoRedirect = false });
builder.Services.AddSingleton<RommStore>();
builder.Services.AddSingleton<RommClient>();
builder.Services.AddSingleton<RommService>();
builder.Services.AddHostedService(provider => provider.GetRequiredService<RommService>());
builder.Services.AddSingleton<JobService>();
builder.Services.AddHostedService(provider => provider.GetRequiredService<JobService>());
builder.Services.AddCatalog();
builder.Services.AddDataProtection().PersistKeysToFileSystem(new DirectoryInfo(Path.Combine(data, "keys")))
    .SetApplicationName("RomChecker");
builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme).AddCookie(cookie =>
{
    cookie.Cookie.Name = "romchecker";
    cookie.Cookie.Path = string.IsNullOrEmpty(pathBase) ? "/" : pathBase;
    cookie.Cookie.HttpOnly = true;
    cookie.Cookie.SameSite = SameSiteMode.Strict;
    cookie.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
    cookie.ExpireTimeSpan = TimeSpan.FromHours(8);
    cookie.SlidingExpiration = true;
    cookie.Events.OnRedirectToLogin = context => { context.Response.StatusCode = 401; return Task.CompletedTask; };
    cookie.Events.OnRedirectToAccessDenied = context => { context.Response.StatusCode = 403; return Task.CompletedTask; };
});
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(rate =>
{
    rate.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    rate.AddPolicy("login", context =>
        RateLimitPartition.GetFixedWindowLimiter(context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions { PermitLimit = 5, Window = TimeSpan.FromMinutes(1), QueueLimit = 0 }));
});
builder.Services.Configure<Microsoft.AspNetCore.Http.Json.JsonOptions>(json =>
    json.SerializerOptions.UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow);
builder.WebHost.ConfigureKestrel(kestrel => kestrel.Limits.MaxRequestBodySize = StorageOptions.ChunkBytes);
var proxies = Env("ROMCHECKER_TRUSTED_PROXIES", "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
if (proxies.Length > 0)
{
    builder.Services.Configure<ForwardedHeadersOptions>(forward =>
    {
        forward.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
        forward.ForwardLimit = 1;
        forward.KnownIPNetworks.Clear();
        forward.KnownProxies.Clear();
        foreach (var proxy in proxies) forward.KnownProxies.Add(IPAddress.Parse(proxy));
    });
}
var app = builder.Build();
app.Logger.LogInformation("ROM Checker {Version}, build {BuildNumber}, attempt {BuildAttempt}, channel {Channel}, commit {Commit}, built {BuiltUtc}, schema {Schema}",
    buildIdentity.Version, buildIdentity.BuildNumber, buildIdentity.BuildAttempt, buildIdentity.Channel,
    buildIdentity.Commit, buildIdentity.BuiltUtc, databaseCompatibility.Version);
if (buildIdentity.Channel == "local")
    app.Logger.LogWarning("Local build identity: this is not a versioned published container.");
app.Use(async (context, next) =>
{
    try { await next(context); }
    catch (Exception ex) when (ex is RequestException or BadHttpRequestException)
    {
        context.Response.StatusCode = ex is RequestException request ? request.Status : 400;
        await context.Response.WriteAsJsonAsync(new { error = ex.Message });
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    catch (Exception ex)
    {
        app.Logger.LogError(ex, "Unhandled request failure");
        if (!context.Response.HasStarted)
        {
            context.Response.StatusCode = 500;
            await context.Response.WriteAsJsonAsync(new { error = "The request failed. Check the server logs." });
        }
    }
});
if (proxies.Length > 0) app.UseForwardedHeaders();
if (pathBase.Length > 0)
{
    app.UsePathBase(pathBase);
    app.Use(async (context, next) =>
    {
        if (context.Request.PathBase != pathBase) { context.Response.StatusCode = 404; return; }
        await next(context);
    });
}
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Content-Type-Options"] = "nosniff";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'";
    if (context.Request.Path.StartsWithSegments("/api"))
    {
        context.Response.Headers.CacheControl = "no-store";
        if (context.Request.Method is not ("GET" or "HEAD") && context.Request.Headers["X-RomChecker"] != "1")
            throw new RequestException("Missing same-origin request header.", 403);
        if (context.Request.Headers.TryGetValue("Origin", out var origin)
            && origin != $"{context.Request.Scheme}://{context.Request.Host}")
            throw new RequestException("Cross-origin requests are not allowed.", 403);
    }
    await next(context);
});
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));
var api = app.MapAuthentication(options);
api.MapSettings(options);
api.MapLibrary(options);
api.MapCollections();
api.MapJobs();
api.MapReports();
api.MapStorage();
api.MapRomm();
api.MapCatalog();
var webRoot = Path.GetFullPath(Env("ROMCHECKER_WEB_ROOT", Path.Combine(engine, "web", "client", "dist")));
if (Directory.Exists(webRoot))
{
    var assets = Path.Combine(webRoot, "assets");
    if (Directory.Exists(assets))
        app.UseStaticFiles(new StaticFileOptions { FileProvider = new PhysicalFileProvider(assets), RequestPath = "/assets" });
}
app.MapGet("/", async (HttpContext context) =>
{
    if (pathBase.Length > 0 && !context.Request.Path.Value!.EndsWith('/'))
        return Results.Redirect(pathBase + "/");
    var index = Path.Combine(webRoot, "index.html");
    if (!File.Exists(index)) return Results.Problem("Frontend is not built. Run npm ci and npm run build in web/client.", statusCode: 503);
    context.Response.Headers.CacheControl = "no-store";
    return Results.Content((await File.ReadAllTextAsync(index)).Replace("__BASE_PATH__", pathBase), "text/html");
});
app.Run();
