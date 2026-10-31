# Explicit column rename versus deletion

One branch renames `price` to `unit_price`, while the other removes `price`.
The retained-only `ColumnLineage` API intentionally rejects a missing source.
`ColumnEvolution` adds explicit branch absence without changing that API:

```moonbit
let evolution : Array[@tablemerge.ColumnEvolution] = [{
  base: "price", ours: Some("unit_price"), theirs: None, output: "unit_price",
}]
let plan = @tablemerge.merge(base, ours, theirs,
  key=["id"], column_evolution=evolution)
let kept = @tablemerge.resolve(plan, [{
  target: @tablemerge.Column("unit_price"), choice: @tablemerge.Keep,
}])
```

These calls raise `MergeError`. **A declaration with exactly one absent branch
always requires Keep/Drop**, even if the retained values equal the ancestor,
the retained name is unchanged, or there are no records. This conservative rule
respects explicitly declared retention intent; a rename is not inferred from
cell changes. Without such a declaration, existing deletion rules still apply.

Keep preserves available source values under the output name. If another branch
added a record without that column, the newly exposed intersection is a
`MissingCell`, which needs an explicit value in the next review phase. An empty
string is a stored value; `None` / JSON `null` means a branch column is absent.
Drop removes the whole column and retains affected source values as resolution
evidence. Dropping after filling an intersection requires explicit revocation
of that dependent decision; it is never silently discarded.

## Validation and composition

- The ancestor column must exist; its name and output name are nonempty strings.
  Each branch source is either a present, nonempty name or explicit absence.
- Both branches present use normal cell merge rules. Both absent mean agreed
  deletion. Missing ancestor / inserted-column identity matching is unsupported.
- Declared sources and outputs are one-to-one across retained lineage and
  evolution combined, with a combined limit of 512 declarations. Simultaneous
  mappings preserve cells and physical column positions; output collisions with
  undeclared columns fail.
- An absent branch cannot contain an unclaimed old/source/output name belonging
  to the declaration. If a name was reused for another logical column, declare
  that other column's ownership explicitly. An absent output identity may never
  remain occupied. Ambiguity produces a diagnostic rather than a guessed match.
- Key columns must still exist in every aligned input. Deleting a key cannot be
  repaired by a keep decision, because the missing row identities cannot be
  invented. Retained row-ID migration and retained key-column rename compose
  with non-key evolution; row-ID migration versus record deletion remains
  unsupported.
- Unicode, table, JSON and export limits remain enforced. Errors preserve prior
  plans, input arrays and files. `column_evolution()` returns an owned array.

## CLI and complete review workflow

`merge`, `review` and `git-driver` accept `--column-evolution FILE`, combined with
`--columns`, `--rows`, `--row-order` and `--format` where applicable. The file is
a strict JSON array; every object has exactly these fields:

```json
[{"base":"price","ours":"unit_price","theirs":null,"output":"unit_price"}]
```

`column_evolution_json` / `parse_column_evolution` serialize the same contract.
Unknown/duplicate fields, invalid names/types, malformed Unicode and oversize
documents fail. The parser checks syntax; merge additionally checks schemas.

```text
moon run scripts/evolution-demo.mbtx
moon run scripts/evolution-demo.mbtx native
```

The offline helper uses complete pinned OurAirports records, simulating a
`keywords` → `audit_tags` rename, competing column deletion and record insertion.
It checks keep → missing intersection → explicit fill → combined review → exact
CSV/TSV replay, then drop/revoke → complete audit evidence → 18-column result.
It also verifies stale/override rejection and Git-driver byte preservation.
Native execution requires a supported Linux/macOS CLI host and C compiler.

Bundles with evolution use `mntablemerge/review-5`, adding `column_evolution` to
the review-4 fields; they retain original snapshots, keys, row order and both
retained lineages. Replay rejects all policy overrides. Reports use `report-4`;
audit exports use `review-changes-2` when evolution is present. Conflict kinds
and Keep/Drop choices are unchanged, with **output column names** in coordinates
and values. Declarations and original snapshot headers identify source names.
Full/assigned sheets, combination, revision and typed audit use the same binding.

Without evolution, existing API behavior, report/bundle/audit versions and
default output bytes remain unchanged. Older valid review versions 1–4 remain
importable. Existing retained `ColumnLineage` fields still require strings in
all three inputs; an old reader rejects the new version instead of losing policy.
