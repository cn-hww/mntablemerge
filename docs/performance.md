# Measured scale baseline and immutable snapshot sharing

Status: a reproducible synthetic workload runner and a measured internal memory
optimization, not a performance or maximum-workload guarantee. The public API,
table limits, default CSV bytes and review wire formats are unchanged.

## What changed

`Table` is opaque and immutable after its validating constructor takes defensive
copies. The internal use audit found no mutation of its stored columns/records.
`headers()` and `rows()` still return defensive copies; schema/row transformations
construct new validated tables. Internal `snapshot()` can therefore retain the
immutable table instead of copying every row during merge, finish/table access
and review capture. Shared references cannot expose a writable backing array.

Regression tests mutate constructor inputs, arrays from every public table
boundary, conflict arrays and exported review JSON, including after failed
revision and subsequent replay. They lock down unchanged CSV/report bytes and
independent older plans/bundles. A future mutating Table API would need to revisit
this invariant, using new storage or copy-on-write rather than changing a shared
table in place.

## Reproduce

The portable runner is usable on all four library targets:

```text
moon run --target native --release bench/runner -- 10000 16 25 review
moon run scripts/bench-smoke.mbtx wasm
```

Parameters: rows, columns **including the key**, percentage of rows with one
conflicting `v1` cell, and `merge|review|lineage|unique`. It bounds generated
dimensions, verifies every output cell/header/order and emits timing plus CSV,
report and bundle fingerprints. `merge` uses repeated payload strings; `unique`
uses row/column-specific strings. `lineage` adds explicit column rename and
1% row-ID migration. `review` includes bundle serialization/import and guarded
replay. All modes apply an explicit decision batch, including an empty batch.

On **Linux**, GNU time, unzip, Git and a C compiler provide whole-process peak RSS:

```text
moon run scripts/measure.mbtx 2404100fed8de346dc71ab0aada845d6a77b2f99
moon run scripts/measure-summary.mbtx
```

The script archives the baseline commit into an isolated temporary directory,
copies the exact same runner into it, and builds both sources as native release
with the current toolchain/compiler. It validates one warmup pair and records
three additional fresh-process samples per variant/case, alternating run order.
All 42 recorded samples are retained in [reference data](benchmarks/native-linux.json).
The ignored `output/measure.json` includes the local toolchain details; the
shareable reference removes local machine paths/hostname, not measurement values.

`elapsed_us` uses the core monotonic clock: it excludes input generation and
includes merge, decision replay, report/digest, full result validation and CSV
export (plus bundle round trips in review mode). It is **not isolated algorithm
time**. GNU time RSS is **whole-process KiB**, including generation/validation,
not just live table storage. Its separate wall_seconds field includes process
startup and has coarse resolution. Fingerprints are non-cryptographic FNV-32,
supplemented by full per-cell checks and the exact regression tests.

## Reference observations

2026-10-31, WSL/Ubuntu native C release, Moon 0.1.20260920 / moonc 0.10.14.
CPU, kernel, compiler, optimized table source SHA-256 and individual samples are
in the reference JSON. Medians of three recorded samples (µs truncated to integers):

| Workload / rows × columns / conflict rows | Before µs | After µs | Before RSS KiB | After RSS KiB | RSS reduction |
|---|---:|---:|---:|---:|---:|
| merge / 1000 × 8 / 0% | 4580 | 5315 | 4116 | 3960 | ≈3% |
| merge / 10000 × 16 / 0% | 64906 | 70764 | 26004 | 21608 | ≈16% |
| merge / 50000 × 32 / 0% | 549087 | 524419 | 182628 | 138496 | ≈24% |
| review / 10000 × 16 / 1% | 346321 | 293765 | 53164 | 45948 | ≈13% |
| review / 10000 × 16 / 25% | 303490 | 295778 | 54248 | 53384 | ≈1% |
| lineage / 10000 × 16 / 5% | 129910 | 126976 | 34324 | 26484 | ≈22% |
| unique / 50000 × 16 / 0% | 497788 | 475738 | 142560 | 112944 | ≈20% |

Measured peak RSS decreased in these cases; the 50,000 × 32 case is approximately
178.3 → 135.3 MiB. Small merge cases were slower in this sample, so there is no
general speedup claim. Three samples on a shared WSL host are not statistically
controlled evidence; allocator retention, scheduler load and hardware affect
results. These programmatic string tables do not model every CSV/CLI dataset,
browser heap, target or conflict distribution. No comparison with another
project is implied. CI runs only small correctness smoke workloads, with no
timing/RSS threshold that could fail due to runner noise.
