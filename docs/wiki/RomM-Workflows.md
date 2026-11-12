# RomM Workflows

Complete [Connect RomM](Connect-RomM.md) and test a small manual publication first.
All automation is a deliberate opt-in.

## Real-instance pre-release check

On 2026-11-12, a local development build was tested with RomM 5.4.1 on Linux
amd64 using disposable synthetic NES files. The check covered the connection,
manual and automatic imports and publication, ClamAV verification, conflict
handling, and outage recovery. It did not validate real collections, metadata
providers, other RomM versions, or backup restoration.

Before deploying, record the exact ROM Checker image digest and RomM version, then
test on a disposable instance with a small backed-up collection. Use dedicated
export storage, not an existing RomM library, and leave automatic publication and
synchronization disabled initially.

1. Connect using a RomM API token and confirm the configured platform mappings.
2. Import a small collection into ROM Checker, verify it, and review its findings.
   Preview publication, confirm an eligible file, and check that RomM scans it and
   the exact-hash metadata link appears. Confirm an ineligible file is held.
3. Import a selected file from RomM and confirm it arrives as an unchecked local
   import. Verify it separately; do not assume remote metadata proves safety.
4. With disposable copies, create a local/remote content conflict. Confirm it is
   visible and neither copy is automatically overwritten or deleted. Exercise
   the appropriate explicit conflict resolution.
5. Test a RomM outage and recovery. Confirm failures are visible and do not become
   deletion signals; restore the service and retry explicitly.
6. Only after manual workflows succeed, test opt-in synchronization and publication
   rules on the small collection. Disable them again before restoring or deleting
   the disposable environment.

Record failures and sanitized diagnostics without ROM contents, credentials, or
private paths. A successful fixture or this checklist alone does not establish
compatibility with every RomM version or deployment.

## Publication

Select explicit Library files, preview **Publish to RomM…**, review exclusions, and
confirm. Publication copies complete eligible groups into the shared export folder,
requests a RomM scan, and links exact hash/platform evidence to remote metadata.
It does not upload ROMs through an HTTP upload endpoint.

Unchecked, changed, unsafe, incomplete, or otherwise blocked content cannot bypass
publication policy. "Exported / awaiting scan" is not "linked." Review failures
and retry explicitly; metadata providers may not have artwork for every game.
Copies are not remotely renamed or deleted by ROM Checker.

## Automatic publication

In RomM settings, configure reference requirements, consoles, categories, regions,
and named imports. Preview draft rules before saving. All filters must match;
empty selections in a restricted filter are invalid, not permission to publish
everything.

Save settings and explicitly enable automatic publication. Browser Library filters
do not control the scheduler. Current eligibility and physical hashes are checked
again. Failed automatic work requires an explicit retry. Turning automation off
does not remove existing exports.

## Imports and metadata

Manual imports download selected remote files into a new local import. They start
**unchecked**, even if RomM has metadata. Complete file hashes/sizes are required;
scan RomM first if they are missing.

For automatic imports, explicitly select platforms and enable/save the policy.
Metadata refresh is a separate opt-in for existing links. The shared schedule is
1–1440 minutes, default 60. **Run saved synchronization** uses saved settings, not
unsaved browser edits.

Downloads are streamed, linked-game identity is checked, and unchanged exact local
content can be linked instead of fetched again. There is no implicit extraction,
replacement of originals, or deletion propagation.

## Conflicts

Changed local or remote content, paths, platform identity, or missing games/files
can create visible conflicts. A remote outage is an error, not a deletion signal.

- **Keep local copy:** ignore the current remote version without modifying local files.
- **Import remote as separate copy:** explicitly bring the remote version into a
  new unchecked import when applicable, retaining the existing local copy.

Restore matching files, refresh the local catalog, and recheck when appropriate.
Ignored/conflicted content is held from automatic publication to avoid feedback
loops. See the [detailed synchronization reference](https://github.com/Phthisicus/ROM-Checker/blob/development/docs/REFERENCE.md#inbound-discovery-metadata-schedules-and-conflicts)
for restart/retry behavior and edge cases.
