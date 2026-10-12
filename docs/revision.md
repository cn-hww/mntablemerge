# Revising an offline review

[Review version comparison](review-audit.md) now shows added, replaced and revoked resolutions with complete before/after evidence before accepting a revised bundle.

Reviewers sometimes correct a value or reverse a keep/drop choice after
inspecting the merged table. `resolve` continues to append choices and reject
duplicates. `revise` explicitly replaces or revokes choices and recomputes the
entire merge, leaving the previous plan/bundle available for comparison.

Library additions:

```moonbit
let changed = plan.revise([
  @tablemerge.Set({ target: column, choice: @tablemerge.Drop }),
  @tablemerge.Revoke(dependent_cell),
])
```

`ReviewEdit::Set(Decision)` may replace a recorded choice or select a conflict
reported by the **current** plan. `ReviewEdit::Revoke(Target)` requires a recorded
choice. `MergePlan::revise` and `ReviewBundle::revise` return new values. Targets
use output row/column coordinates when lineage is active. Source snapshots,
key selection, row ordering and both lineage declarations remain bound.

An edit batch is atomic: any duplicate target, unknown target, unsupported
choice, invalid Unicode or inapplicable retained decision rejects the whole
batch. It never removes other decisions automatically. For example, keeping a
column may require an explicit value for a newly added row; subsequently dropping
the column requires **revoking that cell decision in the same batch**. Switching
the selected source of a concurrent insertion has the same applicability check.
Unrelated choices remain in order, replacements retain their positions, and
new choices append in edit order. Empty edits preserve the report.

Revoking a structural choice can reopen the original structural conflict.
Returning to keep after drop may expose new cell conflicts. Inspect the resulting
report and supply cell choices in a **second** operation. Newly hidden targets
cannot be guessed in the structural batch. Errors include the rejected target
and suggest explicit dependency revocation; the CLI prints these diagnostics.

```json
[
  {"op":"set","target":{"column":"keywords"},"choice":"drop"},
  {"op":"revoke","target":{"row":["6524"],"column":"keywords"}}
]
```

`review_edits_json` / `parse_review_edits` use this strict array schema. Set has
exactly op/target/choice; revoke has exactly op/target. Unknown fields,
operations, duplicate object keys, empty/oversized keys and malformed choices
fail. Duplicate edit targets are rejected when applying the batch. Wire documents
are limited to 16,000,000 UTF-16 units, including escape expansion; the same
Unicode/depth restrictions as decisions apply. At most 2,000,000 edits are
accepted programmatically. No partial JSON or CSV is emitted on failure.

```text
moon run cmd/main -- review-revise COMPLETE.json EDITS.json
moon run scripts/revision-demo.mbtx
moon run scripts/revision-demo.mbtx native
```

Save stdout to a **new UTF-8 file**. Successful review-revise exits 0 even if the
new bundle is incomplete; invalid edits exit 2 with empty stdout. Replay exits 1
until conflicts are resolved. Existing bundle formats are unchanged: the bundle
contains current effective decisions. Keep earlier bundle files for an audit
trail; edit history, reviewer identity and signatures are **not implemented**.

The offline demo uses three pinned public-domain OurAirports records. One
simulated branch removes keywords and adds a record, while the other edits
keywords. It keeps/fills the missing intersection, rejects drop without revoke,
then explicitly revokes/drops, undoes, reopens and rejects stale input. Expected
retained cells are constructed from the pinned source records and compared
after normalizing CSV/order. All files remain intact on error. Native CLI demo
requires a supported Linux/macOS host; Windows uses Wasm.
