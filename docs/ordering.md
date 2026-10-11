# Output row order

Use this when a catalog is deliberately grouped or hand ordered: preserving its row positions avoids unrelated changes in a Git diff. Order does not establish row identity or choose cell values.

`merge(..., key=["id"], row_order=BaseOrder)` preserves surviving base rows in their original sequence. `OursOrder` and `TheirsOrder` select the corresponding source sequence. Every surviving row absent from the preferred source is appended in lexicographic compound-key order. Deleted rows stay deleted. An empty preferred source appends all surviving rows lexically. Column ordering remains unchanged.

The default `Lexical` retains the existing output. This is an explicit preference, not inference or reconciliation of competing row moves. UTF-16 code-unit lexical order is deterministic and case sensitive, not numeric or locale order.

```text
moon run cmd/main -- merge examples/airports/base.csv examples/airports/ours.csv examples/airports/theirs.csv --key id --row-order base
moon run scripts/order-demo.mbtx
```

The offline OurAirports example checks all merged values against `order-expected.csv`, retaining original IDs `6523,323361` instead of sorting them. The data source/license and simulated edits are the same as the original example. The helper also exports a review and replays its exact policy, then verifies override rejection.

`merge`, `review`, and `git-driver` accept `--row-order lexical|base|ours|theirs`. For example, append `--row-order ours` to the configured Git driver's command. `replay` rejects this flag because the bundle owns the policy; regenerate review to change it. Invalid or duplicate options fail without output or input writes.

Non-default ordering uses strict `mntablemerge/review-2` with the seventh field `row_order`. Legacy six-field `review-1` remains supported, and default plans still export that exact envelope. Unknown order values or envelope fields are rejected. Cumulative resolutions retain the selected policy. The bundle is a revision guard, not a signature.
