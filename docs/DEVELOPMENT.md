# Development and release guide

## Branch ownership

| Branch | Role | Successful push |
|---|---|---|
| `development` | Integrated feature and fix work | CI and development container; no Git tag or GitHub release |
| `beta` | Preview testing | Versioned container and GitHub prerelease |
| `main` | Production-ready releases | Versioned container and stable GitHub release |

Create feature branches from development. Submit PRs to development using Conventional Commit titles such as `feat(library): add console-scoped verification` or `fix(storage): preserve interrupted uploads`. Squash feature PRs so the reviewed title becomes the commit message.

Promote development to beta, then beta to main, using **merge commits, not squash/rebase**. This preserves ancestry for future promotions, cumulative stable notes, and reliable comparison links. PR checks reject other promotion sources. Emergency fixes can use `hotfix/*` into main with a Conventional Commit title and release note. Immediately merge the fix back into development and beta; do not cherry-pick unrelated development features into main.

The pipeline intentionally does not switch your repository's default branch or change merge settings. Keep merge commits enabled for promotions. Optional squash merging is useful for feature PRs; GitHub's repository-wide default cannot enforce the correct method separately for each branch.

## Required CI

Linux jobs are pinned to `ubuntu-24.04` to avoid automatic `ubuntu-latest` operating-system migrations. JavaScript actions use Node.js 24 runtimes; Trivy's composite action also uses a Node.js 24 cache action. These hosted workflows require a sufficiently recent GitHub Actions runner for Node.js 24; review runner requirements before moving them to self-hosted infrastructure.

The `Required checks` job fails unless every gate succeeds:

- Promotion/title policy, release-note validation, release automation regression tests, and workflow linting.
- Direct/transitive NuGet and lockfile dependency audits, including frontend build/test dependencies.
- Frontend build/TypeScript checks and component tests.
- API, canonical catalog, storage/SMB, RomM protocol fixture, and collection-engine regressions.
- Ubuntu engine regressions and Windows PowerShell compatibility.
- Actual browser workflows, reverse-proxy subpath behavior, and isolated redesigned-library browser coverage.
- Docker build, vulnerability scanning, non-root boot, authentication, and storage integration.

Container readiness probes tolerate transient refused/reset connections for up to 60 seconds. A stopped container fails immediately with startup logs; a running container that never serves a successful health response fails at the deadline. CI tests both storage readiness inside its container and application readiness through the published host port.

Container and dependency scanners block fixable **HIGH/CRITICAL** vulnerabilities; unfixed operating-system/library findings are not blockers in this initial policy. Review scan output instead of treating a passing gate as a guarantee of safety. Do not blanket-disable scanners to release. Any future exception must identify the CVE, justification, owner, and expiry and be reviewed like code. Trivy database/network errors fail the check rather than bypassing it.

No publishing credentials are supplied to PR workflows. Do not change these jobs to `pull_request_target` or execute untrusted PR code with write credentials. Delivery gets publication permissions only after reusable CI succeeds. There is no publishing trigger for feature branches or tags.

Development pushes publish a readable version such as `0.3.0-development.142` plus `development-sha-<full commit>` and update the moving `development` alias only if that commit is still the branch head. The base version comes from the same history-based release planner used by beta/main; the development suffix is the Delivery workflow run number. Images include SBOM and provenance. Candidate and published-image smoke checks verify baked/runtime/frontend identity. This job has no repository write permission and creates no Git tag, GitHub release, or release assets. Development delivery runs independently of the serialized beta/main release queue. A retry reuses an existing exact-version image rather than replacing it; commit-specific tags identify source, not necessarily unique bytes across separate workflow runs. Deploy by digest for exact bytes.

Dependabot targets development with weekly grouped updates. Review dependency changes, add a release-note entry to an application/pipeline update PR, and rerun checks before merging. Dependabot is configured from the default branch once these files reach main.

## Feature-focused release notes

Add a uniquely named JSON file under `.github/release-notes/` to each meaningful feature, fix, or pipeline PR:

```json
{
  "type": "feature",
  "title": "Check a console without interrupting library browsing",
  "description": "Select an individual ROM, a console, a category, or the full library. Verification runs in Activity while results remain visible alongside each file.",
  "upgrade": "Existing files are retained. Run verification to populate new evidence fields.",
  "limitations": "Related tracks and companion files are checked together."
}
```

Allowed types: `feature`, `improvement`, `fix`, `performance`, `security`, `breaking`, `maintenance`. Title and description are required; upgrade/limitations are optional except that breaking changes **must** include upgrade instructions. Entries are append-only and retained for stable-release aggregation; do not delete them after a beta. Avoid secrets, personal data, unverified claims, and raw technical commit titles as feature descriptions.

The release template renders:

1. Clear stable/beta identity.
2. Main feature highlights and user benefits.
3. Improvements, fixes, security changes, and maintenance.
4. Backup, migration, and upgrade guidance.
5. Known limitations.
6. Exact image version, digest, source commit, release assets, and expandable commit history.

Beta notes are incremental against the preceding applicable published ancestor beta/stable release. Main notes include **all** entries since the preceding published stable release, even if they appeared in several betas. Reserved tags and drafts from failed deliveries never remove changes from later release notes. The first release includes all available entries. If a direct push has no editorial entry, notes explicitly say so and include commit history; the pipeline does not invent feature claims.

## Version rules

`version.txt` is the initial release floor. With the current baseline, the first beta is `0.2.0-beta.1`, and the first stable release is `0.2.0`. After a stable tag exists:

| Change since previous stable release | Next release |
|---|---|
| Breaking note, `feat!:`, or `BREAKING CHANGE:` trailer | Next major |
| Feature note or `feat:` commit | Next minor |
| Fixes, performance, documentation, maintenance, or other changes | Next patch |

Breaking changes deliberately advance the major version even before 1.0; this avoids silently breaking preview users. Beta numbers increment within the upcoming release line. For example, after `1.2.0`: feature previews are `1.3.0-beta.1`, `.2`, and `.3`; promotion creates `1.3.0`, not three stable releases. A later fix produces `1.3.1-beta.1` and then `1.3.1`.

Tags are the release-version ledger. Never repoint or delete them. The pipeline stamps `version.txt` and frontend package metadata in the build workspace without committing generated changes. The UI, GitHub release, and exact Docker tag identify the same application version.

## Build identity and compatibility

Each published container includes `/app/build-info.json`: application version, Delivery workflow build number, build attempt, channel (`development`, `beta`, or `stable`), full source SHA, UTC build timestamp, workflow URL, and database schema version. Docker copies the same file into the frontend distribution and compiles the version into its JavaScript. OCI version/revision/created labels and `io.romchecker.*` labels carry the same identity. Build numbers are workflow-local, not global release ordering; attempts identify retries. Reusing an already published image preserves its original build metadata, even when a later attempt performs the publication checks.

The baked file is authoritative. `ROMCHECKER_VERSION` and `ROMCHECKER_COMMIT` remain image defaults for external tooling but cannot override `/api/info`, startup logs, or Settings. Missing/invalid container metadata fails startup; source runs without that file are explicitly `0.0.0-local`, build 0. Unversioned local Docker builds default to the same local identity and cannot pass published-image identity smoke checks.

Settings displays build details and offers an authenticated diagnostic JSON download (`/api/diagnostics/build`) containing only build/schema metadata, not settings, credentials, or ROM data. Startup checks adopt existing unversioned SQLite databases as schema 1 without altering their tables or ROM data. `PRAGMA user_version` is checked before application stores/workers start; newer unsupported schema versions fail with backup/compatible-image guidance and are never reset. Future schema changes must add explicit migrations and advance the supported range and baked schema together. An image predating this guard cannot enforce downgrade protection: back up data before upgrades and restore a matching backup when necessary.

## Channel-aware update notifications

Update checks are disabled by default and never install software. Set `ROMCHECKER_CHECK_UPDATES=true` on the application server, then use **Settings > Check for updates**. There is no background polling. The server reads this package's GHCR `development`, `beta`, or `latest` image metadata for the matching channel and CPU architecture. It compares semantic application versions, not build counters alone, refuses cross-channel results/conflicting identities, and reports a schema warning when the candidate schema differs. A channel alias older than the running image does not trigger a downgrade.

Public package checks need no credentials. For this private package, configure `ROMCHECKER_UPDATE_USERNAME` and a server-only `ROMCHECKER_UPDATE_TOKEN` with package-read access (and required organization authorization, if applicable). These credentials are never sent to the browser or exported in diagnostics. Checks contact `ghcr.io` and its signed `pkg-containers.githubusercontent.com` blob endpoint; no ROM data is sent. Network/authentication/invalid-metadata failures are explicit errors, not an "up to date" result. Deployments without outbound access can leave checks disabled.

## Release transaction and retries

For beta/main:

```text
Required CI
  -> plan and reserve version tag
  -> build candidate (or reuse existing exact-version image)
  -> vulnerability and runtime/version checks
  -> publish immutable image with SBOM/provenance
  -> verify published digest and runtime
  -> assemble release notes and checksummed assets
  -> upload draft release assets, then publish release
  -> update beta/latest alias only for current branch head
```

An immutable tag is reserved **after CI** and before the image build. A failed delivery can therefore leave a reserved Git tag, an image, or a draft release without a published GitHub release. This is intentional: rerunning that delivery reuses the version, checks source labels, reuses the image, and finishes the transaction. Fix source errors in a new commit; the new commit gets a new version. Never overwrite an image with different bytes under an existing version.

An already published release is accepted on retry only if its source commit and image digest match. Published release assets are not replaced. Draft asset uploads are retriable. Channel aliases update from the exact digest, never an unverified local tag. Old-run retries cannot move a channel alias back past a newer branch head or mark an old stable release as latest.

GitHub Actions serializes release deliveries across beta and main. It does not cancel the running delivery, but GitHub retains only the **newest pending run** in a concurrency group. Rapid pushes can therefore be coalesced: the next release contains intervening changes, not necessarily one release per intermediate push. Wait for the current delivery before another release promotion if each must have its own release.

The Actions `release-record-*` artifact retains the plan, notes, digest, and diagnostics for 90 days. The GitHub release permanently includes `release-manifest.json`, `image-digest.txt`, and `SHA256SUMS`; validate downloaded assets with `sha256sum -c SHA256SUMS`. SBOM/provenance attestations are attached to the registry image. This is build provenance, not a separately configured release-signing identity.

Automatic Docker `.dockerbuild` artifact uploads are disabled in CI and delivery to avoid consuming Actions artifact storage on every build. Build summaries and logs remain available; registry images and their SBOM/provenance are unaffected. Explicit browser-failure and release-record uploads still require available Actions artifact storage. If those uploads hit the quota, check the repository owner's Actions storage usage in GitHub billing settings; usage can come from other repositories and storage accounting is not immediate. This repository does not automatically delete existing artifacts.

## GitHub setup and protection

Install the files on all three branches through reviewed promotions. Actions must be enabled; the delivery job requests `contents: write` and `packages: write`. For an existing GHCR package, grant this repository Actions access under the package's settings. No personal access token or deployment SSH secret is required for releases.

Use the following protection on development, beta, and main:

- Require a PR, `Required checks`, up-to-date branches, and resolved conversations.
- Disallow force pushes and branch deletion.
- Enforce protection for administrators.
- For a solo maintainer, require **zero external approvals**, so the owner can merge their own passing PRs. Teams can increase this.

Preview the provided setup:

```powershell
node .\.github\release-tools\protect-branches.mjs
```

Apply it only after the workflows are installed:

```powershell
node .\.github\release-tools\protect-branches.mjs --apply
```

It targets `Phthisicus/ROM-Checker` by default; set `GITHUB_REPOSITORY=owner/repo` to change the target. It refuses to overwrite an existing protection policy. It fails explicitly for unsupported plans or insufficient permissions, potentially after configuring an earlier branch; inspect each branch before retrying.

**Current repository limitation:** GitHub reports that protection/rulesets on this private repository require GitHub Pro (or a plan that supports private-repository protection). The workflows cannot prevent a person from merging failed PRs or pushing directly without platform protection. Publication itself still waits for passing CI. Do not make the repository public merely to work around this limitation.

The default branch's workflow and note files must reach main for normal repository configuration discovery, including Dependabot and the PR template. Release publishing begins when these workflows are pushed to beta/main; merely adding them locally creates no releases.

## Deploying and rolling back

Publishing does **not** automatically update a running installation. No production host or deployment credentials have been configured. Use an exact immutable tag or digest for repeatable deployment:

```dotenv
ROMCHECKER_IMAGE=ghcr.io/phthisicus/rom-checker:1.3.0
# Or: ghcr.io/phthisicus/rom-checker@sha256:<digest from release>
```

Back up application data, ROM storage, and configuration, and ensure imports/processing are idle. Then:

```powershell
docker compose pull
docker compose up -d --no-build
docker compose ps
```

Use the same image reference for all Compose services. Check health and the application version before resuming imports. For rollback, select the previous exact version and restore a matching data backup if a migration is not backward compatible. Do not run `docker compose down -v`; it deletes persistent data. `beta` and `latest` are convenient moving aliases, not immutable rollback references.

Images initially target Linux amd64. Architecture expansion and unattended server rollout require their own tested deployment policy.

## Local release validation

```powershell
node --test .\.github\release-tools\release.test.mjs
node .\.github\release-tools\release.mjs validate
docker run --rm --mount "type=bind,source=$($PWD.Path),target=/repo,readonly" -w /repo rhysd/actionlint:1.7.7 -color
```

Tests use disposable git histories to verify SemVer, beta/stable promotion, cumulative notes, append-only note policy, and deterministic retries. They do not create real releases, push tags, or publish packages.
