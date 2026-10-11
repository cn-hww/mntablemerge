# Explicit column lineage

A schema migration renames `name` to `airport_name` on one branch, while another branch edits the existing name values. Treating these columns as delete/add can require a destructive-deletion review or leave two distinct columns. Explicit lineage declares that they are one logical column so the normal three-way cell rules can reconcile their edits.

```moonbit
let columns : Array[@tablemerge.ColumnLineage] = [{
  base: "name", ours: "airport_name", theirs: "name", output: "airport_name",
}]
let plan = @tablemerge.merge(base, ours, theirs, key=["id"], column_lineage=columns)
let result = plan.finish().table()
```

The source tables must be validated `Table`s. Each declaration names one existing column in **each** source and its desired output name. Undeclared columns retain their names and normal lifecycle rules. Mapping is simultaneous: swaps/cycles are supported without intermediate collisions. Every cell stays attached to its declared logical column; values, row identities and physical positions are retained. Output columns keep the mapped base sequence plus sorted newly added names. Key names and decision coordinates use **output names**. A key column can be renamed without changing its key values; compound keys remain supported.

Every source name and every output name must be unique within the declarations. The complete mapped schema must also be unique, including undeclared columns. Missing/empty names, duplicate mappings, collisions, invalid Unicode and expanded size violations fail before any output or Git-driver write. At most 512 declarations are accepted. A failed mapping leaves input tables and prior plans usable. Constructor inputs/accessors own copies.

This capability only maps retained columns present in all three schemas. It does not infer rename intent, split/combine columns, transform values, rename row keys or resolve rename versus deletion. For a missing declared column, correct the mapping or remove that declaration and review its ordinary deletion conflict. Source key-value changes remain delete/add. The caller is responsible for supplying the intended correspondence; the engine cannot prove that two arbitrary headers mean the same thing.

## CLI and offline workflow

`column_lineage_json` serializes declarations, refusing invalid Unicode or an export beyond the 512-entry/16-million-code-unit import limits. `parse_column_lineage` accepts only an array of exactly `base/ours/theirs/output` string objects. It rejects unknown/duplicate JSON fields; merge additionally validates declarations against the tables. These calls raise `MergeError`. Put the objects in a UTF-8 file, then:

```text
moon run cmd/main -- merge examples/airports/base.csv examples/airports/rename-ours.csv examples/airports/ours.csv --key id --columns examples/airports/columns.json
moon run scripts/rename-demo.mbtx
```

The example uses pinned public-domain OurAirports records with simulated rename, value and keyword edits. The helper checks exact complete output, then creates a competing name edit, exports a review, resolves its `airport_name` cell, and replays against the original schemas. A changed non-conflicting source value is rejected as stale. It also checks that an invalid Git-driver mapping preserves OURS byte-for-byte, followed by successful retry with both mapping and ordering options. All fixtures are offline; no private service is needed.

`merge`, `review` and `git-driver` accept `--columns FILE`, combined with `--row-order`. A bundle with lineage uses strict `mntablemerge/review-3`: the original six fields plus `row_order` and `column_lineage`. Original source CSV snapshots are retained, not replaced by transformed tables. Import revalidates mappings and cumulative decisions; `review-resolve` preserves both mapping and ordering. Replay accepts no overriding `--columns`/`--row-order`; regenerate review for a different policy. Existing `review-1`/`review-2` remain supported and still exported for plans without lineage.

Reports with lineage use `mntablemerge/report-2`, adding `column_lineage` and `row_order` to the existing report. Conflict and resolution coordinates/source-value column labels use output names; the declarations translate those back to each source. Without lineage the report-1 format remains unchanged. Review bundles guard accidental revision mismatch; they do not authenticate intentional edits to a bundle.
