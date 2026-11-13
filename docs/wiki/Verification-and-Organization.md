# Verification and Organization

## Read findings independently

| Finding | What it describes |
|---|---|
| Reference identity | Evidence of a match, missing reference, modification, or conflict |
| Integrity | Supported structure/header/internal checksum checks; some formats are inconclusive |
| Antivirus | Whether the enabled local antivirus completed and what it found |
| Online malware checks | Optional fingerprint-based service results |
| Organization / publication | Whether the current file and its linked group meet the applicable policy |

A DAT match is not antivirus clearance. An unsupported check is not automatically
a failure. No detections never guarantees safety.

## Choose the operation

- **Check only:** save findings without moving ROMs.
- **Verify & organize:** explicitly authorize organization of eligible working
  copies after checks. It is not an implicit upload effect.
- **Advanced move previews:** inspect planned changes and explicitly Apply.
  Review decisions require a rebuilt preview to take effect.

One engine operation runs at a time. Supported linked tracks and companions are
handled together; a blocked member holds its group. Files are not automatically
repaired, renamed, overwritten, or deleted to resolve findings.
Exact duplicates are reported rather than automatically removed.

## Held files and approvals

Review the file drawer for incomplete checks, unresolved identity, suspicious
content, integrity problems, missing companions, and service errors.
Infrastructure errors are not evidence that a ROM is defective, but they must not
be treated as completed clean checks.

Where allowed, an explicit manual approval requires an explanation and is bound
to the file's SHA-256. It acknowledges reviewable reference/modification findings;
it does not certify safety or override security blocks, required incomplete
protection, identity conflicts, or missing dependencies. Approval alone does not
move a file. Changed bytes invalidate the previous approval/eligibility.

## Recovery

Organization uses content checks and journals. Inspect Recovery in Advanced mode
for supported undo previews and restoration; do not assume every deletion is
reversible. Processed-archive cleanup is permanent and disables that archive's
extraction undo.

For detailed eligibility rules and engine options, use the
[operational reference](https://github.com/Phthisicus/ROM-Checker/blob/development/docs/REFERENCE.md#console-grouping-verification-and-organization).
