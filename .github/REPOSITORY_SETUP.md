# GitHub repository setup recommendations

These are recommendations for a maintainer to apply in GitHub. Repository settings have not been changed by this documentation update.

## Description

Suggested repository description:

> A self-hosted ROM verification and security platform for validating integrity and reviewing potential malware in gaming collections.

Set this in the repository's About panel. It describes the current web application rather than only the original command-line sorter.

## Topics

Suggested topics:

`rom`, `roms`, `rom-verification`, `game-preservation`, `self-hosted`, `malware-scanning`, `docker`, `powershell`

These describe the documented application and deployment. Add or remove topics to match the project's intended discoverability.

## Social preview

Upload [`assets/brands/social-preview.png`](../assets/brands/social-preview.png) under **Settings > General > Social preview**. It is a 1280 x 640 PNG using the supplied banner, centered on a black background without cropping or stretching the artwork. The social preview is configured in GitHub and is not set automatically by a repository file.

## Brand assets

The official artwork is retained unchanged:

- [`ROM-Checker-Banner.png`](../assets/brands/ROM-Checker-Banner.png)
- [`ROM-Checker-Logo.png`](../assets/brands/ROM-Checker-Logo.png)

GitHub documentation uses optimized derivatives from the same artwork:

- `banner.webp`: 1600 pixels wide, used at the top of the README.
- `logo.webp`: 768 pixels wide, used in the documentation index.
- `social-preview.png`: 1280 x 640, prepared for manual upload.

Use relative image paths in documentation. Preserve the supplied green, black, and silver identity and the tagline **Verify. Protect. Preserve.** Do not stretch, crop, or redraw the official artwork.

## Issue and pull request templates

- Bug reports use `.github/ISSUE_TEMPLATE/bug_report.yml`. Ask for a version and sanitized reproduction steps; do not request ROM uploads or secrets.
- Feature requests use `.github/ISSUE_TEMPLATE/feature_request.yml`.
- `.github/ISSUE_TEMPLATE/config.yml` keeps blank issues enabled alongside the forms.
- The existing `.github/PULL_REQUEST_TEMPLATE.md` captures release notes, verification, branch promotion, and data-safety considerations; retain it.

GitHub reads issue forms and templates from the default branch. The current default branch must receive these files before the forms appear.

## Documentation structure

Keep the README as the project landing page. Use `docs/README.md` as the documentation index and `docs/DEVELOPMENT.md` for contributor and operator details. Add focused guides under `docs/` when they can be kept accurate independently; avoid duplicating configuration values across multiple sources.

## Manual review items

- Review third-party component and asset licenses before publishing a release.
- Apply the suggested description and topics in the repository's About panel.
- Upload `assets/brands/social-preview.png` in repository settings.
- Review the repository's existing visibility and access settings before describing the project as publicly available.
- Enable private vulnerability reporting if desired and available; `SECURITY.md` does not assume that it is enabled.

## Development, Actions, and release settings

Repository files define workflows and least-privilege job permissions; they cannot create or protect branches, configure environments, or change package visibility. Apply and verify these settings manually in GitHub:

- Establish `main` from the exact published `v0.2.0` stable source and `develop` from the current integrated development source. The checked-out legacy branch is named `development`; migrate it only after confirming the remote branch and default-branch state. Do not move or overwrite existing release tags.
- Set `main` as the default branch. Protect both `main` and `develop`; require pull requests, up-to-date `Required checks`, resolved conversations, and block force pushes and deletion. For a solo maintainer, zero required external approvals is sufficient if that is the intended policy. Apply branch protection only after the new workflows exist on both branches.
- Permit GitHub Actions to create pull-request check results and grant package write permission only to build/promotion jobs. The internal build allocator also needs Actions write permission to persist `ROMCHECKER_INTERNAL_BUILD_NUMBER`; it starts from the checked-in seed `31` when that repository variable is absent.
- Grant this repository's Actions workflows write access to the `ghcr.io/phthisicus/rom-checker` package. Anonymous package read access is required for public update checks. Private package reads use only server-side package-read credentials; never add a write token to the application.
- Create the `beta`, `release-candidate`, and `production` Actions environments. Use required reviewers on `production`; add reviewers to beta/RC only if desired. Set the production environment deployment branch/tag policy to approved stable tags.
- Review Actions' default workflow permissions and the package's repository access independently. Do not treat successful workflow-file changes as proof that any setting was applied.

The configured next release target is `.github/release-config.json` (`0.3.0`). Before running a promotion, confirm it matches the intended release cycle. The first new internal build uses build number `32` unless the persistent repository variable is already higher.
