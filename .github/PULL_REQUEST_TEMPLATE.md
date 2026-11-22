## Summary

Describe the user-visible outcome and why it matters.

## Release notes

- [ ] Added a new `.github/release-notes/*.json` entry for meaningful application or pipeline changes.
- [ ] Described main features in end-user language, without unverified claims.
- [ ] Included upgrade instructions for breaking changes and known limitations where relevant.

## Verification

Describe the relevant automated checks and any manual verification.

## Promotion

- Feature/fix: target `develop` from `feature/*` or `bugfix/*`.
- Release stabilization: create `release/<version>` from `develop`; merge approved release changes into `main`.
- Emergency fix: use `hotfix/*` from `main`, release it, then integrate the fix back into `develop`.
- Beta, RC, and stable publication are explicit manual/tagged promotions; do not publish from a feature or `develop` branch.

## Compatibility and data safety

Describe configuration, migration, backup, or rollback considerations; write N/A if none.
