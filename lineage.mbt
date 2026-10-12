///|
/// Declares the same retained logical column across three source schemas.
/// All source names must exist. Output names are used for keys and decisions.
/// This is explicit intent, never a guess based on similar headers or values.
pub(all) struct ColumnLineage {
  base : String
  ours : String
  theirs : String
  output : String
} derive(Eq, Debug)

///|
pub extend ColumnLineage with Eq::{equal, not_equal}

///|
pub extend ColumnLineage with @debug.Debug::{to_repr}

///|
pub fn MergePlan::column_lineage(self : MergePlan) -> Array[ColumnLineage] {
  self.lineage_data.copy()
}

///|
/// Refuses invalid Unicode/oversized export; every emitted declaration array
/// can be parsed back without losing text. Merge checks schema semantics.
pub fn column_lineage_json(
  lineage : Array[ColumnLineage],
) -> Json raise MergeError {
  if lineage.length() > max_columns {
    raise LimitExceeded("column lineage exceeds 512 entries")
  }
  let mut total = 0
  for c in lineage {
    for name in [c.base, c.ours, c.theirs, c.output] {
      validate_unicode(name)
      if name.length() > max_chars - total {
        raise LimitExceeded(
          "column lineage text exceeds 16000000 UTF-16 code units",
        )
      }
      total += name.length()
    }
  }
  let value = lineage_json(lineage)
  if value.stringify().length() > max_chars {
    raise LimitExceeded(
      "column lineage JSON exceeds 16000000 UTF-16 code units",
    )
  }
  value
}

///|
// Internal plans already contain validated strings; report has no export cap,
// and the review serializer checks the size of its complete envelope.
fn lineage_json(lineage : Array[ColumnLineage]) -> Json {
  Json::array(
    lineage.map(c => {
      "base": c.base,
      "ours": c.ours,
      "theirs": c.theirs,
      "output": c.output,
    }),
  )
}

///|
/// Rejects unknown fields/types. Source existence and collisions are checked
/// against all three tables by merge, before any values can be exported.
pub fn parse_column_lineage(
  source : String,
) -> Array[ColumnLineage] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidLineage("expected an array of base/ours/theirs/output objects")
  }
  if items.length() > max_columns {
    raise LimitExceeded("column lineage exceeds 512 entries")
  }
  items.map(item => {
    guard item is Object(fields) &&
      fields.length() == 4 &&
      fields.get("base") is Some(String(base)) &&
      fields.get("ours") is Some(String(ours)) &&
      fields.get("theirs") is Some(String(theirs)) &&
      fields.get("output") is Some(String(output)) else {
      raise InvalidLineage(
        "each column requires exactly four string fields: base/ours/theirs/output",
      )
    }
    ColumnLineage::{ base, ours, theirs, output, }
  })
}

///|
fn aligned_table(
  table : Table,
  lineage : Array[ColumnLineage],
  side : String,
) -> Table raise MergeError {
  let mappings : Map[String, String] = Map([])
  let outputs : Map[String, Bool] = Map([])
  for c in lineage {
    let source = match side {
      "base" => c.base
      "ours" => c.ours
      _ => c.theirs
    }
    validate_unicode(source)
    validate_unicode(c.output)
    if source.is_empty() || c.output.is_empty() {
      raise InvalidLineage("\{side}: source and output names must be nonempty")
    }
    if !table.columns.contains(source) {
      raise InvalidLineage(
        "\{side} lacks declared column '\{source}'; correct the mapping or remove it and review deletion normally",
      )
    }
    if mappings.contains(source) || outputs.contains(c.output) {
      raise InvalidLineage(
        "\{side}: source and output columns must each occur once; split/combined columns are unsupported",
      )
    }
    mappings[source] = c.output
    outputs[c.output] = true
  }
  let columns = table.columns.map(name => mappings.get(name).unwrap_or(name))
  let seen : Map[String, Bool] = Map([])
  for column in columns {
    if seen.contains(column) {
      raise InvalidLineage(
        "\{side}: output column '\{column}' collides with another column; choose a distinct output or declare both lineages",
      )
    }
    seen[column] = true
  }
  // Simultaneous header mapping leaves every cell and its physical position
  // untouched. The validating constructor checks size/Unicode after expansion.
  Table::from_rows(columns, table.records)
}

///|
fn calculate(
  base : Table,
  ours : Table,
  theirs : Table,
  keys : Array[String],
  decisions : Array[Decision],
  ordering : RowOrder,
  lineage? : Array[ColumnLineage] = [],
  rows? : Array[RowLineage] = [],
) -> MergePlan raise MergeError {
  if lineage.length() > max_columns {
    raise LimitExceeded("column lineage exceeds 512 entries")
  }
  let b = if lineage.is_empty() {
    base
  } else {
    aligned_table(base, lineage, "base")
  }
  let o = if lineage.is_empty() {
    ours
  } else {
    aligned_table(ours, lineage, "ours")
  }
  let t = if lineage.is_empty() {
    theirs
  } else {
    aligned_table(theirs, lineage, "theirs")
  }
  let plan = calculate_normalized(
    aligned_rows(b, keys, rows, "base"),
    aligned_rows(o, keys, rows, "ours"),
    aligned_rows(t, keys, rows, "theirs"),
    keys,
    decisions,
    ordering,
  )
  // Review/replay owns original inputs, rather than only transformed snapshots.
  {
    ..plan,
    base,
    ours,
    theirs,
    lineage_data: lineage.copy(),
    row_lineage_data: rows.copy(),
  }
}
