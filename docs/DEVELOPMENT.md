# Development and release guide

ROM Checker uses `main` for stable production source and `develop` for integration. Beta and RC are temporary promotions of immutable images, not permanent branches. Release target configuration is explicit in `.github/release-config.json`; update it through a reviewed change rather than deriving a version from a branch.

## Branch workflow

| Branch | Create from | Use |
|---|---|---|
| `main` | Existing stable source | Stable production and hotfix integration |
| `develop` | Current integrated development source | Feature/fix integration and automatic internal images |
| `feature/<description>` | `develop` | New functionality |
| `bugfix/<description>` | `develop` | Development fixes |
| `release/<version>` | `develop` | Release stabilization and RC source |
| `hotfix/<description>` | `main` | Production emergencies |

Never edit `main` or `develop` directly. Create focused branches with descriptive names, run relevant tests, and submit a PR using `.github/PULL_REQUEST_TEMPLATE.md`. Feature and bugfix PRs target `develop`; merge after `Required checks` succeeds. Merge an approved `release/*` branch into `main` only after RC validation. A hotfix starts at `main`, is released as a patch, then is merged back into `develop`. Delete temporary branches only after successful integration and explicit authorization.

### Using Copilot

Before asking Copilot to change code, check the current branch and worktree. A new local Copilot Chat does **not** create or select a Git branch: it edits the checked-out branch. Create the appropriate branch yourself, or authorize the agent to create it from the correct base. GitHub Copilot Coding Agent works in a GitHub-managed branch/worktree and usually submits a PR; still confirm its base and actual branch rather than assuming it is the same context as a local chat. Repository-specific rules are in `.github/copilot-instructions.md`.

### Migration from `development`

The legacy integration branch is named `development`, and older deployments may report `0.2.0-development.31`. This implementation does not rename remote branches, change the default branch, publish packages, or move tags. Before enabling new delivery:

1. Confirm the remote `v0.2.0` stable tag/release and preserve its source and GHCR tags; do not overwrite or recreate them.
2. Create `main` from the exact published stable source and `develop` from the existing integrated `development` source. If repository settings support renaming safely, review default-branch, PR, ruleset, and Actions references first. Keep legacy branches until the transition has been verified.
3. Set `main` as the default branch, install these workflow files on both permanent branches, and configure their protection before accepting PRs.
4. Keep `.github/release-config.json` at the explicitly confirmed target `0.3.0`. `internalBuildSeed: 31` makes the first new build `0.3.0-internal.32+<short-sha>`; the repository variable `ROMCHECKER_INTERNAL_BUILD_NUMBER` then persists and increments the counter. If an existing value is higher than 31, the next build uses that value plus one.
5. Leave old stable, `beta`, and `development` image tags intact. New workflows publish only new versioned tags and channel aliases. No migration step publishes beta or stable.

## CI and release notes

`ci.yml` runs the application, engine, dependency, security, browser, container, and workflow checks. `feature-build.yml` runs CI for feature/bugfix pushes without publishing beta/stable images. PR validation builds a disposable container and never has package-write permission. `integration-build.yml` runs full CI, builds the application, stamps a single baked build identity, publishes an immutable GHCR tag with SBOM/provenance, records its digest, and updates the internal channel manifest only for `develop`.

Add a uniquely named `.github/release-notes/*.json` entry for meaningful application or pipeline changes. Entries are append-only. Use an end-user benefit, factual limitations, and explicit upgrade instructions for breaking changes. The release-note validator checks note structure and references. Run:

```sh
node --test .github/release-tools/semver.test.mjs .github/release-tools/release.test.mjs
node .github/release-tools/release.mjs validate
dotnet build web/server/RomChecker.Web.csproj
dotnet run --project web/tests/Build.Tests
cd web/client && npm ci && npm run build && npm test
```

The full CI workflow is authoritative and also covers API, catalog, storage/SMB, RomM protocol, PowerShell and browser integration tests. Container and dependency scanners block fixable HIGH/CRITICAL findings; a clean scan is not a guarantee of safety. Never grant write credentials to untrusted PR code or switch to `pull_request_target`.

## SemVer and Docker tags

`.github/release-tools/semver.mjs` validates SemVer 2.0.0, compares prerelease identifiers correctly, and converts versions to Docker-safe tags. `.github/release-config.json` contains the next stable release target and the one-time internal counter seed.

| Image purpose | Application/channel version | Docker tag |
|---|---|---|
| Internal build 32 | `0.3.0-internal.32+d45e67f` | `0.3.0-internal.32-d45e67f` |
| Beta promotion 1 | `0.3.0-beta.1` | `0.3.0-beta.1` |
| Release candidate 1 | `0.3.0-rc.1` | `0.3.0-rc.1` |
| Stable | `0.3.0` | `0.3.0` |

Internal build numbers are stored in the repository Actions variable `ROMCHECKER_INTERNAL_BUILD_NUMBER`; workflow concurrency serializes allocation. Gaps after failed builds are expected; numbers must not be reset. Beta and RC counters advance independently per configured target by checking existing release records. All versioned image tags are immutable. `internal`, `beta`, `latest`, and channel-manifest aliases are conveniences only; pin an exact version or digest for repeatable deployment.

The image's **build identity** is immutable. It always reports the SemVer, commit, build number, build timestamp, and workflow URL baked at build time. A promotion adds a separate **channel identity** (for example `0.3.0-beta.1`) to release metadata and never pretends that the image was rebuilt as a beta. Frontend/backend version reporting identifies the immutable build and the selected update channel separately.

## Internal testing

After a successful merge to `develop`, pull a specific image by the exact Docker-compatible version emitted in the `Integration build` summary. Internal test environments must use a separate Compose project, env file, host ROM folder, port, and named volumes from production:

```sh
cp .env.example .env.internal
# Edit .env.internal: use an isolated ROM_LIBRARY, a unique password/token,
# ROMCHECKER_PORT=18080, and ROMCHECKER_IMAGE with the exact internal tag.
ROMCHECKER_UPDATE_CHANNEL=internal
docker compose --env-file .env.internal -p romchecker-internal pull
docker compose --env-file .env.internal -p romchecker-internal up -d --no-build
docker compose --env-file .env.internal -p romchecker-internal ps
```

The project name creates separate `app-data`, `rom-storage`, and `signatures` volumes. Never use a production `.env`, ROM library, named volumes, ports, credentials, or a mutable `internal` alias for a controlled test. Stop the test stack with `docker compose --env-file .env.internal -p romchecker-internal down` (without `-v` if test data should be retained). Compare the app version, source commit, build number, and image digest to the workflow summary before testing.

## Beta promotion

Beta publication is **manual only** via **Actions > Beta promotion > Run workflow**. Select an immutable internal Docker tag (not `internal`), confirm the configured target `0.3.0`, and optionally enter release notes. The workflow verifies the source image identity, that the commit is in `develop`, and that its required CI check succeeded. It determines the next `beta.N`, promotes the selected digest without rebuilding, verifies the digest before/after, writes immutable and moving channel manifests, and publishes a prerelease record with image digest and source commit. A beta release never publishes `latest`.

The beta environment can require a reviewer. Duplicate versions and conflicting image tags fail closed. If a run fails after publishing artifacts, inspect the run summary, registry tags, and GitHub release before retrying; do not manually repoint immutable tags.

## Release candidates and stable releases

1. Create `release/<version>` from `develop`; freeze feature work. CI and integration builds run on release-branch commits, but they do not move the internal channel alias.
2. Fix release-blocking issues on focused branches into the release branch. Dispatch **Release candidate** from that release branch, select its exact immutable internal image tag, confirm the configured target, and provide notes. The workflow requires that the image source SHA is exactly the release branch head and that CI passed.
3. Each manual run publishes the next `0.3.0-rc.N` release, manifest, and source/digest record using the existing image digest. Test the exact RC image in an isolated environment; repeat after release-blocking fixes. Do not merge new features into the release branch.
4. After approval, merge the release branch into `main`, merge the approved release history back into `develop`, and create the stable Git tag `v0.3.0` on the approved `main` commit. The tag starts `release.yml`; the `production` environment should require manual approval.
5. The stable workflow verifies the tag, configured target, main ancestry, and latest matching RC manifest. It promotes exactly that RC digest to `0.3.0` and `latest`, verifies the digest, publishes the stable channel manifest, and creates a GitHub release with traceability assets. It never builds a new app image.
6. After release, update `nextRelease` in `.github/release-config.json` to the explicitly selected next target in a reviewed PR. Do not infer the target from `main`, `develop`, or SemVer precedence alone.

An RC is a release-candidate channel, not an update-check channel. The supported application update channels are `stable`, `beta`, and `internal`.

## Hotfixes

Create `hotfix/<description>` from `main`; implement only the production fix and test it. Open a PR into `main`, include a release note, and merge after CI. For the emergency release, build the hotfix head and dispatch **Release candidate** from that hotfix branch; it is the explicit RC exception to the usual `release/*` flow. The corresponding stable release still requires an approved RC/digest; never publish from an arbitrary main push. Merge the hotfix into `develop` so it is not lost from future work. Do not cherry-pick unrelated development features into production.

## Update checks and deployment

The application reads channel manifests from GHCR using an anonymous pull token for public packages or optional server-only package-read credentials for private packages. Stable users do not need a GitHub login. Manifests carry channel version, immutable build version, image tag/repository, verified digest, commit, build number, schema version, publication time, and release-notes URL. The manifest package must allow anonymous reads for public updates; the app never receives a write token.

Set `ROMCHECKER_CHECK_UPDATES=true` to enable manual checks; add `ROMCHECKER_SCHEDULED_UPDATES=true` for scheduled checks. `ROMCHECKER_UPDATE_CHECK_INTERVAL_HOURS` configures the interval from 1–168 hours (default 6). `ROMCHECKER_UPDATE_CHANNEL` selects `stable`, `beta`, or `internal`; set it to match the image channel when deploying a promoted build. Requests are cached and limited to once per minute, scheduled checks are jittered, and network failures retain an explicitly stale last success. The UI can link to version-specific release notes. Update checks **only notify**: they do not pull images, access a Docker socket, restart, or replace a container.

Deploy an exact tag or digest through Compose:

```sh
docker compose pull
docker compose up -d --no-build
docker compose ps
```

Use the same image reference for the application, storage service, and signature updater. Back up application data, ROM storage, and configuration first. A changed channel or tag does not change a running container; a new Compose deployment is a separate operator action. Rollback may require restoring a matching database backup. Never run `docker compose down -v` on production data.

## Repository configuration and access

These settings are manual GitHub administration; workflow files cannot apply them:

- Protect `main` and `develop`; require PRs and up-to-date `Required checks`; block force pushes and deletion. For a solo maintainer, zero required outside approvals is reasonable.
- Limit Actions default permissions. CI and feature builds need read-only access; internal builds need `packages: write` and `actions: write` for the persistent counter; promotions need `packages: write` and `contents: write`.
- Grant the repository Actions access to the GHCR package. Allow public reads if stable update checks should be unauthenticated.
- Create `beta`, `release-candidate`, and `production` environments; configure manual reviewers for production and restrict stable deployments to release tags.
- Confirm workflow check names, Actions enablement, GHCR visibility, and permissions in GitHub; do not assume repository files changed the settings.

The preflight helper in `.github/release-tools/protect-branches.mjs` can inspect/apply baseline protection one branch at a time. Review its output and ensure recovery access first; this repository task does not modify remote settings.

## Troubleshooting

| Symptom | Safe response |
|---|---|
| `Required checks` failed | Inspect the failing job, reproduce its targeted test, fix through a PR, and wait for fresh checks. Do not bypass protection. |
| Internal image tag already exists | Compare its labels and digest with the run's source SHA. Never overwrite it; allocate a new build through a new integration commit/run. |
| Counter API or workflow permission failed | Check Actions `actions: write` permission and the repository variable. Never reset a higher stored counter to the seed. |
| Beta/RC promotion failed after tagging | Inspect the immutable image/manifest tags and GitHub release assets. Verify source SHA and digest; if artifacts conflict, stop and reconcile manually. |
| Stable release rejected | Verify tag SemVer, configured `nextRelease`, tag ancestry from `main`, and a published matching RC. Do not create a replacement tag over an existing tag. |
| Update check returns an error | Check opt-in settings, selected channel, package visibility/read permission, outbound HTTPS to GHCR, and server logs. An error is not an "up to date" result. |
| Internal deployment appears empty | Confirm the distinct Compose project name, env file, host folder, port, and exact image tag. Do not attach production volumes to test builds. |

## Practical release checklist

- [ ] Confirm `.github/release-config.json` target and persistent internal build counter.
- [ ] Merge only reviewed PRs; required CI and release-note validation are green.
- [ ] Test an exact internal digest in an isolated Compose project.
- [ ] Manually promote an approved internal build to beta; verify its digest and notes.
- [ ] Create/freeze the release branch; publish and test an RC from its exact head.
- [ ] Approve the candidate; merge to `main` and synchronize release changes to `develop`.
- [ ] Create the stable tag only with explicit authorization; approve the production environment.
- [ ] Verify the stable release manifest, GitHub notes, GHCR digest, and update channel.
- [ ] Set the next release target explicitly and document any follow-up migration/configuration.
