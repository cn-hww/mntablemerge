# Input-bound offline review

A bare decision array names conflicts but has no revision information. `ReviewBundle` owns all three parsed CSV snapshots, the ordered key selection and cumulative decisions. It recomputes conflicts on import/replay; it never trusts a persisted preview or accepts unused decisions.

```text
moon run cmd/main -- review BASE.csv OURS.csv THEIRS.csv --key id
moon run cmd/main -- review-resolve DRAFT.json DECISIONS.json
moon run cmd/main -- replay BASE.csv OURS.csv THEIRS.csv --key id --review REVIEWED.json
moon run scripts/review-demo.mbtx
```

Save each command's stdout as a **new UTF-8 file**, separately from its inputs. `review` and `review-resolve` exit 0 when a valid bundle was produced, even if incomplete. `replay` exits 1 for pending conflicts and 2 for input/decision errors. With `--report`, replay prints diagnostics/evidence rather than CSV. Structural review may expose cell conflicts: export the updated bundle and use `review-resolve` again.

Library API: `ReviewBundle::from_plan`, `to_json`, `from_json`, `plan`, `resolve`, `replay`. The guard compares **all cells, headers, row/header order and ordered key selection**, including data unrelated to conflicts. It accepts CSV quote style, LF/CRLF and BOM changes after parsing. Row/header reordering requires a new review, even though merge identity itself is order-independent.

Format `mntablemerge/review-1` has exactly six fields: format/base/ours/theirs/key/decisions. Snapshots are canonical CSV strings. Unknown fields/versions, duplicate JSON keys, wrong types, invalid snapshots/identities, irrelevant/duplicate decisions and nesting beyond 64 are rejected. Import/export is limited to 16,000,000 UTF-16 code units including escaped envelope content; export refuses oversized bundles. Returned JSON may be edited; importing revalidates it.

The bundle **does not authenticate the reviewer or detect deliberate alteration of the bundle itself**. It binds replay to its supplied snapshots. Treat files as copies of their input data. Signatures, compact hashed bundles and encryption are not implemented.

The offline helper uses pinned OurAirports fixtures, completes a missing intersection, verifies expected CSV, rejects changed input and checks byte-for-byte input preservation. It requires no network/private infrastructure.
