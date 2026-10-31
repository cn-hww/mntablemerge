///|
/// A named exact-string unique tuple, in output column coordinates.
pub struct UniqueRule {
  priv label : String
  priv fields : Array[String]
} derive(Eq, Debug)

///|
pub fn UniqueRule::UniqueRule(
  name : String,
  columns : Array[String],
) -> UniqueRule {
  { label: name, fields: columns.copy(), }
}

///|
pub fn UniqueRule::name(self : UniqueRule) -> String {
  self.label
}

///|
pub fn UniqueRule::columns(self : UniqueRule) -> Array[String] {
  self.fields.copy()
}

///|
/// Full affected records in output coordinates; absence is an empty source array.
pub(all) struct UniqueConflict {
  rule : String
  columns : Array[String]
  values : Array[String]
  rows : Array[RowKey]
  base : Array[CellValue]
  ours : Array[CellValue]
  theirs : Array[CellValue]
  merged : Array[CellValue]
} derive(Eq, Debug)

///|
/// A separate policy-bound phase. Existing ordinary review formats are unchanged.
pub struct UniqueReview {
  priv review : ReviewBundle
  priv rules_data : Array[UniqueRule]
  priv repair_data : Array[Decision]
  priv ordinary : MergePlan
  priv initial : Table?
  priv candidate : Table?
  priv pending_unique : Array[UniqueConflict]
  priv sources : Array[Indexed]
  priv outputs : Array[Indexed]
}

///|
pub extend UniqueRule with Eq::{equal, not_equal}

///|
pub extend UniqueRule with @debug.Debug::{to_repr}

///|
pub extend UniqueConflict with Eq::{equal, not_equal}

///|
pub extend UniqueConflict with @debug.Debug::{to_repr}

///|
fn canonical_rules(
  rules : Array[UniqueRule],
) -> Array[UniqueRule] raise MergeError {
  if rules.is_empty() || rules.length() > 64 {
    raise InvalidReview("uniqueness requires 1..64 named rules")
  }
  let names : Map[String, Bool] = Map([])
  let sets : Map[String, Bool] = Map([])
  let mut count = 0
  let mut chars = 0
  for rule in rules {
    validate_unicode(rule.label)
    if rule.label.is_empty() || names.contains(rule.label) {
      raise InvalidReview("unique rule names must be nonempty and distinct")
    }
    names[rule.label] = true
    if rule.fields.is_empty() {
      raise InvalidReview("unique rule '\{rule.label}' requires columns")
    }
    if rule.fields.length() > max_columns - count {
      raise LimitExceeded("unique rules exceed 512 total column references")
    }
    count += rule.fields.length()
    let columns : Map[String, Bool] = Map([])
    for name in rule.fields {
      validate_unicode(name)
      if name.is_empty() || columns.contains(name) {
        raise InvalidReview("unique rule columns must be nonempty and distinct")
      }
      columns[name] = true
      if name.length() > max_chars - chars {
        raise LimitExceeded("unique rule text exceeds 16000000 UTF-16 units")
      }
      chars += name.length()
    }
    if rule.label.length() > max_chars - chars {
      raise LimitExceeded("unique rule text exceeds 16000000 UTF-16 units")
    }
    chars += rule.label.length()
    let ordered = rule.fields.copy()
    ordered.sort_by(lexical_string)
    let token = RowKey(ordered).token()
    if sets.contains(token) {
      raise InvalidReview("duplicate unique column set; declare it once")
    }
    sets[token] = true
  }
  let out = rules.copy()
  out.sort_by((a, b) => lexical_string(a.label, b.label))
  out
}

///|
pub fn unique_rules_json(rules : Array[UniqueRule]) -> Json raise MergeError {
  let value = Json::array(
    canonical_rules(rules).map(r => {
      (
        { "name": r.label, "columns": Json::array(r.fields.map(Json::string)) } :
        Json)
    }),
  )
  if value.stringify().length() > max_chars {
    raise LimitExceeded("unique rule JSON exceeds 16000000 UTF-16 units")
  }
  value
}

///|
pub fn parse_unique_rules(
  source : String,
) -> Array[UniqueRule] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidReview("unique rules must be a JSON array")
  }
  if items.length() > 64 {
    raise LimitExceeded("at most 64 unique rules")
  }
  canonical_rules(
    items.map(item => {
      guard item is Object(fields) &&
        fields.length() == 2 &&
        fields.get("name") is Some(String(name)) &&
        fields.get("columns") is Some(Array(columns)) else {
        raise InvalidReview("unique rule requires exactly name and columns")
      }
      UniqueRule(
        name,
        columns.map(c => {
          match c {
            String(s) => s
            _ => raise InvalidReview("unique rule columns must be strings")
          }
        }),
      )
    }),
  )
}

///|
fn unique_source(
  review : ReviewBundle,
  table : Table,
  side : String,
) -> Indexed raise MergeError {
  let aligned = if !review.evolution.is_empty() {
    let evolution = review.evolution.copy()
    for c in review.lineage {
      evolution.push({
        base: c.base,
        ours: Some(c.ours),
        theirs: Some(c.theirs),
        output: c.output,
      })
    }
    evolved_table(table, evolution, side)
  } else if !review.lineage.is_empty() {
    aligned_table(table, review.lineage, side)
  } else {
    table
  }
  index_table(
    aligned_rows(aligned, review.keys, review.rows, side),
    review.keys,
    side,
  )
}

///|
fn unique_tuple(table : Indexed, key : RowKey, rule : UniqueRule) -> RowKey {
  let row = table.rows[key.token()]
  RowKey(rule.fields.map(name => row[table.columns[name]]))
}

///|
fn unique_groups(
  table : Indexed,
  rule : UniqueRule,
) -> Array[(RowKey, Array[RowKey])] raise MergeError {
  for name in rule.fields {
    if !table.columns.contains(name) {
      raise InvalidReview(
        "unique rule '\{rule.label}' lacks column '\{name}'; restore it or start a review with revised rules",
      )
    }
  }
  let groups : Map[String, (RowKey, Array[RowKey])] = Map([])
  for _, key in table.identities {
    let values = unique_tuple(table, key, rule)
    let token = values.token()
    match groups.get(token) {
      Some((_, rows)) => rows.push(key)
      None => groups[token] = (values, [key])
    }
  }
  let duplicates = groups
    .values()
    .filter(group => group.1.length() > 1)
    .to_array()
  for (_, rows) in duplicates {
    rows.sort_by(key_compare)
  }
  duplicates.sort_by((a, b) => key_compare(a.0, b.0))
  duplicates
}

///|
fn unique_row_values(table : Indexed, rows : Array[RowKey]) -> Array[CellValue] {
  let values = []
  for key in rows {
    if table.rows.get(key.token()) is Some(row) {
      for i, name in table.source.columns {
        values.push({ key, column: name, value: row[i], })
      }
    }
  }
  values
}

///|
fn unique_conflicts(
  table : Indexed,
  sources : Array[Indexed],
  rules : Array[UniqueRule],
) -> Array[UniqueConflict] raise MergeError {
  let planned = []
  let mut count = 0
  for rule in rules {
    for (values, rows) in unique_groups(table, rule) {
      for source in [sources[0], sources[1], sources[2], table] {
        for row in rows {
          if source.rows.contains(row.token()) {
            count += source.source.columns.length()
          }
        }
      }
      if count > max_cells {
        raise LimitExceeded(
          "complete unique-conflict evidence exceeds 2000000 cells; reduce the review scope",
        )
      }
      planned.push((rule, values, rows))
    }
  }
  // Check the entire evidence budget before materializing any full records.
  planned.map(item => {
    let (rule, values, rows) = item
    {
      rule: rule.label,
      columns: rule.fields.copy(),
      values: values.components(),
      rows: rows.copy(),
      base: unique_row_values(sources[0], rows),
      ours: unique_row_values(sources[1], rows),
      theirs: unique_row_values(sources[2], rows),
      merged: unique_row_values(table, rows),
    }
  })
}

///|
fn copy_unique(c : UniqueConflict) -> UniqueConflict {
  {
    ..c,
    columns: c.columns.copy(),
    values: c.values.copy(),
    rows: c.rows.copy(),
    base: c.base.copy(),
    ours: c.ours.copy(),
    theirs: c.theirs.copy(),
    merged: c.merged.copy(),
  }
}
