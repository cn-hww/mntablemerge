# Changelog

## 0.1.0 — 2026-10-31

- Additive `UniqueRule` / `UniqueReview` phase for exact single/compound unique
  tuples: reject invalid sources, inspect merge-created duplicates, explicitly
  repair implicated fields/drop records, revoke/replace repairs and guard export.
  New unique-review/report/changes envelopes bind rules and full source evidence;
  legacy APIs, enum variants and ordinary review-1..5 formats retain their meaning.
- Full uniqueness CLI and offline browser workflow, real-data CSV/TSV replay,
  package-consumer tests and generated public interfaces. Generic schema checks,
  expression/foreign-key constraints and assigned/combined unique reviews are
  outside this slice.

- Structural CSV/TSV three-way merge, explicit row/column lineage, source
  ordering and complete-table validation.
- Input-bound offline review/replay, editable/assigned sheets, explicit
  revision/revocation, independent review combination and decision audit.
- Git merge driver and complete-only no-replace file export.
- Packaged-source external-consumer gate on all four library targets, runnable
  catalog application, real-data review and documented API adoption contract.
- Additive `ColumnEvolution` for explicit column rename/delete, conservative
  keep/drop review, dependent revocation and input-bound review-5/report-4/audit-2.
  Existing retained lineage structs and legacy wire versions are preserved.

First release contents. Publication and registry-consumption evidence are
recorded separately in [validation](docs/validation.md).

### Offline browser review

- Self-contained HTML with the existing MoonBit core in a local worker, real-data
  examples, CSV/TSV uploads, compound keys, lineage/evolution declarations,
  structural/cell decisions, explicit dependent revocation and paginated drafts.
- Input-bound bundle resume, complete-only table downloads, full evidence and
  last-batch audit downloads; fatal UTF-8 decoding, explicit browser limits,
  cancellation and failure recovery preserve confirmed review state.
- Six JavaScript bridge test blocks and actual offline Chrome file-URL workflow
  QA, comparing downloads to the release Wasm CLI; no server/CDN dependency.

### Scale baseline and memory

- Portable, self-checking generated workloads and Linux native peak-RSS comparison
  against a pinned source commit, with raw samples and measurement limitations.
- Share opaque immutable table snapshots internally; preserve defensive array
  boundaries, result bytes, review binding and all existing public signatures.
