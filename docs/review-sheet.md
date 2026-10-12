# Editable input-bound review sheets

Reviewers can fill `choice` and `value` columns instead of constructing decision JSON. This is part of the existing three-way structural review workflow: every sheet carries its originating bundle and complete current conflict evidence. It supports UTF-8 TSV editors that preserve exact strings and quoted TSV grammar. Spreadsheet import/export, XLSX and browser editing have not been validated or implemented.

```text
moon run cmd/main -- review BASE.csv OURS.csv THEIRS.csv --key id
moon run cmd/main -- review-sheet DRAFT.json
moon run cmd/main -- review-apply-sheet DRAFT.json EDITED.tsv
moon run cmd/main -- replay BASE.csv OURS.csv THEIRS.csv --key id --review REVIEWED.json
moon run scripts/sheet-demo.mbtx
```

Save each command's stdout to a **new UTF-8 file**, respectively `DRAFT.json`, `EDITED.tsv` and `REVIEWED.json`. Edit `EDITED.tsv` before applying. Export/apply exit 0 for a valid sheet/bundle, including unfinished review; invalid input exits 2 with a diagnostic and no partial stdout. Replay still exits 1 for unresolved conflicts. All inputs are read only. `moon run scripts/sheet-demo.mbtx native` executes the workflow on supported native CLI hosts.

Public additions: `MergePlan::review_sheet() -> Table raise MergeError` and `MergePlan::apply_review_sheet(Table) -> MergePlan raise MergeError`. Use `to_tsv` / `parse_tsv` for transport and `ReviewBundle::from_plan` to persist the result. A failed application leaves the original plan and earlier review files unchanged.

The exact eight headers are `format,target,kind,base,ours,theirs,choice,value`. Format: `mntablemerge/sheet-1`. The first data row is a binding record: `kind=binding`, with the complete canonical originating review bundle in `base`. Keep it first and unchanged. It binds all three snapshots, key selection, ordering, both lineages and existing decisions, including data unrelated to conflicts. It is a revision guard, not authentication or a signature.

Every remaining row represents a current conflict. `target` is JSON in output coordinates; `base/ours/theirs` are complete JSON evidence arrays with source coordinates and exact values. Keep these first six columns unchanged and every row exactly once, including undecided conflicts. Conflict rows may be reordered; applying canonicalizes new decisions to the original conflict order.

| choice | value | meaning |
|---|---|---|
| empty | empty | Leave pending |
| `keep` / `drop` | empty | Structural object decision, where applicable |
| `base` / `ours` / `theirs` | empty | Select an available source, where applicable |
| `value` | exact text, possibly empty | Set a cell; empty is an explicit stored empty string |

Choices are case-sensitive and must be valid for that conflict. Nonempty `value` with any other choice is rejected, never discarded. Quoted values may contain tabs, quotes, Unicode and newlines. Structural choices can expose new `MissingCell` conflicts: save the returned bundle, export a **new** sheet and review that phase. Reusing the old sheet is rejected. Existing choices remain; changing/revoking them uses the separate [revision workflow](revision.md).

Application rejects stale bindings, changed headers/evidence/coordinates, omitted/duplicate/unknown records and invalid choices before returning a result. There are no partial decisions on failure; repair and retry against the unchanged bundle. Deliberately changing both a bundle and its binding does not authenticate the original data or reviewer.

Existing table limits apply, including 16,000,000 semantic UTF-16 units across all fields, 100,000 records and 2,000,000 cells. The binding occupies one record, leaving at most 99,999 conflicts; complete snapshots/evidence can reach the size limit earlier. Bundle export separately enforces its 16,000,000-unit escaped JSON limit. Oversized sheets fail with `LimitExceeded`, preserving all evidence. The JSON workflow may remain usable when only the additional sheet representation exceeds a limit; it has its own limits. There is no truncation or pagination.

The offline demo retains all 19 source columns of the pinned OurAirports records and a simulated missing `review_owner` for airport `6524`. It rejects unused custom text and modified evidence, retries with `choice=value,value=team-B`, verifies exact expected replay, and rejects the sheet against a bundle with a changed nonconflicting municipality. It edits only the known fixture's last empty choice/value pair; arbitrary TSV uses the production parser. No network/private infrastructure is required.
