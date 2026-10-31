# Uniqueness-aware merge review

Implemented first slice; actual execution evidence is recorded in
[validation](validation.md). This remains pre-1.0 and unpublished.

`UniqueReview` adds a policy-bound review phase to an existing `ReviewBundle`.
Old merge APIs, `Target`/`Choice` variants and review-1..5 bytes keep their
meaning. The independent value is tracing and explicitly repairing uniqueness
violations introduced by the combination of three individually valid snapshots.

Three workflows: two branches insert different IDs with the same email; two
catalog editors give different products the same `(country, sku)`; two editors
change different airports' `ident` fields to the same simulated identifier. The
last uses the existing licensed full-record OurAirports fixtures. In each case,
declare the rule, resolve ordinary conflicts, inspect complete duplicate-row
source evidence, explicitly drop a record or set a unique field, recheck, save
the review and replay against the original files before exporting.

Rules are named, nonempty ordered column arrays. Equality is exact Unicode
string tuple equality: no delimiter joining, trimming, case folding, type
inference or SQL NULL semantics. Empty strings participate in uniqueness.
Columns use output coordinates after declared lineage. Rule columns must exist
in all three aligned inputs and the merged schema. An already-invalid input is
rejected with its source, rule, value tuple and row identities; it is not treated
as a merge-created conflict. Rules have unique names and unique column sets.
Limits: 1..64 rules, at most 512 total column references; existing table/text
limits apply. Full violation evidence is capped at 2,000,000 source/candidate
cells; overflow fails explicitly. JSON output is capped at 16,000,000 UTF-16
units, without truncation.

Ordinary structure/cell conflicts precede uniqueness review. A uniqueness repair
uses existing `Decision` coordinates, in a separate namespace: `Row/Drop` or
`Cell/Value`. It may affect only initially duplicated rows and their implicated
unique columns; primary-key editing, unrelated changes and implicit deduplication
are rejected. A row cannot be both dropped and edited in the same repair set.
All repairs are applied atomically, in canonical target order. Partial repair is
allowed, but a repair must not introduce a duplicate pair absent from the initial
merged candidate. Failed repairs preserve the previous review. Replacements and
revocations are explicit `ReviewEdit` operations. Revoke repairs before changing
ordinary decisions that change their initial candidate.

`finish` refuses ordinary or unique conflicts. CSV/TSV preserves all unaffected
records, columns and exact strings, and keeps the selected row order. The
versioned `unique-review-1` envelope binds the full ordinary bundle, rules and
repairs. Import strictly checks fields/duplicates/Unicode/versions and recomputes
every phase. `unique-report-1` retains ordinary conflict fields and adds complete
unique conflicts/repair evidence. `unique-changes-1` compares two reviews of the
same inputs and policies, retaining before/after evidence; it is not authentication.

No generic schema validator, fuzzy deduplication, cross-field expressions,
foreign keys, XLSX, rule editing during review, assigned sheets or independent
unique-review combination is part of this slice. Existing ordinary sheets and
combination remain available for ordinary bundles; unsupported unique envelopes
must be refused. Registry publication is a separate action.

## Minimal library workflow

Create a normal merge/review with the existing APIs, then wrap it:

```moonbit
let base = @tablemerge.parse_csv("id,email\n")
let ours = @tablemerge.parse_csv("id,email\n101,team@example.com\n")
let theirs = @tablemerge.parse_csv("id,email\n202,team@example.com\n")
let plan = @tablemerge.merge(base, ours, theirs, key=["id"])
let review = @tablemerge.UniqueReview::new(
  @tablemerge.ReviewBundle::from_plan(plan),
  [@tablemerge.UniqueRule("unique_email", ["email"])],
)
let fixed = review.repair([{
  target: @tablemerge.Cell(@tablemerge.RowKey(["202"]), "email"),
  choice: @tablemerge.Value("other@example.com"),
}])
let csv = fixed.finish().table().to_csv()
```

Calls raise `MergeError`. First inspect `merge_conflicts()` and `conflicts()`;
`revise` handles ordinary decisions, `repair` adds uniqueness decisions,
`revise_repairs` explicitly sets/replaces/revokes them. `rules`/`repairs` and
conflict accessors return defensive arrays. Repairs are always relative to the
unrepaired merged candidate. `finish().resolutions()` retains ordinary resolution
evidence; uniqueness repair evidence is in the wrapper's `report` and
`changes_report`. `to_json` / `from_json` recompute the complete workflow;
`replay(base, ours, theirs, key=...)` refuses stale original files/keys and retains
the envelope's rules. The external packaged consumer exercises this public API.

## CLI and offline browser

```text
moon run scripts/unique-demo.mbtx wasm
moon run scripts/unique-demo.mbtx native
```

The native helper requires a supported Linux/macOS async host. It reads the
licensed full-record OurAirports CSV, simulates independent identifier edits,
and verifies all 19 columns, exact CSV/TSV replay, rejected incomplete file export,
audit, revocation, stale inputs and invalid-source recovery. No network is used.

CLI workflow (commands after `moon run cmd/main --`):

```text
review BASE OURS THEIRS --key id
unique-review ORDINARY_BUNDLE RULES.json
unique-report UNIQUE_BUNDLE
unique-revise UNIQUE_BUNDLE ORDINARY_EDITS.json
unique-repair UNIQUE_BUNDLE REPAIR_EDITS.json
unique-replay BASE OURS THEIRS --key id --review UNIQUE_BUNDLE
unique-changes BEFORE_UNIQUE_BUNDLE AFTER_UNIQUE_BUNDLE
```

Save each emitted bundle to a new file before the next step. Rules use exactly
`[{"name":"unique_email","columns":["email"]}]`. Repairs use the existing edit
syntax, for example `[{"op":"set","target":{"row":["202"],"column":"email"},"choice":{"value":"other@example.com"}}]`;
row deletion uses `{"op":"set","target":{"row":["202"]},"choice":"drop"}`.
Revocation uses `{"op":"revoke","target":...}`. Ordinary commands refuse unique
envelopes; use `unique-revise` for their ordinary decisions. Unique replay supports
`--format csv|tsv`, `--report` and complete-only `--output NEWFILE`; output never
replaces an existing destination. Exit 0 means complete export, 1 means unresolved
replay (no partial table), and 2 means invalid input/I/O. Review/report/edit/audit
commands emit a validated document with exit 0 even when review is incomplete.

Build [the offline browser](browser.md) and choose “载入唯一性冲突示例”, or declare
rules in the advanced import panel. Review each duplicate group's original
sources and current merged values, then explicitly check a field repair or
whole-record deletion. The UI shows up to 12 affected records per application;
remaining violations stay pending and reappear after applying a batch. Resolved
repairs can be edited/revoked; conflicting drop/edit operations fail atomically.
Saved unique envelopes reopen and validate against the original three files.
CSV/TSV export stays disabled until both review phases are complete. UI QA
compares actual downloads and audit JSON with the release CLI, including reopen,
revocation and whole-record deletion.
