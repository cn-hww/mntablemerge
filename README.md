# MoonTableMerge

Structural three-way merge for keyed CSV tables, written in MoonBit. For developers who maintain catalogs, lookup tables or reference datasets in Git: independent cell edits merge, while destructive row/column changes and unknown intersections require explicit review.

**Implemented in 0.1.0:** compound keys, exact string values, row/column insertion and deletion, structural and cell conflicts, strict CSV, JSON diagnostics/decisions, input-bound offline review, a file CLI, and offline real-data examples. This is an early API; it is not yet published to Mooncakes.

## Try it

Install [MoonBit](https://www.moonbitlang.com/download/). Validated toolchain: `moonc v0.10.14+7d59c7ec9`, `moon 0.1.20260920`. Use the current `moon.mod` / `moon.pkg` formats.

```text
moon run scripts/demo.mbtx
moon run cmd/main -- merge examples/airports/base.csv examples/airports/ours.csv examples/airports/theirs.csv --key id
moon run cmd/main -- merge examples/airports/base.csv examples/airports/structure-ours.csv examples/airports/structure-theirs.csv --key id --report
moon run cmd/main -- merge examples/airports/base.csv examples/airports/structure-ours.csv examples/airports/structure-theirs.csv --key id --decisions examples/airports/decisions.json
```

The third command exits **1**, reporting `MissingCell` at row `6524`, column `review_owner`. The final command explicitly supplies `team-B` and produces a complete rectangular CSV. [Example provenance and expected output](examples/airports/README.md) explain every change.

CLI `merge BASE OURS THEIRS --key id[,other] [--decisions FILE] [--report]`: complete CSV on stdout; unresolved JSON on stderr; `--report` sends only JSON to stdout. Exit **0** complete, **1** unresolved, **2** invalid input/I/O. Input files are read only. The CLI accepts arbitrary files, not just the fixtures. Avoid redirecting stdout over an input file: shells truncate before running the CLI.

For decisions reviewed outside the immediate process, use [input-bound offline review](docs/review.md): `review` → `review-resolve` → `replay`. It rejects stale inputs instead of applying old choices to another revision. `moon run scripts/review-demo.mbtx` demonstrates the complete workflow.

## Library workflow

Add this repository as a local dependency with `moon.work` until registry publication. Import `"cn-hww/mntablemerge" @tablemerge`. The generated [public interface](pkg.generated.mbti) is the API reference.

```moonbit
let base = @tablemerge.parse_csv("id,value\nx,old\n")
let ours = @tablemerge.parse_csv("id,value\nx,ours\n")
let theirs = @tablemerge.parse_csv("id,value\nx,theirs\n")
let plan = @tablemerge.merge(base, ours, theirs, key=["id"])
let reviewed = @tablemerge.resolve(plan, [{
  target: @tablemerge.Cell(@tablemerge.RowKey(["x"]), "value"),
  choice: @tablemerge.Value("reviewed"),
}])
let csv = reviewed.finish().table().to_csv()
```

Calls raise `MergeError`; use them in a raising function/test or handle errors. An unresolved plan cannot be exported. Accessors return defensive copies. `report()` includes affected source values and resolution evidence. See [the design contract](docs/design.md) for three complete workflows.

## Rules that prevent data loss

- Values are strings: `007`, spaces, empty strings and quoted newlines retain their meaning. Missing data is never invented as an empty string.
- Headers are exact, nonempty and unique. Keys have nonempty components and are unique per input. Removing a key column fails. Key/header changes are delete/add; renames are not inferred.
- Row/column deletion competing with any change on that structure requires `keep`/`drop`. Even removing a row on the opposite branch counts as a column change, and conversely; this conservative rule can request review for two independent deletions.
- Different concurrent inserts with the same key require selection of a whole row. Structural decisions precede cell decisions. Unknown, duplicate, premature, invalid or absent-source choices fail.
- Output uses base column order plus sorted new headers, and lexicographically sorted compound row keys. Row order is not identity. CSV formatting is normalized to LF/necessary quoting; semantic cells round-trip.
- Strict JSON rejects duplicate object keys (including escaped aliases) and unknown fields. Input limitations produce errors, never partial output.

CSV supports UTF-8, optional leading BOM, comma delimiters, LF/CRLF, doubled quotes and quoted line breaks. Limits: 100,000 rows, 512 columns, 2,000,000 cells and 16,000,000 UTF-16 code units per table/CSV/JSON; CLI reads are capped at 64,000,000 bytes. Union/output limits are also enforced. No streaming, XLSX, fuzzy keys, type inference or automatic rename detection.

## Validation and platform scope

The pure library supports Wasm, Wasm-GC, JavaScript and native. The async file CLI supports Wasm and Linux/macOS native hosts; Windows native CLI is excluded because of the current async dependency's MSVC requirement. A C compiler is required for native execution. CI exercises Linux, Windows and macOS; test outcomes are recorded in [validation](docs/validation.md), separately from planned compatibility.

```text
moon run scripts/verify.mbtx
```

On Windows, if your compiler is absent from PATH, supply its directory as the script's only argument. This runs format/interface generation, strict checks, all four backend tests and actual Wasm/native CLI demos. CI additionally refuses formatting/interface drift. Tests include 100 CSV round trips, 64 scalar combinations, structural conflicts, limits, deterministic ordering, defensive copies and recovery after failed decisions.

## Scope and roadmap

This project's independent boundary is **two-dimensional structural merge with complete-table invariants and explicit evidence**, complementing CSV, DataFrame, diff and generic JSON merge libraries. [Research](docs/research.md) records adjacent MoonBit APIs, demand, overlap and remaining uncertainty. No ecosystem uniqueness, algorithm originality or performance advantage is claimed.

Next complete capability: a Git merge driver; later, explicit rename lineage and ordering policy options. Browser review and other formats remain planned and depend on demand.

MIT. [Third-party sources and licenses](THIRD_PARTY.md).
