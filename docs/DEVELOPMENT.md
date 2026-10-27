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

Development pushes publish `development-sha-<full commit>` and update the moving `development` alias only if that commit is still the branch head. Images carry a version such as `0.2.0-development.<full commit>`, with matching frontend/runtime identity, SBOM, and provenance. Candidate and published-image smoke checks verify runtime identity. This job has no repository write permission and creates no Git tag, GitHub release, or release assets. Development delivery runs independently of the serialized beta/main release queue. Commit-specific development tags identify source but can be rebuilt on rerun; deploy by digest when immutable bytes are required.

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

Tags are the version ledger. Never repoint or delete them. The pipeline stamps `version.txt`, frontend package metadata, OCI labels, and runtime version/commit variables in the build workspace without committing generated changes. The UI, GitHub release, and exact Docker tag identify the same build.

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
