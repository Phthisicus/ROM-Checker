# Documentation

<img src="../assets/brands/logo.webp" alt="ROM Checker logo" width="240">

Use this index to find the project documentation. Keep guidance aligned with the implementation and avoid documenting unverified behavior as a guarantee.

## User and operator documentation

- [README](../README.md): project overview, features, deployment choices, and safety boundaries.
- [User documentation](wiki/Home.md): Wiki sources for installation, workflows, configuration, and troubleshooting.
- [Published Wiki](https://github.com/Phthisicus/ROM-Checker/wiki): user-facing documentation portal.
- [Operational reference](REFERENCE.md): complete advanced workflow, engine, configuration, and deployment details.
- [Development and release guide](DEVELOPMENT.md): branch workflow, CI and release rules, deployment, upgrades, backups, and rollback.
- [Design system](DESIGN_SYSTEM.md): frontend audit, design tokens, shared components, interaction states, accessibility, and incremental adoption rules.

## Project policies

- [Contributing](../CONTRIBUTING.md): development workflow, tests, and pull request expectations.
- [Security policy](../SECURITY.md): private vulnerability reporting and deployment cautions.
- [Code of conduct](../CODE_OF_CONDUCT.md): expectations and private reporting for conduct concerns.

## GitHub repository setup

- [Repository setup recommendations](../.github/REPOSITORY_SETUP.md): suggested repository description and topics, social preview, templates, and manual settings.
- Issue forms are in [`.github/ISSUE_TEMPLATE/`](../.github/ISSUE_TEMPLATE/).
- The pull request template is [`.github/PULL_REQUEST_TEMPLATE.md`](../.github/PULL_REQUEST_TEMPLATE.md).

## Maintaining the Wiki

`docs/wiki/` contains the version-controlled source pages, including `_Sidebar.md`.
Publish those Markdown files at the root of `ROM-Checker.wiki.git`, converting
internal `Page.md` link targets to extensionless `Page` targets for GitHub Wiki.
Source links retain `.md` so they also work when browsing the application repository.
If the Wiki has only been enabled but has no Git repository yet, create its first
Home page in GitHub before cloning it.

Update the source pages with deployment changes, then publish the same revision
to the Wiki. Keep secrets out of both repositories. The Compose files and environment
templates remain at the application repository root; the Wiki links to them rather
than maintaining separate YAML copies.
