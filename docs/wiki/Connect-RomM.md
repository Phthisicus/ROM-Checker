# Connect RomM

You create an **API token**, not an API server. RomM must be running and its first
administrator setup must be complete before ROM Checker can authenticate.

These token labels and API permissions were checked against **RomM 5.4.1 source**.
Other releases can differ. The ROM Checker connection test checks the installed
server's capabilities; source review does not replace a small live publication test.

## 1. Create a dedicated API token in RomM

1. Sign in to RomM as an administrator.
2. Open **Settings**, then **Client API Tokens**.
3. Choose **Create new API token**.
4. Name it `ROM Checker` so its purpose is recognizable.
5. Choose an expiration that fits your maintenance policy. Record when it must be
   renewed; an expired or revoked token stops integration operations.
6. Select these permissions:

   | Scope | Purpose |
   |---|---|
   | `platforms.read` | List platforms and map consoles |
   | `roms.read` | Read game metadata/hash evidence and download files for inbound imports |
   | `tasks.run` | Request RomM library scans after publication |

7. Create the token, choose **Copy token**, and copy its raw value immediately.
   RomM warns that it will not show the value again. Device pairing is not needed.
8. Store it privately until you save it in ROM Checker. Do not paste it into an
   issue, screenshot, environment example, or Git commit.

Do not select every scope. `roms.write`, user administration, and remote deletion
permissions are not required for this integration. The token can only select scopes
its owner has; if using a dedicated integration account, ensure that account has the
three required permissions. Revoking/regenerating a token invalidates the old value.

## 2. Save and test the connection in ROM Checker

1. Sign in to ROM Checker.
2. Open **Settings → Connections → Open RomM settings**.
3. Enter the RomM **base URL**:

   | Deployment | URL |
   |---|---|
   | Supplied combined stack | `http://romm:8080` |
   | Existing instance elsewhere | Its final reachable base URL, preferably HTTPS |

4. Paste the token into **API token**, without a `Bearer ` prefix.
5. Choose **Save RomM settings**, then **Test saved connection**.
6. Resolve authentication, connectivity, or capability errors before publishing.

`localhost:8081` inside ROM Checker's container points to ROM Checker itself,
not the RomM container. Do not append `/api` to the base URL. Redirects are not
followed; use the final URL. For a separate instance, both applications still need
access to the same exported files; API connectivity alone is insufficient.

The saved credential is protected with ROM Checker's persisted Data Protection
keys and is not returned by the settings API. Back up `app-data` with the database.
Leaving the token field blank preserves the saved value.

## 3. Ensure platforms exist and configure mappings

The connection test returns RomM's platform list. Map each local console key
(for example `NES`) to the correct RomM platform and its filesystem slug.
Console keys and filesystem slugs are not necessarily identical.

For a brand-new empty combined stack, first create the required empty platform
folders in the **dedicated export directory**, then run a scan in RomM.
For example, after checking that `nes` is the appropriate filesystem slug:

```sh
sudo -u '#10001' mkdir -p /srv/rom-checker/romm-export/roms/nes
```

Use the path configured in `ROMM_LIBRARY` if different. This Linux example requires
the permissions established during installation; use the equivalent host file
operation on Docker Desktop. Do not copy unchecked games into these folders.

After RomM's scan, test the saved connection again, choose the discovered platform
in **Platform mappings**, and save. Repeat only for consoles you intend to use.
Never guess numeric platform IDs. Review the
[RomM folder structure guide](https://docs.romm.app/latest/Getting-Started/Folder-Structure/)
for other slugs and layouts.

## 4. Test one manual publication

1. Import a small backed-up collection into ROM Checker.
2. Run verification and inspect any publication blocks.
3. Select an eligible game in Library and choose **Publish to RomM…**.
4. Review eligible/excluded files and confirm.
5. Follow RomM activity until the export is scanned and linked.
6. Confirm the game is visible in RomM; check metadata/artwork if providers are configured.

An export awaiting a scan is not yet a completed metadata link. Required checks,
platform/hash mismatches, missing mounts, and incomplete linked groups can block
publication. Never disable checks just to make this test pass.

Only then consider [automatic publishing or inbound synchronization](RomM-Workflows.md).

## Verification sources

The instructions use RomM 5.4.1's
[production deployment example](https://github.com/rommapp/romm/blob/5.4.1/examples/docker-compose.example.yml),
[token dialog](https://github.com/rommapp/romm/blob/5.4.1/frontend/src/v2/components/Settings/CreateClientTokenDialog.vue),
[token labels](https://github.com/rommapp/romm/blob/5.4.1/frontend/src/locales/en_US/settings.json),
[scan endpoint](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/tasks.py),
and [file endpoints](https://github.com/rommapp/romm/blob/5.4.1/backend/endpoints/roms/files.py).
