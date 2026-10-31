# Public API adoption contract

The generated `pkg.generated.mbti` is the complete public signature reference.
Version 0.1.0 has a pre-1.0 API. The following is the supported adoption
path; it is covered by an independent packaged-source consumer in CI.

1. Create a `Table` using `parse_csv`, `parse_tsv` or `Table::from_rows`.
   Values are exact Unicode strings. Constructors/accessors copy mutable arrays.
2. Call `merge(base, ours, theirs, key=[...])`. Keys identify records; physical
   order does not. Optional ordering and explicit lineage remain caller choices.
3. Inspect `MergePlan::conflicts` / `report`. Resolve only reported conflicts with
   typed `Decision` values or strict `parse_decisions`. Structure precedes cells;
   a decision can expose another round. Errors preserve the earlier plan.
4. For offline work, use `ReviewBundle::from_plan`, `to_json`, `from_json`,
   `resolve` and `replay`. Replay binds exact original tables, ordered keys and
   policies. Bundles are revision guards, not reviewer authentication.
5. Call `finish` only after all conflicts are resolved, then `table` and
   `to_csv` / `to_tsv`. Incomplete plans cannot yield partial output.

`RowKey::RowKey` owns a copy of its components. `Target`, `ConflictKind`,
`Choice`, `Decision`, `ColumnLineage` and `RowLineage` have public constructors
or fields as shown in the generated interface. Consumers may match them and
handle `MergeError`; `diagnostic()` provides repair-oriented text. Error prose
is not a machine-readable stability guarantee. Unknown choices, fields, mapping
sources and unsupported transformations are rejected rather than ignored.

Existing public struct fields will not be silently changed to optional values
to add a new capability. Additive APIs must retain the old source workflow;
intentional breaking changes require an explicit version/changelog entry.
Pre-1.0 does not imply that undocumented breaking changes are acceptable.

Existing wire formats must keep their semantics. New policies require explicit
versioned formats; older readers should reject them rather than discard data.
Older valid bundles remain importable. Default ordering and CSV bytes remain
unchanged unless a documented compatibility change is deliberately introduced.

Advanced review sheets, assignments, combination, revision and audit are public
APIs too; their detailed contracts are linked from the README. The minimal
adoption path does not require applications to implement those workflows.

Declared secondary [uniqueness](uniqueness.md) uses the additive `UniqueReview`
wrapper. Its `finish` is the constraint-aware export gate; ordinary merge alone
has no caller-declared secondary constraints. Unique repairs have their own
namespace and versioned envelope and cannot be sent to ordinary resolve/sheet/
combine APIs. Ordinary `Target`/`Choice` variants remain source compatible.

The pure library runs without host file/process APIs. The file CLI has a
separate platform contract; native pure-library execution does not imply that
Windows native async CLI execution is supported. No performance or workload
scale guarantee follows from configured size limits.
