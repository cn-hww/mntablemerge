# Combining independent reviews

Multiple owners can review copies of the same baseline bundle, using [assigned sheets](scoped-review.md) or decision JSON. Combine their returned bundles without hand-merging JSON or choosing whichever file arrives last.

```text
moon run cmd/main -- review-combine BASELINE.json OWNER_A.json OWNER_B.json
moon run scripts/combine-demo.mbtx
```

Save stdout to a new `COMBINED.json` and use normal replay against the original inputs. Library: `ReviewBundle::combine(reviews) -> ReviewBundle raise MergeError`. It does not modify the baseline, input bundles or source files. Every bundle is validated and all original snapshots, ordered key selection, row order and both lineage declarations must match exactly. CSV transport formatting may differ after parsing; original semantic row/header order and policy declarations remain bound.

All baseline decisions must appear unchanged in every returned review. Missing/revoked/replaced inherited decisions fail, even if another reviewer kept them. To change an inherited choice, explicitly revise the shared baseline and restart assignments. New agreeing decisions at the same target coalesce; **different choices fail**, including different source selections that happen to yield the same text. The error identifies the coordinate. There is no automatic preferred reviewer or last-writer behavior.

Inherited decision order stays fixed; additions are sorted by their serialized JSON target using UTF-16 lexical order. Output is independent of review-file order and repeated agreeing submissions. Unreviewed conflicts remain pending. Combining reruns the complete structural/cell merge, retaining source evidence and rejecting invalid dependencies/unused choices. A structural result that exposes new cells is an unfinished valid bundle: export a fresh assignment and use that result as the next shared baseline.

CLI accepts 1–256 review files; library accepts 0–256 (zero validates and returns the baseline). The union is limited to 2,000,000 decisions, with normal table/bundle wire limits still enforced. Successful bundle output exits 0 even if incomplete; invalid input, disagreement or inheritance violations exit 2 with no partial stdout. There is no reviewer authentication, approval signature, timestamps, quorum policy or concurrent live service; caller-provided files are ordinary input-bound review data.

The offline OurAirports helper retains every existing source column, simulates two different edits to airport `6523`'s name alongside the existing missing `6524/review_owner`, and gives each conflict to a separate assignment. It combines the returned bundles, checks reversed/repeated input determinism, replays exact expected CSV, rejects a different name decision and a changed nonconflicting municipality, and retries while preserving earlier files. All changes are simulated and reuse the documented public-domain fixtures. Narrow fixture edits affect only the known name and choice/value suffix; production parsing remains general. Run with `native` on supported Linux/macOS CLI hosts.
