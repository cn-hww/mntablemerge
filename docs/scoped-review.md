# Explicit review assignments

Returned bundles from separate assignments can now be [combined](collaborative-review.md) against their shared baseline, with explicit rejection of disagreement and changes to inherited decisions.

Assign a list of current conflict coordinates to an owner, export a smaller sheet, then apply it using the same independently supplied list. Unassigned conflicts remain pending. This avoids manually copying decision JSON or removing rows from a full review sheet; no wildcard, fuzzy match or automatic choice is involved.

```text
moon run cmd/main -- review-sheet-for DRAFT.json TARGETS.json
moon run cmd/main -- review-apply-sheet-for DRAFT.json TARGETS.json EDITED.tsv
moon run scripts/scope-demo.mbtx
```

Write stdout to new UTF-8 files and edit only choice/value as in [full sheets](review-sheet.md). `TARGETS.json` is an exact array, for example `[{"row":["6524"],"column":"review_owner"}]`. Column and whole-row targets use `{"column":"name"}` and `{"row":["key"]}`. Keys are arrays, including compound keys. All coordinates use the merge's output namespace. Duplicate, unknown, already resolved and structurally hidden targets fail. Resolve structure first, then export another assignment for newly exposed cells.

Library: `parse_review_targets`, `MergePlan::review_sheet_for(targets)` and `MergePlan::apply_review_sheet_for(targets, sheet)`. The selected evidence follows original conflict order, independent of assignment-list ordering. An empty assignment is an explicit no-op; it cannot silently replace a nonempty assignment. Application retains all previous decisions, applies only assigned pending targets, and returns a new plan. Coverage, evidence and choice guards are identical to full sheets. Failures leave earlier plans/files intact.

Scoped sheets use `mntablemerge/sheet-2`, with the same eight headers. Their first record binds the complete original bundle in `base` and the canonical coordinate list in `value`. Keep this record first and unchanged. Full sheets retain their existing `sheet-1` output/contract. Full application rejects scoped sheets; scoped application independently recomputes the expected assignment. It rejects stale input or decisions even outside the assigned targets. Bindings are revision guards, not authentication/access control; every recipient still receives the complete original snapshots, so assignments are not data redaction.

At most 99,999 assigned conflicts fit the record limit; full snapshots and evidence remain subject to the table/bundle character limits. Small assignments can fit when full evidence exceeds the sheet row limit, but cannot bypass an oversized original bundle. No assigned source evidence is truncated. Scope documents use strict JSON (duplicate keys/unknown fields/invalid Unicode/depth/16-million-unit limits apply); programmatic coordinates require nonempty names and 1–512 nonempty key components. CLI export/apply exit 0 for a valid result even with pending conflicts, or 2 with no partial stdout for invalid input.

The offline helper assigns the real OurAirports fixture's missing `review_owner`, rejects a changed assignment and accidental full-sheet application, retries, and verifies exact complete output. It also rejects a nonexistent conflict. Only the single known fixture's final choice/value pair is edited by a narrow suffix operation; arbitrary inputs use the production TSV parser. Run the helper with `native` on supported Linux/macOS CLI hosts.
