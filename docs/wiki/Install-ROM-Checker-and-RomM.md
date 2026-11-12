# Install ROM Checker + RomM

This example creates a **new stack**: ROM Checker, internal storage, signature
updater, RomM, and MariaDB. It does not migrate an existing RomM installation.
Read [Requirements](Requirements.md) first.

The example pins RomM **5.4.1** and MariaDB **11.4**. RomM's deployment and token
instructions were checked against its 5.4.1 source. This is not a claim of a
completed live end-to-end compatibility test; validate a small backed-up collection
before enabling automation.

## 1. Get both Compose files

```sh
git clone --branch development https://github.com/Phthisicus/ROM-Checker.git
cd ROM-Checker
cp .env.romm.example .env.romm
```

Keep [`compose.yml`](https://github.com/Phthisicus/ROM-Checker/blob/development/compose.yml)
and [`compose.romm.yml`](https://github.com/Phthisicus/ROM-Checker/blob/development/compose.romm.yml)
together: the combined file inherits ROM Checker's services from the standalone
file. Use **only** `-f compose.romm.yml` for this path, not two running stacks.

For a release, obtain both files and the environment example from that same revision.

## 2. Create dedicated directories and secrets

Edit `.env.romm` and replace all required values:

```dotenv
ROM_LIBRARY=/srv/rom-checker/server-library
ROMM_LIBRARY=/srv/rom-checker/romm-export
ROMCHECKER_PASSWORD=<unique password, at least 16 characters>
ROMCHECKER_STORAGE_TOKEN=<independent random secret, at least 32 characters>
ROMM_AUTH_SECRET_KEY=<independent random secret>
ROMM_DB_PASSWORD=<independent random database password>
ROMM_DB_ROOT_PASSWORD=<different random root password>
```

Run `openssl rand -hex 32` separately for each random secret. The RomM API token is
created **after first boot** and saved in ROM Checker's UI, not this file.

For **new empty Linux directories**:

```sh
sudo mkdir -p /srv/rom-checker/server-library /srv/rom-checker/romm-export/roms
sudo chown 10001:10001 /srv/rom-checker/server-library /srv/rom-checker/romm-export /srv/rom-checker/romm-export/roms
sudo chmod 755 /srv/rom-checker/romm-export /srv/rom-checker/romm-export/roms
chmod 600 .env.romm
```

Do not recursively change an existing collection's permissions. Docker Desktop
users should configure shared host folders instead.
Create the empty `roms` subdirectory on every platform before first boot: RomM
cannot bootstrap that directory itself through a read-only library mount.

## 3. Understand the shared library

| Container | Mount | Access |
|---|---|---|
| ROM Checker | `ROMM_LIBRARY` → `/storage/romm-library` | Read/write: eligible exports only |
| RomM | Same directory → `/romm/library` | Read-only: scan, browse, and download |

Never point `ROMM_LIBRARY` at `ROM_LIBRARY`, the whole `rom-storage` volume, or an
existing RomM library without planning a migration. Unchecked originals and staging
must remain private to ROM Checker.

The read-only RomM library deliberately prevents RomM-side uploads, renames, and
deletions in this example. Saves/assets and metadata have separate writable volumes.
If you need an independently writable RomM library, design that deployment
separately rather than removing the safeguard without review.

## 4. Validate and start

Use these options for **every** command in the combined deployment:

```sh
docker compose --env-file .env.romm -f compose.romm.yml config --quiet
docker compose --env-file .env.romm -f compose.romm.yml pull
docker compose --env-file .env.romm -f compose.romm.yml up -d
docker compose --env-file .env.romm -f compose.romm.yml ps
docker compose --env-file .env.romm -f compose.romm.yml logs --tail=100 romm romm-db signature-updater
```

Database initialization and signature downloads can take time.
Do not publish database or storage-service ports.

## 5. Complete RomM setup, then create the token

1. Open `http://localhost:8081` on the Docker host.
2. Complete RomM's setup wizard and create the initial administrator.
3. Configure optional metadata providers if you want artwork and descriptions.
   The environment example exposes Hasheous, IGDB, and SteamGridDB options;
   none is presented as a guarantee of metadata coverage.
4. Follow [Connect RomM](Connect-RomM.md) to create the token, configure
   `http://romm:8080` in ROM Checker, and map platforms.
5. Open ROM Checker at `http://localhost:8080`, verify a small import, and test
   manual publication before enabling automation.

An empty RomM library may have no platforms to map. The connection guide explains
how to seed only the platform folders you need without adding unchecked ROMs.

## Backups and existing installations

Retain ROM Checker's three volumes and server-library directory, the shared export
directory, and RomM's database, resources, assets, configuration, and Redis volumes.
Back up and restore related state together.

Do not switch an existing standalone deployment to this example blindly:
standalone exports live inside `rom-storage`, while this example uses a separate
bind mount. Mounting the bind hides the old export subdirectory rather than moving
it. Stop work, back up, and explicitly migrate/verify exports before switching.

Changing database password variables after initialization does not rotate existing
MariaDB accounts. Follow MariaDB's supported password-change procedure.
See [Updates, Backups, and Recovery](Updates-Backups-and-Recovery.md).
