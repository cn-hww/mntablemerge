# Changelog

## Unreleased — 0.1.0 development

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

This is not a registry release announcement. Mooncakes publication and registry
installation have not been performed or validated.

### Offline browser review

- Self-contained HTML with the existing MoonBit core in a local worker, real-data
  examples, CSV/TSV uploads, compound keys, lineage/evolution declarations,
  structural/cell decisions, explicit dependent revocation and paginated drafts.
- Input-bound bundle resume, complete-only table downloads, full evidence and
  last-batch audit downloads; fatal UTF-8 decoding, explicit browser limits,
  cancellation and failure recovery preserve confirmed review state.
- Five JavaScript bridge test blocks and actual offline Chrome file-URL workflow
  QA, comparing downloads to the release Wasm CLI; no server/CDN dependency.

### Scale baseline and memory

- Portable, self-checking generated workloads and Linux native peak-RSS comparison
  against a pinned source commit, with raw samples and measurement limitations.
- Share opaque immutable table snapshots internally; preserve defensive array
  boundaries, result bytes, review binding and all existing public signatures.
