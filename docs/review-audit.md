# Compare recorded review decisions

Inspect decisions added, changed or explicitly revoked before accepting a revised review. Complete affected source values support release review and automated checks of destructive structure choices; this API does not compare arbitrary table snapshots.

```text
moon run cmd/main -- review-changes BEFORE.json AFTER.json
moon run scripts/audit-demo.mbtx
```

CLI emits deterministic JSON, exits 0 even if either valid review is incomplete, or 2 with no partial report for invalid/mismatched inputs. Save stdout to a new UTF-8 file. Both bundles are validated by rerunning the merge. All original snapshots (including unrelated cells/order), key selection, ordering and both lineages must match exactly. Input revisions require a new review; this command refuses to compare decisions across different sources. Earlier files remain intact on error.

Library: `AFTER.changes_since(BEFORE) -> Array[ReviewChange] raise MergeError`, and `AFTER.changes_report(BEFORE) -> Json raise MergeError`. `ReviewChange` has `target`, `before : Resolution?`, `after : Resolution?`. Absence means no recorded decision; explicit `Value("")` remains distinct. Present resolutions carry choice, conflict kind and complete base/ours/theirs evidence. Dropped structural values and revoked fills remain visible. Returned arrays are independent copies.

Results sort by serialized target with UTF-16 lexical order. Reordering the same decisions produces no changes; reversing the comparison swaps before/after. Complete resolution equality is used, so changed evidence for a retained choice also appears. Coordinates use the output namespace, with original source evidence and declared lineage retained.

JSON format `mntablemerge/review-changes-1` has exactly `format,key,row_order,column_lineage,row_lineage,before_complete,after_complete,changes`. Each change has `target,before,after`; a side is null or `{conflict,choice}`. Conflicts use the existing full schema (target/kind/base/ours/theirs/hint). Completion flags mean plan exportability, not approval/authentication. Unchanged resolutions and pending conflicts are outside this report's defined scope; full bundles retain all snapshots/decisions.

At most 2,000,000 changed resolutions are returned. JSON export is limited to 16,000,000 escaped UTF-16 units; oversized output fails without truncation. The typed API retains complete evidence when only the wire limit is exceeded. There is no report importer/replay patch, authenticated history, reviewer identity, clock, signature or claim of every intervening revision. Keep separate review files for history; use explicit resolve/revise to apply choices.

The offline helper reuses the pinned OurAirports records and existing revision demo's simulated keywords removal. It keeps the column and fills the new record, then drops it and revokes the dependent fill. The comparison verifies both changes, the discarded `simulated audit note` and revoked custom text, then checks complete 18-column output, stale rejection, retry and file preservation. The transformation handles only known single-line fixture rows; production parsing supports arbitrary valid quoted CSV/TSV. Run with `native` on supported Linux/macOS hosts.
