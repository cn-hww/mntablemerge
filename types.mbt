///|
/// A validated rectangular table. Constructors and accessors copy their arrays.
pub struct Table {
  priv columns : Array[String]
  priv records : Array[Array[String]]
} derive(Eq, Debug)

///|
/// A compound row identity. Components are never joined with a user delimiter.
pub struct RowKey {
  priv parts : Array[String]
} derive(Eq, Debug)

///|
/// Conflict coordinates are independent of input row and column ordering.
pub(all) enum Target {
  Column(String)
  Row(RowKey)
  Cell(RowKey, String)
} derive(Eq, Debug)

///|
pub(all) enum ConflictKind {
  ColumnDeleteEdit
  RowDeleteEdit
  ConcurrentInsert
  CellEdit
  MissingCell
} derive(Eq, Debug)

///|
/// A source value, including its row identity and column name.
pub(all) struct CellValue {
  key : RowKey
  column : String
  value : String
} derive(Eq, Debug)

///|
/// Empty source arrays mean absence; an empty string is an actual stored value.
pub(all) struct Conflict {
  target : Target
  kind : ConflictKind
  base : Array[CellValue]
  ours : Array[CellValue]
  theirs : Array[CellValue]
} derive(Eq, Debug)

///|
/// Keep/Drop resolve deletion conflicts; Ours/Theirs select inserted rows.
/// Base/Ours/Theirs/Value resolve cells. Unsupported combinations are errors.
pub(all) enum Choice {
  Keep
  Drop
  Base
  Ours
  Theirs
  Value(String)
} derive(Eq, Debug)

///|
pub(all) struct Decision {
  target : Target
  choice : Choice
} derive(Eq, Debug)

///|
/// Evidence for an explicit resolution, including original source values.
pub(all) struct Resolution {
  conflict : Conflict
  choice : Choice
} derive(Eq, Debug)

///|
/// Owns immutable input snapshots and cumulative decisions.
pub struct MergePlan {
  priv base : Table
  priv ours : Table
  priv theirs : Table
  priv key_columns : Array[String]
  priv ordering : RowOrder
  priv lineage_data : Array[ColumnLineage]
  priv row_lineage_data : Array[RowLineage]
  priv decisions_data : Array[Decision]
  priv pending : Array[Conflict]
  priv evidence : Array[Resolution]
  priv output : Table?
}

///|
/// Available only after all conflicts have been resolved.
pub struct MergedTable {
  priv result : Table
  priv evidence : Array[Resolution]
}

///|
/// Diagnostics include locations and corrective actions, not partial output.
pub(all) suberror MergeError {
  InvalidTable(String)
  InvalidKey(String)
  InvalidCsv(record~ : Int, column~ : Int, reason~ : String)
  LimitExceeded(String)
  InvalidDecision(String)
  Unresolved(Int)
  InvalidReview(String)
  InvalidOrder(String)
  InvalidLineage(String)
} derive(Debug)

///|
pub fn RowKey::RowKey(parts : Array[String]) -> RowKey {
  { parts: parts.copy(), }
}

///|
pub fn RowKey::components(self : RowKey) -> Array[String] {
  self.parts.copy()
}

///|
pub fn MergeError::diagnostic(self : MergeError) -> String {
  match self {
    InvalidTable(reason) => "InvalidTable: \{reason}"
    InvalidKey(reason) => "InvalidKey: \{reason}"
    InvalidCsv(record~, column~, reason~) =>
      "InvalidCsv: record \{record}, field \{column}: \{reason}"
    LimitExceeded(reason) => "LimitExceeded: \{reason}; reduce the table size"
    InvalidDecision(reason) => "InvalidDecision: \{reason}"
    Unresolved(count) =>
      "Unresolved: \{count} conflict(s); inspect the report and supply explicit decisions"
    InvalidReview(reason) => "InvalidReview: \{reason}"
    InvalidOrder(reason) => "InvalidOrder: \{reason}"
    InvalidLineage(reason) => "InvalidLineage: \{reason}"
  }
}

///|
pub extend Table with Eq::{equal, not_equal}

///|
pub extend Table with @debug.Debug::{to_repr}

///|
pub extend RowKey with Eq::{equal, not_equal}

///|
pub extend RowKey with @debug.Debug::{to_repr}

///|
pub extend Target with Eq::{equal, not_equal}

///|
pub extend Target with @debug.Debug::{to_repr}

///|
pub extend ConflictKind with Eq::{equal, not_equal}

///|
pub extend ConflictKind with @debug.Debug::{to_repr}

///|
pub extend CellValue with Eq::{equal, not_equal}

///|
pub extend CellValue with @debug.Debug::{to_repr}

///|
pub extend Conflict with Eq::{equal, not_equal}

///|
pub extend Conflict with @debug.Debug::{to_repr}

///|
pub extend Choice with Eq::{equal, not_equal}

///|
pub extend Choice with @debug.Debug::{to_repr}

///|
pub extend Decision with Eq::{equal, not_equal}

///|
pub extend Decision with @debug.Debug::{to_repr}

///|
pub extend Resolution with Eq::{equal, not_equal}

///|
pub extend Resolution with @debug.Debug::{to_repr}

///|
pub extend MergeError with @debug.Debug::{to_repr}
