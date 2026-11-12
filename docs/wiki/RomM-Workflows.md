# RomM Workflows

Complete [Connect RomM](Connect-RomM.md) and test a small manual publication first.
All automation is a deliberate opt-in.

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
