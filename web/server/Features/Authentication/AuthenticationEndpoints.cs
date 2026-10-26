using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace RomChecker.Web.Features.Authentication;

public static class AuthenticationEndpoints
{
    public static RouteGroupBuilder MapAuthentication(this WebApplication app, WebOptions options)
    {
        var password = options.Password;
        app.MapPost("/api/login", async (LoginRequest request, HttpContext context) =>
        {
            var expected = SHA256.HashData(Encoding.UTF8.GetBytes(password));
            var actual = SHA256.HashData(Encoding.UTF8.GetBytes(request.Password ?? ""));
            if (!CryptographicOperations.FixedTimeEquals(expected, actual)) return Results.Json(new { error = "Invalid password." }, statusCode: 401);
            // Bind sessions to the configured password so rotating it invalidates old cookies.
            var identity = new ClaimsIdentity([new Claim(ClaimTypes.Name, "Administrator"),
                new Claim("credential", Convert.ToHexString(expected))], CookieAuthenticationDefaults.AuthenticationScheme);
            await context.SignInAsync(new ClaimsPrincipal(identity));
            return Results.Ok(new { authenticated = true });
        }).RequireRateLimiting("login");
        app.MapPost("/api/logout", async (HttpContext context) =>
        {
            await context.SignOutAsync();
            return Results.NoContent();
        }).RequireAuthorization();
        var api = app.MapGroup("/api").RequireAuthorization();
        api.AddEndpointFilter(async (context, next) =>
        {
            if (context.HttpContext.User.FindFirstValue("credential") != Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(password))))
                return Results.Unauthorized();
            return await next(context);
        });
        api.MapGet("/session", () => new { authenticated = true });
        return api;
    }
}
