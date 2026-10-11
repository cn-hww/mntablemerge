# MoonTableMerge: first usable capability

Status: implemented design contract for version 0.1.0; platform validation is recorded separately.

## Users and three complete workflows

1. **Product data in a Git repository.** A developer starts from a catalog, changes prices on one branch while a colleague changes stock on another. They supply ancestor/ours/theirs and the compound key `sku,warehouse`, inspect cell conflicts, record decisions, and receive one complete importable CSV. Reordering rows does not change identity. Neither input is overwritten.
2. **A maintained reference dataset changes structure.** One branch adds a column while another adds a record. A newly formed row/column intersection has no source value. The developer receives a `MissingCell` diagnostic, supplies an explicit value, and then exports a rectangular table. No blank is invented. OurAirports provides publicly licensed real source records for the runnable demonstration; branch changes are simulated and clearly labeled.
3. **A destructive schema change competes with new data.** One branch removes a column while another modifies it or inserts a row containing that column. The reviewer decides the fate of the whole column. Dropping it explicitly records affected source values; keeping it restores still-available source values. Row deletion versus edits/additional cells is symmetric. The resulting table is revalidated before export.

## Public boundary

The library owns `Table`, `MergePlan`, `Conflict`, `Decision`, and `MergedTable`. Tables are created through validating constructors; accessors return copies. The minimum workflow is `Table::from_rows` or `parse_csv` -> `merge` -> `MergePlan::conflicts` -> `resolve` -> `MergedTable::table` / CSV serialization. A plan owns defensive snapshots of all inputs; it is not an arbitrary JSON merge result.

Conflict identities consist of their typed row/column coordinates. Decisions select base/ours/theirs/custom cell values or explicitly keep/drop structural objects. Decisions for unknown conflicts, conflicting duplicate decisions, missing source values, and invalid structural choices are errors. Repeating the same exact decision is also rejected, rather than interpreted as a last-writer rule.

## Structural semantics

Rows use exact, nonempty compound keys; columns use exact unique header names. Row/column order is not data identity. Output columns follow base order then lexicographically sorted new names; output rows are lexicographically sorted by their component arrays. Values are exact strings: leading zeros, spaces, quoted newlines, and empty strings are preserved.

For an existing row or column, deleting it on one side while the other side changes any data on it is a structural conflict. This includes new cells caused by new columns or new rows. A structural decision owns the whole row/column, not a collection of unrelated JSON pointer deletions. Uncontested deletions are applied. Independent insertions are preserved. Concurrently inserted rows sharing a key require an explicit row-source decision if different; they are not combined into a guessed record.

After structural decisions, surviving intersections are merged. Equal values coalesce; a change on only one side wins over unchanged base. Two different concurrent values conflict. A surviving intersection with no value in any source is `MissingCell`, distinct from a stored empty string. Decisions are applied in two phases: resolve structure, then resolve cells. The CLI report shows current conflicts and the decision file can accumulate both phases. Every supplied decision must be consumed by a real conflict in the replay; irrelevant decisions are errors. A result is exportable only when no conflicts remain and all invariants hold.

Key columns are immutable structural requirements. Removing a key column, duplicate headers/keys, ragged rows, or an empty key component are rejected with location and suggested repair. Keys themselves cannot be edited through a cell decision. Changes to key values in source CSV are ordinary delete/add, because CSV contains no rename intent. Column disappearance/addition is likewise delete/add; there is no rename inference.

## Inputs and environments

Supported: in-memory rectangular string tables and UTF-8 comma-delimited CSV with a header, LF or CRLF, doubled quote escaping and quoted line breaks. Optional leading UTF-8 BOM is transport metadata. Export uses deterministic LF and necessary quoting, preserving semantic cell data, not original CSV formatting. Limits bound input size, rows, columns, and prospective output cells; oversized input fails before large intermediate allocations.

Unsupported: XLSX, binary/non-UTF-8 input, alternate separators, fuzzy identity, inferred scalar types, numeric tolerance, streaming/infinite tables, automatic rename detection, concurrent edits to a live database, Git configuration installation, and cryptographic authenticity of review files. Unsupported/malformed input produces an error, never a partial exported table.

The pure library targets Wasm, Wasm-GC, JavaScript and native. A file CLI uses MoonBit async host I/O on supported Wasm/native hosts; target claims are recorded only after actual runs. CI covers Linux, Windows and macOS. Local native execution requires a C compiler.

## Demonstration and independent checks

The first runnable demo reads pinned real OurAirports rows, performs an independent cell merge and a row/column intersection conflict, then resolves the conflict and prints the complete table. All fixtures are offline. A CLI accepts arbitrary user files and review decisions; it is not restricted to these fixtures. Review reports contain the full source values relevant to conflicts and explicit decisions.

Checks cover semantic CSV round trips, empty versus undefined cells, malformed input, duplicate compound keys, delimiter-containing keys, Unicode, strict conflict handling, repeatability, immutable input snapshots, error recovery, structural symmetry and final-table invariants. Small exhaustive combinations are compared with a separately specified scalar truth table; no performance claims are made.

## Capability roadmap

1. Complete structural three-way merge with strict CSV, explicit review/replay, complete output, real offline example and cross-target validation. This milestone is independently useful.
2. Source row ordering is implemented with deterministic lexical fallback and review-bound policy. Explicit row/column rename operations with auditable lineage and larger-data memory improvements remain planned, each with preservation tests.
3. Input-bound offline review and Git driver integration are implemented using this same library contract. Browser review and format adapters remain planned, following demonstrated downstream demand.

No arbitrary commit-count goals, general DataFrame API, translation runtime, or database engine are planned.
