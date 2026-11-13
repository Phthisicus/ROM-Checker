# Imports and Storage

## Folder uploads

Use **Add games** in Chrome/Edge to choose a folder. Relative paths are retained;
uploads use bounded chunks rather than one large ZIP request.
To resume, reselect the same unchanged folder in the same import session.
The server checks path, size, and modification time; those checks are not a full
client-side content hash. Changed inputs require a new import.

Preparation makes a separate working copy. Original uploads are protected from
normal verification/organization, but explicit import deletion removes them.
Once prepared, an import is sealed; add more files in a new import session.

## SMB imports

1. Configure exact permitted hostnames/IPs in `ROMCHECKER_SMB_HOSTS` and recreate
   the app/storage services with the saved environment.
2. Open the network-share import UI and create an empty destination import.
3. Connect with a dedicated read-only account, browse, and select files/folders.
4. Wait for the copy, then finish preparation/detection where prompted.

SMB uses TCP 445 from the storage container. It never writes to the source share.
Credentials stay in live in-memory sessions, not saved configuration; connections
do not survive a storage restart. Use a trusted network or VPN, not public SMB.
SMB1 and DFS referral/cluster workflows are not supported by this import flow.

## Capacity and downloads

Defaults allow 100,000 original files and 1 TiB per import, with a 1 GiB free-space
reserve. Originals, working copies, extraction, recovery, and exports all consume
space; these defaults do not guarantee that processing will fit.

Download current files, organized console folders, or a full import as a streaming
ZIP. Full downloads include held files and reports/recovery journals. A console
ZIP reflects a folder, not a safety certification. Failed ZIP downloads must be
restarted; downloading is not proof of a usable backup.

## Deletion and interrupted work

Nothing is automatically deleted after download. Explicitly deleting an import
permanently removes its originals, working copies, partial transfers, and journals.
RomM exports and files downloaded elsewhere are separate copies.

Processing leases prevent conflicting changes. After an interrupted operation,
inspect Activity and recovery evidence before retrying. Do not manually remove a
lease or run the CLI against these roots while the application is processing.
See the [operational reference](https://github.com/Phthisicus/ROM-Checker/blob/development/docs/REFERENCE.md#bulk-imports-and-temporary-rom-storage)
for exact limits and advanced behavior.
