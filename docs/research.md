# Scope and demand research

Snapshot: 2026-10-11. This documents the selected project's boundary, not proof that no competitor exists. Sources: Mooncakes registry/readmes/generated APIs, GitHub source/readmes, official stable MoonBit documentation and Python package statistics. Search terms included `MoonBit CSV merge`, `MoonBit table three-way merge`, `MoonBit reconcile`, `csvdiff`, `diff3`, `table_diff_by_key`, `compare_csv`, `apply_decisions`, `JSON merge`, and `delete column conflict`.

## Adjacent MoonBit capabilities

| Project/source | Public boundary inspected | License / recent evidence | Relationship |
|---|---|---|---|
| [moonconfig 0.2.0](https://mooncakes.io/docs/forey217/moonconfig@0.2.0), [GitHub](https://github.com/forey217/moonconfig) | `merge`, `merge_json`, `resolve`, `guarded_diff`, `apply`: JSON configuration three-way review/guarded patch replay; arrays treated atomically | MIT; registry publication 2026-10-02 | Strong overlap with a fixed-schema CSV→JSON cell merge. That initial boundary was rejected. It does not establish rectangular row/column lifecycle invariants. |
| [MoonRow](https://mooncakes.io/docs/JingLan0v0/moonrow@0.1.0), [GitHub](https://github.com/JingLan0v0/MoonBit) | `compare(before,after,options)`, `compare_csv`, `parse_csv`, JSON/text reports; two snapshots, exact/compound keys, schema equality except ignored columns | Apache-2.0; Mooncakes 0.1.0 visible, recent listing activity in October 2026 | Shared keyed identity and CSV groundwork; no ancestor/ours/theirs structural resolution workflow in inspected API. |
| [mbitsv](https://mooncakes.io/docs/CJR-zhang/mbitsv@0.1.0), [GitHub](https://github.com/CJR-zhang/mbitsv) | Delimited-text parsing/quality tooling and `table_diff_by_key` two-table comparison | MIT; registry 0.1.0 dated 2026-08-20 | Parsing/diff overlap, not a complete structural three-way merge contract. |
| [MoonFrame](https://github.com/ihb2032/MoonFrame) | DataFrame operations, filtering, joins and CSV data analysis | Apache-2.0; registry 0.7.0 dated 2026-10-02 | Relational joins align two datasets; they do not encode branch ancestry or destructive merge intent. |
| [bit_diff3 / bit-vcs](https://github.com/mizchi/bit-vcs), [registry](https://mooncakes.io/docs/mizchi/bit_diff3@0.48.0) | `content_merge`: text three-way merge primitives | Apache-2.0; registry 0.48.0 dated 2026-09-21 | Generic text merge loses keyed table identity and independently changed cells on the same CSV line. |

Publication dates/listing activity are maintenance signals, not evidence of production adoption or sustained support. This is a limited API/source inspection, not an exhaustive audit of every unpublished branch. Repository names, packages and APIs can change; rerun these searches before substantially expanding scope. Other reconciliation tools may cover matching/reports without using the same vocabulary. Failure to find a package is not evidence of absence.

## Independent value and overlap decision

**Independent value:** merge concurrently edited keyed tables while making whole-row/whole-column deletion conflicts and undefined row×column intersections explicit, producing only validated complete tables with source evidence.

JSON merge's generic `merge/resolve` shape is established and deliberately not claimed as novel. The differentiating work is the two-dimensional domain contract: column removal versus any value/new row on that column; row removal versus any value/new column on that row; atomic selection of conflicting insertions; unknown intersections distinct from empty strings; compound-key identity; final rectangularity/uniqueness checks. A CSV wrapper over JSON alone would not supply these rules. Our first milestone implements them, rather than deferring differentiation to future features.

## Other-language demand evidence

- [daff](https://github.com/paulfitz/daff), MIT, includes tabular comparison/merge workflows and Python distribution. The research snapshot observed 929 GitHub stars and 76 forks. [PyPI daff](https://pypi.org/project/daff/) version 1.4.2, released 2025-05-04. [PyPIStats](https://pypistats.org/packages/daff) snapshot: 16,721,647 downloads/month, 4,344,255/week, 394,652/day. These are package installations, **not unique users or merge operations**; [dbt-core's dependency](https://github.com/dbt-labs/dbt-core/blob/1.10.latest/core/setup.py) explains substantial indirect installs.
- [csv-diff](https://github.com/simonw/csv-diff), Apache-2.0, supplies keyed CSV comparison and JSON reports in Python. [PyPIStats](https://pypistats.org/packages/csv-diff): 76,693/month, 27,325/week, 2,929/day at the snapshot. Useful evidence for recurring keyed-table change inspection, not direct evidence for three-way structural merge demand.
- [csvdiff3](https://github.com/sctweedie/csvdiff3), MIT, explicitly supports CSV three-way diff/merge and Git-driver use. Snapshot 10 stars / 4 forks. Its README accepts column deletion despite changes on the retained side, so its structural policy differs from this project's explicit review. This narrow workflow has weaker direct popularity evidence; no download count was established.

An earlier isolated Python daff experiment merged independent price/stock edits on one synthetic record, while ordinary `git merge-file` conflicted on that CSV line. It demonstrates functional value, not a benchmark. No third-party implementation or fixture was copied into the merge engine.

The broad table-change workflow is established and useful beyond a niche MoonBit demo. Demand for this stricter structural policy specifically remains medium-confidence until downstream developers adopt it. No popularity number is presented as evidence of MoonBit adoption.

## Selection judgment

Prior candidate investigation included localization-catalog auditing and SARIF baseline workflows. Their existing format/runtime and reporting overlap required tighter boundaries. The selected table capability scored best on a 1–5 qualitative scale: user value 4, differentiation 4 **after structural narrowing**, technical depth 4, feasibility 4, portability 5, demonstration 5, maintenance affordability 4. The evidence above supports that judgment; it is not market research or a uniqueness claim. The explicit structural slice is independently useful now, and input-bound review/Git integration extend the same contract rather than creating unrelated features.

Toolchain sources: [stable module configuration](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html), [package configuration](https://docs.moonbitlang.com/en/stable/toolchain/moon/package.html), [v0.10.14 release](https://www.moonbitlang.com/updates/2026/09/21/index).

## Ordering and explicit lineage extension

Rechecked Mooncakes' MoonRow 0.1.0 and moonconfig 0.2.0 public boundaries on 2026-10-11 before this extension. Searches also included `MoonBit column rename merge`, `MoonBit table schema lineage`, `moonrow merge rename`, and `daff column rename merge CSV`. The inspected MoonRow boundary remains two-snapshot comparison with matching non-ignored schemas; moonconfig remains JSON configuration merge/review. This extension stays inside structural three-way table reconciliation, rather than introducing a general rename/filter/diff API. Unpublished implementations and alternate terminology remain uncertain.

Search also found [MoonFrame's `Series::rename`](https://mooncakes.io/assets/ihb2032/MoonFrame%400.5.1/series/series.mbt.html), in indexed 0.5.1 source: it returns a series with a new name and shared storage. That single-source operation is established overlap and is not claimed as new here. Our public addition declares correspondence across three schemas, preserves original review snapshots and applies the existing structural/cell conflict rules; it does not expose a general table/series rename utility.

[daff's tabular diff specification](https://paulfitz.github.io/daff-doc/spec.html) explicitly represents column rename and discusses respecting row order in CSV/spreadsheet workflows. This is evidence that these concerns occur in established table tooling, not a claim that our explicit mapping policy is novel or that demand counts measure this particular feature. The implementation/tests here were independently authored; no daff code or fixtures were incorporated.

## Explicit row identity extension

On 2026-10-12, rechecked [MoonRow 0.1.0](https://mooncakes.io/docs/JingLan0v0/moonrow@0.1.0) and [moonconfig 0.2.0](https://mooncakes.io/docs/forey217/moonconfig@0.2.0). Search terms: `MoonBit row key rename lineage three way table merge`, `daff csv merge row primary key changes rename`. The inspected MoonRow API still compares two snapshots; primary key changes appear as deletion/addition. The inspected moonconfig boundary remains generic JSON merge/review, not retained-record identity across three rectangular tables. Our addition is an explicit correspondence within the existing structural merge workflow, not a general entity matching library. Alternate package names, unpublished code and uninspected branches remain uncertain.

[daff](https://github.com/paulfitz/daff) already provides row matching and table merge/Git workflows. Identifier alignment is established table tooling, and no novelty or additional download/adoption claim is made for this particular policy. This implementation requires caller-declared one-to-one retained records, checks final key collisions, preserves original review inputs and uses output coordinates for decisions. It neither guesses entity equality nor bypasses ordinary structural conflicts. No external code/tests were copied; real fixture licensing remains in THIRD_PARTY.md.
