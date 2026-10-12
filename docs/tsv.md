# TSV transport for structural merge

`parse_tsv` and `Table::to_tsv` support **quoted tab-delimited text** with the
same strict quote grammar as CSV: quote fields containing tabs, quotes or line
breaks, double embedded quotes, accept LF/CRLF and an optional transport BOM.
Commas are ordinary TSV data. Literal backslash sequences are not escapes.
Variants that use backslash escapes for embedded tabs/newlines or treat quotes
as literal unescaped data are unsupported. No delimiter
guessing, trimming, scalar inference or blank-value filling is performed.

Both formats preserve the validated rectangular string table. CSV parsing and
output retain their existing behavior. TSV uses the same table/syntax/Unicode
limits and `MergeError` diagnostics; syntax errors still use `InvalidCsv` with
record/field locations because the parser shares its strict grammar. Key
uniqueness and structural correctness are checked by the existing merge engine.

```text
moon run cmd/main -- convert INPUT.csv --from csv --to tsv
moon run cmd/main -- merge BASE.tsv OURS.tsv THEIRS.tsv --key id --format tsv
moon run cmd/main -- review BASE.tsv OURS.tsv THEIRS.tsv --key id --format tsv
moon run cmd/main -- replay BASE.tsv OURS.tsv THEIRS.tsv --key id --format tsv --review REVIEWED.json
moon run cmd/main -- git-driver BASE.tsv OURS.tsv THEIRS.tsv --key id --format tsv
moon run scripts/tsv-demo.mbtx
```

Save stdout to a new UTF-8 file, never an input path. `--format csv|tsv` chooses
the transport for all three inputs and merged output; it defaults to CSV and
rejects duplicate/unknown values. Mixed-format inputs require explicit conversion
first. Conversion validates the entire table before emitting output. Exit 0
means success, 2 invalid input. Merge/replay/driver retain exit 1 for unresolved
conflicts. Driver replacement uses the same validated atomic write workflow.

Review JSON remains version-compatible and stores canonical CSV snapshots of
parsed tables. Transport formatting is not semantic identity: the same cells
may be replayed from CSV or TSV, but altered cells/order/schema/keys/policies
still fail the review guard. Format selects transport only; it cannot override
bound ordering or lineage decisions. No original whitespace/quoting preservation
is claimed.

The offline demo converts seven pinned OurAirports fixtures, checks semantic
round trips, merges TSV, tests malformed/unresolved driver byte preservation
and retry, resolves a structural missing cell, and rejects stale data. All 19
columns are retained, with the previously documented simulated branch changes.
Use `moon run scripts/tsv-demo.mbtx native` on supported Linux/macOS hosts.
