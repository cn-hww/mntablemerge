///|
/// One retained record's identities before, on each branch, and in the output.
/// Components follow the merge key's ordered columns after column alignment.
pub(all) struct RowLineage {
  base : RowKey
  ours : RowKey
  theirs : RowKey
  output : RowKey
} derive(Eq, Debug)

///|
pub extend RowLineage with Eq::{equal, not_equal}

///|
pub extend RowLineage with @debug.Debug::{to_repr}

///|
pub fn MergePlan::row_lineage(self : MergePlan) -> Array[RowLineage] {
  self.row_lineage_data.copy()
}

///|
fn lineage_key(key : RowKey, arity : Int) -> Unit raise MergeError {
  if key.parts.length() != arity || arity == 0 || arity > max_columns {
    raise InvalidLineage(
      "row identities require the same 1..512 components as the ordered merge key",
    )
  }
  for part in key.parts {
    validate_unicode(part)
    if part.is_empty() {
      raise InvalidLineage("row identity components must be nonempty")
    }
  }
}

///|
fn row_lineage_json_unchecked(lineage : Array[RowLineage]) -> Json {
  fn key_json(key : RowKey) -> Json {
    Json::array(key.parts.map(Json::string))
  }
  Json::array(
    lineage.map(row => {
      "base": key_json(row.base),
      "ours": key_json(row.ours),
      "theirs": key_json(row.theirs),
      "output": key_json(row.output),
    }),
  )
}

///|
/// Bounds/Unicode checks prevent producing a document that import cannot read.
pub fn row_lineage_json(lineage : Array[RowLineage]) -> Json raise MergeError {
  if lineage.length() > max_rows {
    raise LimitExceeded("row lineage exceeds 100000 entries")
  }
  let mut total = 0
  for row in lineage {
    let arity = row.base.parts.length()
    for key in [row.base, row.ours, row.theirs, row.output] {
      lineage_key(key, arity)
      for part in key.parts {
        if part.length() > max_chars - total {
          raise LimitExceeded(
            "row lineage text exceeds 16000000 UTF-16 code units",
          )
        }
        total += part.length()
      }
    }
  }
  let value = row_lineage_json_unchecked(lineage)
  if value.stringify().length() > max_chars {
    raise LimitExceeded("row lineage JSON exceeds 16000000 UTF-16 code units")
  }
  value
}

///|
pub fn parse_row_lineage(source : String) -> Array[RowLineage] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidLineage("expected a row-lineage array")
  }
  if items.length() > max_rows {
    raise LimitExceeded("row lineage exceeds 100000 entries")
  }
  fn parse_key(value : Json) -> RowKey raise MergeError {
    guard value is Array(parts) else {
      raise InvalidLineage("row lineage identities must be arrays of strings")
    }
    let key = RowKey(
      parts.map(part => {
        match part {
          String(s) => s
          _ => raise InvalidLineage("row identity components must be strings")
        }
      }),
    )
    lineage_key(key, parts.length())
    key
  }
  items.map(item => {
    guard item is Object(fields) &&
      fields.length() == 4 &&
      fields.get("base") is Some(b) &&
      fields.get("ours") is Some(o) &&
      fields.get("theirs") is Some(t) &&
      fields.get("output") is Some(out) else {
      raise InvalidLineage(
        "each row requires exactly base/ours/theirs/output identity arrays",
      )
    }
    let base = parse_key(b)
    let ours = parse_key(o)
    let theirs = parse_key(t)
    let output = parse_key(out)
    for key in [ours, theirs, output] {
      lineage_key(key, base.parts.length())
    }
    RowLineage::{ base, ours, theirs, output, }
  })
}

///|
fn aligned_rows(
  table : Table,
  keys : Array[String],
  lineage : Array[RowLineage],
  side : String,
) -> Table raise MergeError {
  if lineage.is_empty() {
    return table
  }
  if lineage.length() > max_rows {
    raise LimitExceeded("row lineage exceeds 100000 entries")
  }
  let indexed = index_table(table, keys, side)
  let mappings : Map[String, RowKey] = Map([])
  let outputs : Map[String, Bool] = Map([])
  for row in lineage {
    let source = match side {
      "base" => row.base
      "ours" => row.ours
      _ => row.theirs
    }
    lineage_key(source, keys.length())
    lineage_key(row.output, keys.length())
    let token = source.token()
    let output = row.output.token()
    if !indexed.rows.contains(token) {
      raise InvalidLineage(
        "\{side} lacks declared row \{Repr(source.parts)}; correct the mapping or review deletion normally",
      )
    }
    if mappings.contains(token) || outputs.contains(output) {
      raise InvalidLineage(
        "\{side}: each source/output identity may occur once; splitting or combining rows is unsupported",
      )
    }
    mappings[token] = row.output
    outputs[output] = true
  }
  let positions = keys.map(name => indexed.columns[name])
  let seen : Map[String, Bool] = Map([])
  let records = table.records.map(record => {
    let original = RowKey(positions.map(i => record[i]))
    let output = mappings.get(original.token()).unwrap_or(original)
    if seen.contains(output.token()) {
      raise InvalidLineage(
        "\{side}: output row \{Repr(output.parts)} collides with another row; choose a distinct output or declare both identities",
      )
    }
    seen[output.token()] = true
    let updated = record.copy()
    for n, position in positions {
      updated[position] = output.parts[n]
    }
    updated
  })
  Table::from_rows(table.columns, records)
}
