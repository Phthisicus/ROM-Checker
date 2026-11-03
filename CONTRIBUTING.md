# Contributing

Thank you for helping improve ROM Checker. Contributions should preserve the existing safety checks, recovery behavior, and configuration compatibility.

## Before you start

- Search existing issues and pull requests before starting substantial work.
- For behavior changes, describe the user impact and any compatibility or data-safety implications in an issue first.
- Never include ROM files, credentials, private paths, or personal data in issues, pull requests, test fixtures, or logs.
- Do not change application source as part of documentation-only updates.

## Development workflow

1. Create a feature branch from `development`.
2. Keep changes focused and use a Conventional Commit pull request title, such as `fix(storage): preserve interrupted uploads`.
3. Add a uniquely named JSON release note under `.github/release-notes/` for meaningful application or pipeline changes. Follow the examples and allowed types in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md#feature-focused-release-notes). Documentation-only changes do not need an application release note unless they change release or pipeline behavior.
4. Open a pull request targeting `development` and use the repository pull request template.
5. Feature pull requests are squash-merged. Branch promotions from `development` to `beta` and `beta` to `main` use merge commits; contributors should not perform promotions unless they are responsible for the release.

## Tests

Run the checks relevant to your change. The CI workflow is the authoritative full validation; it covers the engine, API, catalog, storage/SMB, RomM protocol fixture, frontend, browser workflows, Windows PowerShell compatibility, and container startup.

Examples from the repository root:

```sh
dotnet build web/server/RomChecker.Web.csproj
dotnet run --project web/tests/Catalog.Tests
dotnet run --project web/tests/Build.Tests
node web/tests/Romm.Tests.mjs
node --test .github/release-tools/release.test.mjs
```

For frontend changes:

```sh
cd web/client
npm ci
npm run build
npm test
```

For PowerShell engine changes, run `./RomSorter.Tests.ps1` and the relevant integration suite from a supported PowerShell environment. The full command list and optional SMB fixture setup are in the [README verification section](README.md#verification).

## Pull requests

Use the existing template. Include:

- The user-visible change and its motivation.
- Relevant tests run and any checks that could not be run.
- Compatibility, configuration, migration, backup, or rollback considerations.
- Screenshots only when they show the actual running application; redact sensitive information.

Do not claim a security guarantee, external integration compatibility, or behavior that has not been verified against the implementation.
