# Configuration

Use the environment template matching your deployment:

- [`.env.example`](https://github.com/Phthisicus/ROM-Checker/blob/development/.env.example) for standalone.
- [`.env.romm.example`](https://github.com/Phthisicus/ROM-Checker/blob/development/.env.romm.example) for combined.

Never commit populated `.env` or `.env.romm` files.

## Common deployment settings

| Variable | Meaning |
|---|---|
| `ROM_LIBRARY` | Absolute host path mounted as the Advanced server library; not the managed upload volume |
| `ROMCHECKER_PASSWORD` | Required administrator password, at least 16 characters |
| `ROMCHECKER_STORAGE_TOKEN` | Separate app/storage secret, at least 32 characters; keep both services in agreement |
| `ROMCHECKER_IMAGE` | Published channel, exact version, or digest |
| `ROMCHECKER_CHECK_UPDATES` | Opt into manual same-channel GHCR update notifications; default false |
| `ROMCHECKER_SCHEDULED_UPDATES` | Also check about every six hours; requires update checks enabled; default false |
| `ROMCHECKER_UPDATE_USERNAME` / `ROMCHECKER_UPDATE_TOKEN` | Optional server-only GHCR package-read credentials for private packages |
| `ROMCHECKER_PORT` | Host loopback port, default 8080 |
| `ROMCHECKER_SMB_HOSTS` | Comma-separated exact approved SMB hosts; empty disables connections |
| `ROMCHECKER_ALLOWED_HOSTS` | Semicolon-separated permitted web hostnames, retaining `127.0.0.1` for health checks |
| `ROMCHECKER_PATH_BASE` | Empty for a dedicated hostname, or a subpath without trailing slash |
| `ROMCHECKER_TRUSTED_PROXIES` | Exact proxy source IPs as seen by the app; not arbitrary networks |
| `ROMCHECKER_STORAGE_MAX_BYTES` | Original bytes per import, default 1099511627776 |
| `ROMCHECKER_STORAGE_MAX_FILES` | Original files per import, default 100000 |
| `ROMCHECKER_STORAGE_RESERVE_BYTES` | Free-space reserve, default 1073741824 |
| `ROMSORTER_VIRUSTOTAL_KEY` / `ROMSORTER_MALWAREBAZAAR_KEY` | Optional server-side lookup credentials |

Verification defaults are configured in the app. Optional online services receive
fingerprints/metadata, not ROM bytes. Keep service keys server-side.

## Versions and updates

The bottom-left version label opens **Settings > System & updates**. It always
shows the running image's version and channel. Settings includes installed release
notes (available offline), build details, container/process runtime information,
storage paths, and sanitized diagnostics. The runtime information is not a report
of the Docker host.

Checks follow the image's baked channel: `development` checks development builds,
`beta` checks betas, and stable (`main`, image tag `latest`) checks stable releases.
No channel is switched automatically. Checks contact GHCR and its signed blob
download endpoint, not external ROM services, and require outbound HTTPS access.
Disabled checks make no registry requests. A network failure is reported explicitly;
the last successful result, if any, is retained as stale.

Notifications never install software and need no Docker socket. Back up application
data, ROM storage and configuration, read the release's upgrade requirements, then
pull and recreate through your deployment manager. For standalone Compose:

```bash
docker compose pull
docker compose up -d
```

Use the combined-stack flags below when applicable. An exact-version or digest pin
must be edited explicitly before pulling; notification does not change it. Keep
application, storage and signature-updater images aligned. To switch channels,
change `ROMCHECKER_IMAGE` explicitly. Rollback may require restoring a matching
database backup even when the image starts; schema equality is not a safety guarantee.

## Combined-stack settings

| Variable | Meaning |
|---|---|
| `ROMM_LIBRARY` | Existing dedicated shared export directory, writable by ROM Checker |
| `ROMM_IMAGE` | Example default: `rommapp/romm:5.4.1` |
| `ROMM_PORT` | Host loopback port, default 8081 |
| `ROMM_AUTH_SECRET_KEY` | Independent RomM authentication secret |
| `ROMM_DB_PASSWORD` / `ROMM_DB_ROOT_PASSWORD` | Different MariaDB application/root passwords |
| `ROMM_HASHEOUS_API_ENABLED` | Optional metadata provider switch, default false |
| `ROMM_IGDB_CLIENT_ID` / `ROMM_IGDB_CLIENT_SECRET` | Optional IGDB provider credentials |
| `ROMM_STEAMGRIDDB_API_KEY` | Optional artwork provider key |

The RomM API token is saved in ROM Checker's connection UI, not an environment
variable. Provider keys are separate from that token.

## Applying changes

Edit the appropriate file, validate with `docker compose config --quiet`, and
recreate with `docker compose up -d`. Combined deployments must include
`--env-file .env.romm -f compose.romm.yml` in both commands.
Do not paste unredacted `docker compose config` output into support requests:
it can contain resolved secrets.

Changing MariaDB initialization variables is not a password rotation for an
existing database. Likewise, preserve authentication/encryption keys during
restores. The [full environment reference](https://github.com/Phthisicus/ROM-Checker/blob/development/docs/REFERENCE.md#configuration)
documents standalone-process and developer-only settings.
