///|
/// A source order is an explicit output preference, not a merge of row moves.
/// Surviving rows missing from that source are appended in lexical key order.
pub(all) enum RowOrder {
  Lexical
  BaseOrder
  OursOrder
  TheirsOrder
} derive(Eq, Debug)

///|
pub extend RowOrder with Eq::{equal, not_equal}

///|
pub extend RowOrder with @debug.Debug::{to_repr}

///|
pub fn RowOrder::parse(value : String) -> RowOrder raise MergeError {
  match value {
    "lexical" => Lexical
    "base" => BaseOrder
    "ours" => OursOrder
    "theirs" => TheirsOrder
    _ => raise InvalidOrder("use lexical/base/ours/theirs; got '\{value}'")
  }
}

///|
pub fn RowOrder::name(self : RowOrder) -> String {
  match self {
    Lexical => "lexical"
    BaseOrder => "base"
    OursOrder => "ours"
    TheirsOrder => "theirs"
  }
}

///|
pub fn MergePlan::row_order(self : MergePlan) -> RowOrder {
  self.ordering
}

///|
fn order_rows(
  ids : Array[(String, RowKey)],
  ordering : RowOrder,
  base : Indexed,
  ours : Indexed,
  theirs : Indexed,
) -> Unit {
  let source = match ordering {
    Lexical => return
    BaseOrder => base
    OursOrder => ours
    TheirsOrder => theirs
  }
  // The identity map is populated in physical row order by index_table.
  let positions : Map[String, Int] = Map([])
  for i, (token, _) in source.identities.to_array() {
    positions[token] = i
  }
  ids.sort_by((a, b) => {
    match (positions.get(a.0), positions.get(b.0)) {
      (Some(x), Some(y)) => x.compare(y)
      (Some(_), None) => -1
      (None, Some(_)) => 1
      (None, None) => key_compare(a.1, b.1)
    }
  })
}
