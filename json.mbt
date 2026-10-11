///|
/// Stable review coordinates. Key components remain an array.
pub fn Target::to_json(self : Target) -> Json {
  match self {
    Column(name) => { "column": name }
    Row(key) => { "row": Json::array(key.parts.map(Json::string)) }
    Cell(key, name) =>
      { "row": Json::array(key.parts.map(Json::string)), "column": name }
  }
}

///|
fn Choice::to_json(self : Choice) -> Json {
  match self {
    Keep => "keep"
    Drop => "drop"
    Base => "base"
    Ours => "ours"
    Theirs => "theirs"
    Value(value) => { "value": value }
  }
}

///|
fn values_json(values : Array[CellValue]) -> Json {
  Json::array(
    values.map(v => {
      "row": Json::array(v.key.parts.map(Json::string)),
      "column": v.column,
      "value": v.value,
    }),
  )
}

///|
fn Conflict::to_json(self : Conflict) -> Json {
  let kind = match self.kind {
    ColumnDeleteEdit => "ColumnDeleteEdit"
    RowDeleteEdit => "RowDeleteEdit"
    ConcurrentInsert => "ConcurrentInsert"
    CellEdit => "CellEdit"
    MissingCell => "MissingCell"
  }
  let hint = match self.kind {
    ColumnDeleteEdit | RowDeleteEdit =>
      "Choose keep/drop for the whole structure; inspect all affected source values."
    ConcurrentInsert => "Choose ours/theirs/drop for the entire inserted row."
    CellEdit => "Choose base/ours/theirs or supply {value: string}."
    MissingCell =>
      "This intersection has no selected source value; supply a value or explicitly choose an available source."
  }
  {
    "target": self.target.to_json(),
    "kind": kind,
    "base": values_json(self.base),
    "ours": values_json(self.ours),
    "theirs": values_json(self.theirs),
    "hint": hint,
  }
}

///|
/// JSON audit report; incomplete plans contain no candidate CSV output.
pub fn MergePlan::report(self : MergePlan) -> Json {
  let report : Json = {
    "format": "mntablemerge/report-1",
    "complete": self.output != None,
    "conflicts": Json::array(self.pending.map(c => c.to_json())),
    "decisions": decisions_json(self.decisions_data),
    "resolutions": Json::array(
      self.evidence.map(r => {
        "conflict": r.conflict.to_json(),
        "choice": r.choice.to_json(),
      }),
    ),
  }
  if !self.lineage_data.is_empty() {
    guard report is Object(fields) else { abort("object literal") }
    fields["format"] = "mntablemerge/report-2"
    fields["column_lineage"] = lineage_json(self.lineage_data)
    fields["row_order"] = Json::string(self.ordering.name())
  }
  report
}

///|
pub fn decisions_json(decisions : Array[Decision]) -> Json {
  Json::array(
    decisions.map(d => {
      "target": d.target.to_json(),
      "choice": d.choice.to_json(),
    }),
  )
}

///|
/// Unknown fields and non-string values are rejected instead of ignored.
pub fn parse_decisions(source : String) -> Array[Decision] raise MergeError {
  if source.length() > max_chars {
    raise LimitExceeded("decision JSON is too large")
  }
  let value = checked_json(source)
  guard value is Array(items) else {
    raise InvalidDecision("expected a JSON array")
  }
  if items.length() > max_cells {
    raise LimitExceeded("too many decisions")
  }
  items.map(item => {
    guard item is Object(fields) else {
      raise InvalidDecision("each decision must be an object")
    }
    guard fields.length() == 2 &&
      fields.get("target") is Some(target) &&
      fields.get("choice") is Some(choice) else {
      raise InvalidDecision(
        "each decision must have exactly target and choice fields",
      )
    }
    let target = parse_target(target)
    let choice = match choice {
      String("keep") => Keep
      String("drop") => Drop
      String("base") => Base
      String("ours") => Ours
      String("theirs") => Theirs
      Object(fields) => {
        guard fields.length() == 1 && fields.get("value") is Some(String(value)) else {
          raise InvalidDecision("custom choice must be exactly {value: string}")
        }
        Value(value)
      }
      _ =>
        raise InvalidDecision(
          "unknown choice; use keep/drop/base/ours/theirs or {value: string}",
        )
    }
    Decision::{ target, choice, }
  })
}

///|
fn parse_target(value : Json) -> Target raise MergeError {
  guard value is Object(fields) else {
    raise InvalidDecision("target must be an object")
  }
  let key = match fields.get("row") {
    None => None
    Some(Array(parts)) => {
      if parts.is_empty() {
        raise InvalidDecision("row key must contain components")
      }
      Some(
        RowKey(
          parts.map(p => {
            match p {
              String(s) => s
              _ => raise InvalidDecision("row key components must be strings")
            }
          }),
        ),
      )
    }
    _ => raise InvalidDecision("row must be an array of key strings")
  }
  let column = match fields.get("column") {
    None => None
    Some(String(name)) => Some(name)
    _ => raise InvalidDecision("column must be a string")
  }
  match (key, column, fields.length()) {
    (None, Some(name), 1) => Column(name)
    (Some(key), None, 1) => Row(key)
    (Some(key), Some(name), 2) => Cell(key, name)
    _ => raise InvalidDecision("target requires only row and/or column fields")
  }
}
