# ROM Checker

A self-hosted web workspace for verifying and organizing ROM collections, backed by the original ROM Sorter PowerShell engine.

## Web workspace

- Responsive dashboard with dark/light themes, library statistics, and recent activity.
- Library search, console/category filters, pagination, per-file evidence, and HTML/CSV/JSON downloads.
- Independent authenticity, integrity, antivirus, and malware findings. No detections never means guaranteed safe.
- Check-only scanning, sort-only inventory, archive unpacking, and unpack-then-check workflows.
- Draft per-file review decisions: keep, mark original, or quarantine. Rebuild the preview to incorporate decisions; security warnings cannot be overridden through the web interface.
- All six sorting layouts, duplicate policies, custom DAT references, verification options, and archive resource limits.
- Saved move previews, explicit approval, content/inventory revalidation, and journaled recovery. Disc sets and companions stay grouped.
- Background jobs with live events, progress, warnings, downloadable logs, and cancellation for non-mutating jobs.
- Journal inspection, undo previews, restoration, and verified processed-archive cleanup.
- Password authentication, persistent SQLite job/settings storage, non-root Docker runtime, and reverse-proxy subpath support.

This is a **single-administrator, single-library application**, not a multi-tenant upload service. ROMs stay on mounted storage. Optional external services receive hashes and metadata. Browser access does not grant access to arbitrary host folders.

## Run with Docker Compose

Requirements: Docker Engine with Compose, a backed-up ROM folder, and permission for container UID/GID **10001:10001** to read and modify that folder.

1. Copy `.env.example` to `.env`.
2. Set `ROM_LIBRARY` to an absolute host directory. On Docker Desktop, use a shared host folder, for example `C:/ROMs`.
3. Set a unique `ROMCHECKER_PASSWORD` of at least 16 characters.
4. Build locally and start both the application and ClamAV signature updater:

```sh
docker compose build romchecker
docker compose up -d
```

Open `http://localhost:8080/`. The published port binds to loopback by default. The application and updater use the same image tag; `docker compose build romchecker` tags that image for both services.

After CI has published the image, use `docker compose pull && docker compose up -d` instead. The `beta` image follows tested integration builds; `latest` follows approved stable releases. For predictable deployments, pin a version or digest with `ROMCHECKER_IMAGE`.

**Check signature readiness:** `docker compose logs signature-updater`. The first download may take time and ClamAV download rate limits may apply. Antivirus checks report incomplete protection if signatures are unavailable; archives are not extracted when an enabled antivirus check cannot complete. Do not disable antivirus merely to bypass a readiness failure.

The `app-data` volume contains SQLite, authentication keys, job logs, and full result snapshots. The `signatures` volume is updated by the updater and mounted read-only in the application. The library also receives the engine's `_RomSorter` checkpoints, reports, and recovery journals. Back up both the library and application data. Do not run multiple application replicas or the CLI against the same library simultaneously.

Deleting processed recovery archives is **permanent**, disables extraction undo for those archives, and always requires a fresh verified preview and confirmation. Test with a disposable collection before granting access to important files.

## Reverse proxies

Terminate HTTPS at your proxy. Preserve the public `Host`, replace client-supplied forwarding headers, and forward `X-Forwarded-Proto` and `X-Forwarded-For`. Do not expose the backend directly to the Internet.

### Dedicated hostname

Use an empty `ROMCHECKER_PATH_BASE` and forward `/` unchanged. Add the public hostname to `ROMCHECKER_ALLOWED_HOSTS` in `.env`, keeping `127.0.0.1` for the healthcheck.

### URL subpath

For `https://roms.example.com/romchecker/`:

```dotenv
ROMCHECKER_PATH_BASE=/romchecker
ROMCHECKER_ALLOWED_HOSTS=localhost;127.0.0.1;roms.example.com
ROMCHECKER_TRUSTED_PROXIES=172.18.0.1
```

The proxy address above is **only an example**. Configure the exact proxy source IP as seen by the application container; Docker gateways and proxy container addresses differ by deployment. Multiple exact addresses can be comma-separated. Prefer a dedicated, stable proxy address. Never trust arbitrary client networks.

Use the location configuration in [`deploy/nginx.conf`](deploy/nginx.conf) inside an existing HTTPS server block. It preserves the prefix; **do not strip `/romchecker`**. The app owns its configured prefix and rejects unprefixed requests. Forwarded headers are ignored unless the immediate peer is trusted. `X-Forwarded-Prefix` and `X-Forwarded-Host` are deliberately not used.

Keep proxy buffering disabled for `/api/jobs/.../events`, allow long-lived SSE connections, and disable proxy caching. The example disables buffering for the whole application. Cookies use the configured path and become Secure when HTTPS is correctly forwarded. State-changing requests require a custom same-origin header; cross-origin API access is not enabled.

For Traefik or Caddy, use the same rules: preserve the path and public Host, forward the original scheme, and configure the immediate proxy IP. If a containerized proxy shares a private network with the app, route to `romchecker:8080` rather than host loopback and omit the public port mapping if not needed.

Changing the base path requires a restart and a new sign-in. Always include the prefix when probing `/healthz`.

## Local development

Install .NET **10 LTS SDK**, Node.js **24 LTS**, and PowerShell **7**. The bridge remains compatible with Windows PowerShell 5.1 for local Windows use. ClamAV/7-Zip are optional local dependencies but required for their respective operations.

From `web/client`:

```sh
npm ci
npm run build
```

From the repository root, using PowerShell:

```powershell
$env:ROMCHECKER_ENGINE = (Get-Location).Path
$env:ROMCHECKER_LIBRARY = 'C:\ROMs-Test'
$env:ROMCHECKER_DATA = Join-Path $env:TEMP 'romchecker-dev-data'
$env:ROMCHECKER_PASSWORD = '<your own strong development password>'
$env:ASPNETCORE_URLS = 'http://127.0.0.1:5200'
# For Windows PowerShell instead of pwsh:
# $env:ROMCHECKER_POWERSHELL = 'powershell.exe'
dotnet run --project .\web\server
```

On Linux, export equivalent environment variables and use absolute Linux paths. Data must be **outside** the library. Open `http://127.0.0.1:5200/`.

For hot-reloading the UI, run `npm run dev` from `web/client` in another terminal. Vite forwards `/api` to `127.0.0.1:5200`; use an empty base path for development through Vite. The production build is served by ASP.NET Core, without a separate frontend service.

### Feature modules

Features are separate components **inside one application container**, not independently deployed microservices.

| Layer | Module boundaries |
|---|---|
| React `web/client/src/features` | Authentication, overview, library and review state, jobs, recovery/cleanup, settings |
| Shared UI `web/client/src/components` | Accessible dialogs, evidence badges, empty states, progress cards |
| API `web/server/Features` | Authentication, settings validation, library paths/browsing, jobs, reports/downloads |
| Engine `web/engine/Features` | Verification, organization/review/apply, archives/cleanup, recovery, combined workflows |
| Shared infrastructure | SQLite `Store`, serialized `JobService`, isolated PowerShell `Infrastructure/EngineRunner` |

`Program.cs` composes endpoint modules and applies authentication, request protection, and reverse-proxy handling centrally. `App.tsx` coordinates navigation and jobs; feature views own presentation, and `library/useLibrary.ts` owns result filters and review drafts. The engine bridge retains common path checks, progress, snapshots, and report generation; handlers reuse the existing CLI analysis engine.

`Features/Jobs/JobActions.cs` explicitly maps each job action to its engine feature and declares confirmation, source-preview, source-settings, and journal requirements. File-changing actions require confirmation and cannot be cancelled by the user. A fixed engine allowlist and action checks select handlers; the browser cannot supply a script or feature path.

There is **one shared queue across every feature**. Different modules never mutate the mounted library concurrently. Add new operations to the action registry and the appropriate engine handler, wire their feature UI, and extend API/component coverage. Keep cross-feature flows in `Workflows.ps1` and deployment/proxy configuration shared. Splitting modules into separate containers later would require a durable queue and a cross-process library lock; this layout does not pretend to provide those.

### Configuration

| Environment variable | Default / behavior |
|---|---|
| `ROMCHECKER_PASSWORD` | Required, at least 16 characters; rotation invalidates existing sessions |
| `ROMCHECKER_LIBRARY` | `/library`; one mounted root |
| `ROMCHECKER_DATA` | `/data`; persistent storage, outside the library |
| `ROMCHECKER_ENGINE` | `/app` in Docker; directory containing `RomSorter.ps1` |
| `ROMCHECKER_POWERSHELL` | `pwsh`; executable path, never browser-supplied |
| `ROMCHECKER_WEB_ROOT` | `web/client/dist` below the engine directory |
| `ROMCHECKER_PATH_BASE` | Empty; optional path such as `/romchecker`, no trailing slash |
| `ROMCHECKER_TRUSTED_PROXIES` | Empty; explicit IPs, comma-separated, one forwarding hop |
| `AllowedHosts` | ASP.NET Core hostname allowlist; Compose supplies `ROMCHECKER_ALLOWED_HOSTS` |
| `ROMCHECKER_JOB_TIMEOUT_HOURS` | `24`; interrupted operations retain recovery journals |
| `ROMSORTER_VIRUSTOTAL_KEY` | Optional secret; configure on server only |
| `ROMSORTER_MALWAREBAZAAR_KEY` | Optional secret; configure on server only |
| `ROMCHECKER_VERSION`, `ROMCHECKER_COMMIT` | Embedded in published images; visible in Settings |

No keys are exposed through the settings API. Protect the data volume and configuration from other local users. Use the supplied image as a trusted administrative tool: only mount the intended library, never the Docker socket or the host root. Symlink/junction traversal is rejected. Do not allow untrusted processes to alter library paths during file operations.

### Verification

```powershell
pwsh -NoProfile -File .\RomSorter.Tests.ps1
dotnet build .\web\server\RomChecker.Web.csproj
# Build the frontend before API integration tests.
pwsh -NoProfile -File .\web\tests\Api.Tests.ps1
```

From `web/client`:

```sh
npm test
npx playwright install chromium
npm run test:e2e
```

The API and browser suites use synthetic ROM fixtures and disposable storage. They exercise actual engine scanning, review, approved moves, and undo under `/roms/`, not mocked engine results. `ROMCHECKER_DOTNET` can select a non-PATH SDK executable for browser tests; the API script has a `-Dotnet` parameter. Container CI also checks boot, subpath routing, authentication, and the non-root runtime.

## Branches, images, and releases

Development follows:

```text
feature branch -> pull request to beta -> validated integration
beta -> promotion pull request to main -> release PR -> approved stable release
```

- **PR checks:** engine regressions on Ubuntu and Windows PowerShell, API integration, frontend tests/build, real Chromium workflows, and container smoke tests.
- **Push to beta:** rerun checks, then publish `beta`, `<version>-beta.<run number>`, and `sha-<commit>` to GHCR.
- **Push to main:** rerun checks and let Release Please open/update a release PR.
- **Merge the release PR:** create a version tag, GitHub Release, and changelog; publish `<version>`, `latest`, and `sha-<commit>` with OCI version/revision labels, SBOM, and provenance.

The main delivery workflow publishes after Release Please reports release creation in the same run. It does not depend on a second workflow being triggered by a `GITHUB_TOKEN`-created tag.

Use Conventional Commit PR titles and squash merges: `feat:`, `fix:`, `perf:`, `docs:`, `refactor:`, and `chore:`. Mark breaking changes explicitly. Release Please updates `version.txt` and frontend package metadata. Add a reviewed overview, upgrade instructions, known limitations, and migration warnings to release PR notes where relevant; generated commit lists cannot replace editorial review.

Repository-owner setup is still required:

1. Enable GitHub Actions and permit Actions to create pull requests.
2. Grant the delivery workflow package publication permissions; ensure the GHCR package is linked to this repository.
3. Protect `beta` and `main`, require CI, and disallow force pushes.
4. Merge these workflow files into the intended branches. No remote branches, repository policies, or releases are changed merely by adding these files.
5. After each stable release, merge release metadata and any hotfixes back into `beta`.

CI builds linux/amd64 images initially. Publishing is automated; production deployment is deliberately not automated without a defined target, credentials, and rollback policy.

## Original command-line application

The original `RomSorter.ps1`, its regression suite, and Ubuntu/WSL launcher remain available. Run `powershell -File .\RomSorter.ps1` on Windows or `bash RomSorter.sh` on Ubuntu. The web bridge loads engine definitions without starting CLI menus, executes each job in a separate process, and preserves engine safety checks instead of reimplementing ROM analysis in the browser.
