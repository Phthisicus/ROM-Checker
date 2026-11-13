# Requirements

## Host and software

- Docker Engine with Docker Compose v2, or Docker Desktop using Linux containers.
  Published ROM Checker images currently target **Linux amd64**.
- Git to clone the deployment files, or download them together from the same
  application revision. Check with `docker version` and `docker compose version`.
- A private machine managed by one administrator. This is not a public upload
  service or a multi-tenant application.
- A Chromium-based browser such as Chrome or Edge for folder uploads.
- Outbound access for image pulls and antivirus signatures. Reference downloads,
  online verification, and RomM metadata providers need their own network access
  when enabled.

There is no established minimum RAM/CPU benchmark. Verification cost depends on
formats, antivirus, and archive size; monitor resource usage with your own files.
The deployment uses one engine worker, not a distributed processing cluster.

## Storage and permissions

Managed imports require capacity for **originals plus working copies**. Extraction,
recovery archives, downloaded metadata, and RomM publication can require more.
The default 1 GiB free-space reserve is not a capacity estimate.

`ROM_LIBRARY` is a separate host folder for Advanced server-library workflows.
It is not the managed upload volume. Use a new dedicated directory if you only
intend to upload through the browser; do not mount your entire home directory.

ROM Checker runs as **UID/GID 10001:10001**. Grant that identity access to the
specific mounted directories; do not use world-writable permissions or change
ownership of an existing collection without reviewing the consequences.
On Docker Desktop, share the chosen host folders and use absolute paths such as
`C:/ROMs-Test`. Linux `chown` examples do not apply directly to Windows.

## Access and backups

Examples expose ROM Checker on `127.0.0.1:8080` and optional RomM on
`127.0.0.1:8081`. The database and internal storage service are not published.
For a remote host, use an SSH tunnel or [HTTPS reverse proxy](Reverse-Proxy-and-HTTPS.md);
`localhost` on your laptop does not refer to that server.

Back up existing files before testing organization or recovery.
Never use `docker compose down -v` as a routine restart: it deletes named volumes.
Keep real passwords and tokens out of Git and restrict access to environment files.
