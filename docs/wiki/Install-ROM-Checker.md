# Install ROM Checker

This installs the application, its internal storage service, and the ClamAV
signature updater. RomM is optional. Read [Requirements](Requirements.md) first.

## 1. Get the deployment files

For the documentation and examples on the integration branch:

```sh
git clone --branch development https://github.com/Phthisicus/ROM-Checker.git
cd ROM-Checker
cp .env.example .env
```

For a released deployment, use the matching release checkout instead. The examples
default to the `beta` image; select a published version or digest in
`ROMCHECKER_IMAGE` when reproducibility matters. Source availability on development
does not imply the same features have reached a beta/stable image.

## 2. Configure storage and credentials

Edit `.env`:

```dotenv
ROM_LIBRARY=/srv/rom-checker/server-library
ROMCHECKER_PASSWORD=<unique password of at least 16 characters>
ROMCHECKER_STORAGE_TOKEN=<separate random secret of at least 32 characters>
ROMCHECKER_IMAGE=ghcr.io/phthisicus/rom-checker:beta
```

Replace the placeholders; do not use them as credentials. Generate an independent
storage secret with `openssl rand -hex 32`.

For a **new empty Linux deployment directory**:

```sh
sudo mkdir -p /srv/rom-checker/server-library
sudo chown 10001:10001 /srv/rom-checker/server-library
chmod 600 .env
```

For an existing folder, review permissions and backups before granting access.
Advanced server-library operations can modify this folder after approval.
For network-share imports, set `ROMCHECKER_SMB_HOSTS` to exact approved server
names or IPs, separated by commas.

## 3. Pull and start

```sh
docker compose pull
docker compose up -d
docker compose ps
docker compose logs --tail=100 signature-updater
```

Use the published images for normal installation. Building from source is a
separate developer workflow. If a GHCR pull requires authentication, use an account
with package access and `docker login ghcr.io`; never put registry tokens in Compose.

The first ClamAV signature download may take time or encounter upstream rate
limits. Do not treat the web UI being available as antivirus readiness.
Unavailable signatures produce incomplete protection, not a clean result.

## 4. Sign in and import

Open `http://localhost:8080` on the Docker host. Sign in with
`ROMCHECKER_PASSWORD`; there is no separate ROM Checker username.

Open **Add games**, upload a small backed-up folder, then inspect it in **Library**.
Continue with [Getting Started](Getting-Started.md).
For an existing RomM deployment, follow [Connect RomM](Connect-RomM.md) and arrange
a dedicated shared export folder before publication.

## Persistent data

| Location | Contents |
|---|---|
| `app-data` volume | SQLite, authentication/encryption keys, job logs, snapshots |
| `rom-storage` volume | Import metadata, partial transfers, originals, working copies; standalone RomM exports under `romm-library/` |
| `signatures` volume | ClamAV signatures |
| `ROM_LIBRARY` bind mount | Advanced server-library files and engine recovery evidence |

Compose prefixes named volumes with its project name. Keep the same project
directory/name when updating; changing it can create an apparently empty deployment.
See [Updates, Backups, and Recovery](Updates-Backups-and-Recovery.md).
