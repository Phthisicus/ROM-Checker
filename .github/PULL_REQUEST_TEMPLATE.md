## Summary

Describe the user-visible outcome and why it matters.

## Release notes

- [ ] Added a new `.github/release-notes/*.json` entry for meaningful application or pipeline changes.
- [ ] Described main features in end-user language, without unverified claims.
- [ ] Included upgrade instructions for breaking changes and known limitations where relevant.

## Verification

Describe the relevant automated checks and any manual verification.

## Promotion

- Feature/fix: target `development`; use a Conventional Commit title.
- Beta promotion: merge `development` into `beta` without squashing.
- Stable promotion: merge `beta` into `main` without squashing.
- Emergency fix: use `hotfix/*` into `main`, then merge it back into `development` and `beta`.

## Compatibility and data safety

Describe configuration, migration, backup, or rollback considerations; write N/A if none.
