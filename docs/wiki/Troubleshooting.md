# Troubleshooting

For the combined stack, replace `docker compose` in the commands below with
`docker compose --env-file .env.romm -f compose.romm.yml`.

## Start with status and recent logs

```sh
docker compose ps
docker compose logs --tail=100 romchecker rom-storage signature-updater
```

For combined deployments, also inspect `romm` and `romm-db`. Redact paths,
credentials, library contents, and other sensitive details before sharing output.
Avoid sharing resolved Compose configuration: it can contain secrets.

## Common problems

| Symptom | Check |
|---|---|
| Required-variable error | Use the correct environment file and replace every required placeholder |
| Web UI inaccessible | Correct host/loopback port, container status, hostname allowlist, and proxy settings |
| Permission denied | Actual host path, Docker Desktop sharing, and UID/GID 10001 access; do not use `chmod 777` |
| Antivirus incomplete | Signature-updater logs, network access, initial download/rate limits; retry after readiness |
| Insufficient storage | Capacity for originals, working copies, extraction/recovery, and exports, not just upload size |
| SMB unavailable | Exact host allowlist, storage-container TCP 445 access, and read-only account; reconnect after restart |
| Apparent empty Library after redeploy | Compose project name and mounted volumes/paths; do not delete the old volumes |

An infrastructure/service failure is not proof that a ROM is defective. Conversely,
do not disable a required check to make a failed workflow appear successful.

## RomM connection and publication

- **401/403:** token revoked/expired or missing `platforms.read`, `roms.read`, or
  `tasks.run`; check the owner's permissions too.
- **Unreachable:** use `http://romm:8080` in the combined stack, not localhost.
  For external instances, check DNS, TLS, and the final non-redirecting base URL.
- **Missing capability:** inspect the connection-test result and installed RomM
  release. Upgrade deliberately; do not bypass the server-side requirement.
- **No platforms:** seed required empty platform folders and scan RomM, then test
  the connection again. See [Connect RomM](Connect-RomM.md).
- **Exported but not linked:** check the shared mount, platform ID/slug, scan
  outcome, exact hashes, and RomM activity before retrying.
- **Cannot upload/delete in RomM:** the combined example intentionally mounts its
  library read-only. Add/verify/publish through ROM Checker.
- **Inbound import blocked:** scan RomM to populate complete file hashes/sizes;
  review synchronization conflicts rather than replacing local content.

## Diagnostics and reporting

Use **Activity** for the relevant operation and Advanced details when needed.
Settings offers build diagnostics without saved credentials. Include the build,
deployment type, affected operation, and redacted error in a bug report.
Report suspected vulnerabilities privately through the repository's security policy.
