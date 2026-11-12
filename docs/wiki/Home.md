# ROM Checker documentation

ROM Checker identifies, verifies, and organizes ROM collections on your own
infrastructure. It keeps reference identity, integrity, and security findings
separate, and can publish eligible working copies to RomM.

## Install

Start with [Requirements](Requirements.md), then choose one path:

| Deployment | Start here |
|---|---|
| ROM Checker alone, or with an existing RomM instance | [Install ROM Checker](Install-ROM-Checker.md) |
| A new ROM Checker and RomM deployment together | [Install ROM Checker + RomM](Install-ROM-Checker-and-RomM.md) |

Connecting either deployment to RomM requires an API token created after RomM's
first-run setup. Follow [Connect RomM](Connect-RomM.md) before publishing.

## Use

- [Getting Started](Getting-Started.md)
- [Imports and Storage](Imports-and-Storage.md)
- [Verification and Organization](Verification-and-Organization.md)
- [RomM Workflows](RomM-Workflows.md)

## Administer

- [Configuration](Configuration.md)
- [Reverse Proxy and HTTPS](Reverse-Proxy-and-HTTPS.md)
- [Updates, Backups, and Recovery](Updates-Backups-and-Recovery.md)
- [Troubleshooting](Troubleshooting.md)

The [project README](https://github.com/Phthisicus/ROM-Checker#readme) introduces
features. Contributor architecture, testing, release policy, and the design system
remain in the [repository documentation](https://github.com/Phthisicus/ROM-Checker/tree/development/docs).
Wiki source pages are maintained in `docs/wiki/`.
