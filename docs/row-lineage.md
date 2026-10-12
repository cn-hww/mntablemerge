# Explicit row identity migration

A catalog's identifier may change on one branch while another branch edits its
description. Matching only literal keys treats this as a deletion and insertion.
`RowLineage` lets the dataset owner explicitly identify the retained record;
the merger then combines independent non-key edits under the chosen output key.
This is useful for migrations from local IDs to canonical IDs or compound keys.

```json
[{"base":["6523"],"ours":["airport:6523"],"theirs":["6523"],"output":["airport:6523"]}]
```

Each identity is an ordered string array matching `key`. All three source rows
must exist and be individually unique. Each source and output identity may be
declared once. Output keys cannot collide with undeclared rows. Simultaneous
swaps/cycles are supported; declaration order does not change merged data.
This is an explicit correspondence supplied by the owner, not a claim that
different IDs represent the same real entity. Mistaken correspondences cannot
be detected from string data alone. Deleted records, splitting/combining rows
and fuzzy inference are unsupported and rejected; ordinary deletion review
remains available without a declaration.

Column alignment runs first. Key column names refer to **output column names**;
key components in the declaration refer to each original source's values.
Only key cells are replaced. Every other cell and the source's row sequence
remain intact. Unrelated row/column deletion conflicts still require review.
Values such as `007`, Unicode and delimiter characters remain exact strings.

Library: `merge(..., key=["id"], row_lineage=links)`;
`RowLineage { base: RowKey, ours: RowKey, theirs: RowKey, output: RowKey }`;
`parse_row_lineage`, `row_lineage_json`, and `MergePlan::row_lineage`.
Declarations are bounded to 100,000 entries and 1..512 nonempty components;
normal table, Unicode and JSON limits still apply. Errors return no partial plan
or CSV. Existing plans and input arrays survive rejected operations.

```text
moon run cmd/main -- merge examples/airports/base.csv examples/airports/identity-ours.csv examples/airports/theirs.csv --key id --rows examples/airports/rows.json
moon run scripts/identity-demo.mbtx
moon run scripts/identity-demo.mbtx native
```

The offline demo uses all 19 columns of pinned public-domain OurAirports records.
The identifier migration, reviewed name and audit note are simulations. It
checks expected output, a conflict at `airport:6523/name`, serialized review,
stale-input rejection, and Git driver failure/retry preserving input bytes.
Native CLI execution requires Linux/macOS and a C compiler.

`--rows FILE` is accepted by merge/review/git-driver. Replay rejects overrides:
the bundle binds declarations, key order, row ordering and original snapshots.
Mapped conflicts use **output identities**. `report-3` includes row and column
lineage plus row order, making original IDs visible in the report.
`review-4` stores the same policies and original CSV snapshots. Legacy review
versions 1..3 remain accepted; exporting a plan without row lineage retains its
previous format. Bundle editing is not protected by a signature.
