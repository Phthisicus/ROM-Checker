# Updates, Backups, and Recovery

## Back up a consistent set

Stop transfers, processing, and synchronization before taking a filesystem backup.
For the simplest consistent offline backup, stop the relevant services before
copying their persistent data. A live MariaDB directory copy is not a reliable
database backup; use a supported logical dump or stop it first.

| Data | Why retain it |
|---|---|
| `app-data` | SQLite, jobs, findings, and Data Protection keys needed for saved credentials |
| `rom-storage` | Original imports, working copies, partial transfers, metadata, recovery evidence |
| `ROM_LIBRARY` | Advanced server-library files and `_RomSorter` journals |
| Standalone export directory | Inside `rom-storage/romm-library` unless explicitly reconfigured |
| Combined `ROMM_LIBRARY` | Separate shared export bind mount |
| RomM database, resources, assets, config, Redis volumes | Remote identities, metadata, saves, settings, and task/cache state |
| Environment files | Deployment paths and secrets; protect backups accordingly |

Keep the Compose project name and exact image versions/digests with your backup.
Test restoration to a disposable environment. A backup is not established by
successfully downloading a ZIP or copying only the SQLite file.

## Update deliberately

Read release notes and back up first. Preserve the project name and storage paths.
For standalone:

```sh
docker compose pull
docker compose up -d
docker compose ps
```

For combined:

```sh
docker compose --env-file .env.romm -f compose.romm.yml pull
docker compose --env-file .env.romm -f compose.romm.yml up -d
docker compose --env-file .env.romm -f compose.romm.yml ps
```

`development`, `beta`, and `latest` are moving image aliases. Pin a published version
or digest for repeatable deployments. RomM is independently pinned in the combined
example; upgrade it after reviewing compatibility and its own migration guidance.

Settings can optionally check the current ROM Checker image channel for updates;
it never deploys updates. Database schema checks can reject unsupported newer
data, but that is not automatic rollback. Older images may require a matching
pre-upgrade database/storage backup.

## Recovery versus deletion

Use Advanced Recovery to inspect journals and preview supported undo operations.
After interruption, inspect Activity and current files before retrying.
Do not run a second engine or manually change files while work is active.

Explicit import deletion and processed-archive cleanup are permanent. Never use
`docker compose down -v` to restart or update: it destroys named volumes.

Restore matching database, keys, files, and related RomM state together, with
services stopped, then verify permissions and a small workflow before resuming.
