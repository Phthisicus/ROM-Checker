# ROM Checker

A self-hosted web workspace for verifying and organizing ROM collections, backed by the original ROM Sorter PowerShell engine.

## Web workspace

- Upload-first Collections workspace with console groups, individual/console/whole-collection verification, integrated results, search, filters, and accessible file-detail drawers.
- Responsive dark/light themes, named collections, storage accounting, and recent activity.
- Library search, console/category filters, pagination, per-file evidence, and HTML/CSV/JSON downloads.
- Independent authenticity, integrity, antivirus, and malware findings. No detections never means guaranteed safe.
- Check-only scanning, sort-only inventory, archive unpacking, and unpack-then-check workflows.
- Draft per-file review decisions: keep, mark original, or quarantine. Rebuild the preview to incorporate decisions; security warnings cannot be overridden through the web interface.
- All six sorting layouts, duplicate policies, custom DAT references, verification options, and archive resource limits.
- Automatic organization of eligible collection working copies after explicit **Verify & organize** approval; Expert workspace previews still require explicit Apply. Content/inventory revalidation and journaled recovery keep disc sets and companions together.
- Background jobs with live events, progress, warnings, downloadable logs, and cancellation for non-mutating jobs.
- Journal inspection, undo previews, restoration, and verified processed-archive cleanup.
- Password authentication, persistent SQLite job/settings storage, non-root Docker runtime, and reverse-proxy subpath support.
- Dedicated ROM storage service, resumable bulk folder uploads, read-only SMB imports, per-batch processing choices, and processed-folder ZIP downloads.

This is a **single-administrator application**, not a multi-tenant upload service. You can process the existing mounted library or isolated import batches in a separate storage volume. Optional external verification services receive hashes and metadata, not ROM contents. Browser access does not grant access to arbitrary host folders.

## Run with Docker Compose

Requirements: Docker Engine with Compose, a backed-up ROM folder, and permission for container UID/GID **10001:10001** to read and modify that folder.

1. Copy `.env.example` to `.env`.
2. Set `ROM_LIBRARY` to an absolute host directory. On Docker Desktop, use a shared host folder, for example `C:/ROMs`.
3. Set a unique `ROMCHECKER_PASSWORD` of at least 16 characters and a separate random `ROMCHECKER_STORAGE_TOKEN` of at least 32 characters.
4. Optionally set `ROMCHECKER_SMB_HOSTS` to exact SMB server hostnames/IPs approved for imports.
5. Build locally and start the application, ROM storage service, and ClamAV signature updater:

```sh
docker compose build romchecker
docker compose up -d
```

Open `http://localhost:8080/`. The published port binds to loopback by default. All three services use the same image tag; `docker compose build romchecker` tags that image for every service. `rom-storage` runs only the storage API, not a second processing worker. Its port is not published.

After CI has published the image, use `docker compose pull && docker compose up -d` instead. The `beta` image follows tested integration builds; `latest` follows approved stable releases. For predictable deployments, pin a version or digest with `ROMCHECKER_IMAGE`.

**Check signature readiness:** `docker compose logs signature-updater`. The first download may take time and ClamAV download rate limits may apply. Antivirus checks report incomplete protection if signatures are unavailable; archives are not extracted when an enabled antivirus check cannot complete. Do not disable antivirus merely to bypass a readiness failure.

The `app-data` volume contains SQLite, authentication keys, job logs, and full result snapshots. The `rom-storage` volume contains batch metadata, partial uploads, original imports, and processing copies; it is shared by the app and storage containers. The `signatures` volume is updated by the updater and mounted read-only in the application. Each processing root also receives engine `_RomSorter` checkpoints, reports, and recovery journals. Back up the library, application data, and storage volume. Do not run multiple app/storage replicas or the CLI against these roots simultaneously. Do not use `docker compose down -v` unless you intend to destroy the named volumes.

Deleting processed recovery archives is **permanent**, disables extraction undo for those archives, and always requires a fresh verified preview and confirmation. Test with a disposable collection before granting access to important files.

## Bulk imports and temporary ROM storage

Open **Collections**. Use **Upload ROMs / Choose folder** to create a named collection, or open **Import from network share**, create an empty destination collection, and connect to an approved server. Backend APIs retain the term `batch` for compatibility.

1. **Upload / resume folder:** choose a folder in a Chromium-based browser (Chrome/Edge). Relative folders are retained. Files upload sequentially in chunks of at most **8 MiB**; ROM contents are never buffered as one huge request or ZIP. Progress reports file counts and bytes, and Pause aborts the current request. Reselect the same unchanged folder in the same batch to resume after interruptions/reloads; the server checks relative path, size, and modification time. These identity checks are not a full client-side content hash. Changed files require a new batch. A bounded retry policy handles transient failures; permanent failures stop and are displayed.
2. **SMB:** connect using server, share, optional domain, username, and password. The server must be explicitly listed in `ROMCHECKER_SMB_HOSTS`. Browse folders, select files/folders or all visible items, and import into an **empty** batch. Up to 1000 selected roots can expand recursively, within the batch limits. Imports are copied read-only from SMB; they never delete, rename, or write to the source share. Progress reflects completed imported files; failures retain completed originals and identify the failed batch.

SMB connections are made by the storage container on TCP **445**, not by the browser. Use a dedicated read-only account. Credentials are used only for live in-memory sessions, are never written to batch metadata/browser storage, and are not passed on command lines. Connection IDs alone are kept in browser session storage. Connections do not survive a storage restart; disconnect when finished. At most eight live connections are allowed, and idle connections can be reclaimed after 30 minutes when opening another connection. SMB1 is not used. Use a trusted private network/VPN: do not assume SMB transport encryption or expose this service to the Internet. DFS referral/cluster setups are not supported by this import flow; use the direct server/share.

Folder uploads automatically prepare the processing copy when complete. For SMB or resumed/failed imports, click **Finish import & detect consoles**. Originals become read-only to the application's import API; a separate physical copy is created under that collection's `processed` folder. This requires space for at least originals **plus** working copies, and additional space for extraction/recovery. Storage & retention shows working-copy size, available disk space, and preparation requirements. Large preparation/import operations run on a bounded background transfer queue, not an HTTP request. Prepared collections are sealed: add more ROMs in a new collection.

### Console grouping, verification, and organization

The guided workspace detects consoles locally, without moving files or claiming verification. Ambiguous formats remain under **Unknown / Needs identification**. Headers/content signatures supplement extension/folder hints; supported descriptors/tracks and companions form selection units.

Choose individual files, **Verify selected**, **Verify console**, or **Verify everything**. Selecting one linked member includes the whole supported disc/companion unit, even across pagination. Antivirus can scan the entire working copy, but only selected/related files receive new verification results. Check progress stays in the console list; per-file results are committed when the operation completes.

- **Verify & organize** runs the configured checks, then automatically moves eligible working copies into console folders. This action explicitly approves those moves; it is not an implicit upload side effect.
- **Check only** saves findings without moving ROMs.
- **Custom** exposes check choices. Per-run changes do not overwrite global defaults. Online lookups require acknowledgement of fingerprint/metadata sharing in the verification dialog.

Automatic organization requires a known console, completed local checks, clean security status, no invalid header/internal checksum finding, no conflicting/deferred identity evidence, and an eligible classification. Enabled antivirus and applicable online malware checks must complete. Required reference matches must be present. Without a reference, a supported passing structure/internal check is required when the selected policy permits it. One failed member holds its whole linked unit. BIOS, executables, archives, bad dumps, protected files, and unresolved files are not automatically organized. Duplicate content is reported, not deleted or moved into a duplicates area. Homebrew, translations, hacks, and prototypes can be organized when their evidence passes; they are not automatically treated as malware. Names are not changed, existing destinations are not overwritten, and moves are SHA-256 verified and journaled.

Identity, integrity, local antivirus, online malware checks, and organization outcomes remain separate. File drawers explain console-specific findings for every supported console, including unusual homebrew headers and checks that are unsupported/inconclusive rather than failed. DAT matches, Hasheous matches, and previously unknown files identified use separate counters. Infrastructure failures appear as structured service issues; repeated cache-write errors are aggregated. Online caches are persisted under the application engine data directory.

Use **Expert workspace** for server-library operations, all six layouts, raw results, extraction, move previews, manual review, and recovery. Archive extraction remains an explicitly approved Expert action; packed archives are not automatically expanded by guided verification. Refresh console detection after extraction; legacy file-changing jobs invalidate the guided index so it is rebuilt from current files. Existing collections created before this interface are indexed on opening; previous job reports remain in Activity, while guided verification starts as unchecked until run through the new flow. Rediscovery preserves guided evidence only after fingerprint revalidation.

The selected collection is used by recovery actions; **Use server library instead** returns to the original library. Result-source actions use the snapshot's own batch, and the API rejects cross-batch previews. One engine operation runs at a time across all roots. A persistent collection lease prevents uploads, preparation, downloads, or deletion from racing with processing. App restarts mark jobs interrupted and recover orphaned leases; restarting only storage preserves processing leases. After an interrupted operation, inspect Activity and undo journals, then refresh console detection before retrying.

Download individual current files, organized console folders, or the complete collection as a **streaming ZIP**, including ZIP64 for large outputs. Complete downloads include pending/held files and reports/recovery journals; a console ZIP reflects its current physical folder, not a safety certification. Expert storage browsing provides original/processed trees (200 entries per page). ROM bytes are not collected into memory or a temporary ZIP. Compression is disabled to avoid wasting CPU on already-compressed ROMs. A collection is locked for the duration of a download so processing/deletion cannot change it midway. A failed download must be restarted; ZIP downloads do not support HTTP-range resume.

Defaults: **100,000 files**, **1 TiB original data per batch**, **1 GiB free-space reserve**, **200 retained batches**, and **two simultaneous HTTP transfers** across the storage service. SMB directory listings are bounded to 100,000 entries, paths to 32 levels, and names must be portable across Windows/Linux (no traversal, device names, or links). File contents are streamed; bounded manifests contain metadata only. Limits apply to originals, not a promise about final extraction size; configure archive limits in Settings and monitor disk usage. Disk exhaustion returns an explicit error, retaining originals. Preparation interrupted before completion can be retried; a failed SMB batch can prepare its completed subset or be deleted and re-imported.

**Nothing is automatically deleted, including after a download.** Delete a batch explicitly to permanently remove its originals, processing copies, partial transfers, and recovery journals. Downloading is not proof of a backup. Job history is retained in app data, but deleted batch paths are no longer usable.

The SMB library fetches a directory's metadata before the entry-count check; exceptionally large flat shares can still consume substantial metadata memory. Split those into smaller directories. ROM file contents themselves are always read in bounded blocks.

ZIP exports also cap entry counts at the configured file limit. If extraction or engine reports take an output tree over that limit, download smaller processed subfolders instead.

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

Allow at least **8 MiB** request bodies (the nginx example uses `9m`), disable request buffering for uploads, and allow long upload/download timeouts. No multi-gigabyte request limit is needed: each upload request is bounded. Route all browser transfers through the app's authenticated `/api/storage/...` gateway; never publish the storage service directly or give its token to the browser.

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

Batch storage is optional in standalone local mode. To enable it, run the same server assembly in a second terminal with `ROMCHECKER_ROLE=storage`, `ASPNETCORE_URLS=http://127.0.0.1:5201`, `ROMCHECKER_STORAGE_ROOT` pointing outside the legacy library, and a random `ROMCHECKER_STORAGE_TOKEN`. In the app terminal, leave `ROMCHECKER_ROLE` empty and set the same storage root/token plus `ROMCHECKER_STORAGE_URL=http://127.0.0.1:5201`. Both processes must access the same filesystem path. Set `ROMCHECKER_SMB_HOSTS` in the storage terminal, not the browser.

For hot-reloading the UI, run `npm run dev` from `web/client` in another terminal. Vite forwards `/api` to `127.0.0.1:5200`; use an empty base path for development through Vite. The production build is served by ASP.NET Core, without a separate frontend service.

### Feature modules

Processing features remain components inside one application container. An optional **separate storage container** owns transfers, batch lifecycle, SMB connections, and downloads; it is not an independently concurrent engine worker.

| Layer | Module boundaries |
|---|---|
| React `web/client/src/features` | Authentication, overview, library and review state, jobs, recovery/cleanup, settings |
| Shared UI `web/client/src/components` | Accessible dialogs, evidence badges, empty states, progress cards |
| API `web/server/Features` | Authentication, settings validation, library paths/browsing, jobs, reports/downloads |
| Engine `web/engine/Features` | Collection detection/selective verification/automatic safe organization, verification, organization/review/apply, archives/cleanup, recovery, combined workflows |
| Shared infrastructure | SQLite `Store`, serialized `JobService`, isolated PowerShell `Infrastructure/EngineRunner` |
| Storage `web/server/Features/Storage` | Internal token-authenticated service, upload staging, SMB read-only client, batch preparation/leases, streamed downloads; authenticated app gateway |

`Program.cs` composes endpoint modules and applies authentication, request protection, and reverse-proxy handling centrally. `App.tsx` coordinates navigation and jobs; feature views own presentation, and `library/useLibrary.ts` owns result filters and review drafts. The engine bridge retains common path checks, progress, snapshots, and report generation; handlers reuse the existing CLI analysis engine.

`Features/Jobs/JobActions.cs` explicitly maps each job action to its engine feature and declares confirmation, source-preview, source-settings, and journal requirements. File-changing actions require confirmation and cannot be cancelled by the user. A fixed engine allowlist and action checks select handlers; the browser cannot supply a script or feature path.

There is **one shared engine queue across every feature and batch**. A separate bounded storage transfer queue serializes SMB imports and preparation. Add engine operations to the action registry and appropriate handler, wire their feature UI, and extend API/component coverage. Keep cross-feature flows in `Workflows.ps1` and deployment/proxy configuration shared. Processing leases coordinate the two containers, but this is not a distributed multi-worker scheduler.

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
| `ROMCHECKER_STORAGE_URL` | App only; internal storage URL, empty disables batch storage in standalone mode |
| `ROMCHECKER_ROLE` | `storage` starts only the internal storage service; empty starts the web app |
| `ROMCHECKER_STORAGE_ROOT` | `/storage`; same path/volume in app and storage, outside the legacy library |
| `ROMCHECKER_STORAGE_TOKEN` | Required with storage; separate random secret, at least 32 characters |
| `ROMCHECKER_STORAGE_MAX_BYTES` | Storage only; `1099511627776` original bytes per batch |
| `ROMCHECKER_STORAGE_MAX_FILES` | Storage only; `100000` original files per batch |
| `ROMCHECKER_STORAGE_RESERVE_BYTES` | Storage only; `1073741824` minimum free bytes |
| `ROMCHECKER_SMB_HOSTS` | Comma-separated exact approved SMB hostnames/IPs; empty disables connections. Enforced by storage; also supplied to the app for integration status. |

No keys are exposed through the settings API. Protect the data volume and configuration from other local users. Use the supplied image as a trusted administrative tool: only mount the intended library, never the Docker socket or the host root. Symlink/junction traversal is rejected. Do not allow untrusted processes to alter library paths during file operations.

### Verification

```powershell
pwsh -NoProfile -File .\RomSorter.Tests.ps1
dotnet build .\web\server\RomChecker.Web.csproj
# Build the frontend before API integration tests.
pwsh -NoProfile -File .\web\tests\Api.Tests.ps1
pwsh -NoProfile -File .\web\tests\Storage.Tests.ps1
pwsh -NoProfile -File .\web\tests\CollectionEngine.Tests.ps1
```

From `web/client`:

```sh
npm test
npx playwright install chromium
npm run test:e2e
```

The API and browser suites use synthetic ROM fixtures and disposable storage. They exercise actual engine scanning, review, approved moves, and undo under `/roms/`, not mocked engine results. `ROMCHECKER_DOTNET` can select a non-PATH SDK executable for browser tests; the API script has a `-Dotnet` parameter. Container CI also checks boot, subpath routing, authentication, and the non-root runtime.

The storage suite starts both roles and covers upload offsets/restart recovery, zero-byte and multi-chunk files, limits, batch isolation, selected settings, original preservation, leases, and valid streamed ZIPs. CI supplies a read-only Samba fixture and passes `-SmbServer 127.0.0.1` to also exercise real SMB browsing/import. Without that parameter, SMB connection/import integration is not exercised; the server allowlist rejection is still checked.

The unmodified [SMBLibrary](https://github.com/TalAloni/SMBLibrary) dependency is dynamically linked under LGPL-3.0-or-later; its source and license are available from that project and its NuGet package. It can be replaced by a compatible build independently of this application.

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
