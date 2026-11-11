# Reverse Proxy and HTTPS

Keep the internal storage service and database private. Terminate HTTPS at a
trusted proxy; do not expose this single-administrator tool as a public upload
service.

## Dedicated hostname

Use an empty `ROMCHECKER_PATH_BASE`. Forward requests unchanged, preserve the
public Host, and include that hostname in `ROMCHECKER_ALLOWED_HOSTS`.
Keep `127.0.0.1` allowed for the container health check.

## Subpath

For `https://roms.example.com/romchecker/`:

```dotenv
ROMCHECKER_PATH_BASE=/romchecker
ROMCHECKER_ALLOWED_HOSTS=localhost;127.0.0.1;roms.example.com
ROMCHECKER_TRUSTED_PROXIES=<exact proxy source IP seen inside the app container>
```

Replace the placeholder with your actual trusted proxy IP. Do not use wildcard
trust or a whole untrusted subnet. The proxy must preserve the configured path
prefix; the application handles it. Navigation uses hash routes, so bookmarked
views do not require a separate client-side fallback rewrite.

## Proxy behavior

Replace untrusted client forwarding headers and set `X-Forwarded-Proto` and
`X-Forwarded-For`. The app supports one configured forwarding hop.
Configure streaming/event connections and upload timeouts for long-running work;
do not buffer an entire ROM transfer in proxy memory.

The supplied host ports bind to loopback. A proxy running on the host can use
them; a proxy container needs explicitly arranged network access and a stable
trusted source address. Do not publish internal service ports to solve this.

RomM has its own public URL, cookie, proxy, and optional subpath settings. Configure
those according to its documentation; ROM Checker's settings do not configure RomM.
The private combined-stack API URL remains `http://romm:8080` unless you deliberately
change its network topology.

See the [operational proxy examples](https://github.com/Phthisicus/ROM-Checker/blob/development/docs/REFERENCE.md#reverse-proxies)
for additional deployment details.
