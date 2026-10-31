///|
/// An existing ancestor column, optionally absent on either branch. None means
/// declared absence, never an empty cell. A one-sided absence requires Keep/Drop.
/// Existing ColumnLineage remains the retained-in-all-three contract.
pub(all) struct ColumnEvolution {
  base : String
  ours : String?
  theirs : String?
  output : String
} derive(Eq, Debug)

///|
pub extend ColumnEvolution with Eq::{equal, not_equal}

///|
pub extend ColumnEvolution with @debug.Debug::{to_repr}

///|
pub fn MergePlan::column_evolution(self : MergePlan) -> Array[ColumnEvolution] {
  self.evolution_data.copy()
}

///|
fn evolution_name(name : String) -> Unit raise MergeError {
  validate_unicode(name)
  if name.is_empty() {
    raise InvalidLineage(
      "column evolution names must be nonempty; use null for an absent branch",
    )
  }
}

///|
fn evolution_json(items : Array[ColumnEvolution]) -> Json {
  Json::array(
    items.map(c => {
      "base": c.base,
      "ours": c.ours.map(Json::string).unwrap_or(Json::null()),
      "theirs": c.theirs.map(Json::string).unwrap_or(Json::null()),
      "output": c.output,
    }),
  )
}

///|
pub fn column_evolution_json(
  items : Array[ColumnEvolution],
) -> Json raise MergeError {
  if items.length() > max_columns {
    raise LimitExceeded("column evolution exceeds 512 entries")
  }
  let mut total = 0
  for item in items {
    let names = [item.base, item.output]
    for source in [item.ours, item.theirs] {
      if source is Some(name) {
        names.push(name)
      }
    }
    for name in names {
      evolution_name(name)
      if name.length() > max_chars - total {
        raise LimitExceeded(
          "column evolution text exceeds 16000000 UTF-16 code units",
        )
      }
      total += name.length()
    }
  }
  let value = evolution_json(items)
  if value.stringify().length() > max_chars {
    raise LimitExceeded(
      "column evolution JSON exceeds 16000000 UTF-16 code units",
    )
  }
  value
}

///|
/// Strict JSON: base/output are nonempty strings, ours/theirs are strings or
/// null. Merge checks presence, one-to-one ownership and complete-schema collisions.
pub fn parse_column_evolution(
  source : String,
) -> Array[ColumnEvolution] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidLineage("expected column evolution array")
  }
  if items.length() > max_columns {
    raise LimitExceeded("column evolution exceeds 512 entries")
  }
  fn branch(value : Json) -> String? raise MergeError {
    match value {
      Null => None
      String(name) => {
        evolution_name(name)
        Some(name)
      }
      _ =>
        raise InvalidLineage(
          "evolution branch source must be a nonempty string or null",
        )
    }
  }
  items.map(item => {
    guard item is Object(fields) &&
      fields.length() == 4 &&
      fields.get("base") is Some(String(base)) &&
      fields.get("output") is Some(String(output)) &&
      fields.get("ours") is Some(ours) &&
      fields.get("theirs") is Some(theirs) else {
      raise InvalidLineage(
        "column evolution requires exactly base/ours/theirs/output; only branch sources may be null",
      )
    }
    evolution_name(base)
    evolution_name(output)
    ColumnEvolution::{
      base,
      ours: branch(ours),
      theirs: branch(theirs),
      output,
    }
  })
}

///|
fn evolved_table(
  table : Table,
  items : Array[ColumnEvolution],
  side : String,
) -> Table raise MergeError {
  let mappings : Map[String, String] = Map([])
  let outputs : Map[String, Bool] = Map([])
  for c in items {
    evolution_name(c.base)
    evolution_name(c.output)
    if outputs.contains(c.output) {
      raise InvalidLineage(
        "column lineage/evolution output is declared more than once: '\{c.output}'",
      )
    }
    outputs[c.output] = true
    let source = match side {
      "base" => Some(c.base)
      "ours" => c.ours
      _ => c.theirs
    }
    if source is Some(name) {
      evolution_name(name)
      if !table.columns.contains(name) {
        raise InvalidLineage(
          "\{side} lacks declared evolution source '\{name}'; declare null only for a truly absent branch",
        )
      }
      if mappings.contains(name) {
        raise InvalidLineage(
          "\{side}: column source '\{name}' is claimed more than once",
        )
      }
      mappings[name] = c.output
    }
  }
  // An absent declaration must not accidentally leave its old/output name as
  // an unrelated column. Explicit ownership by another mapping permits cycles.
  for c in items {
    let absent = match side {
      "base" => false
      "ours" => c.ours == None
      _ => c.theirs == None
    }
    if absent {
      let reserved = [c.base, c.output]
      for name in [c.ours, c.theirs] {
        if name is Some(n) {
          reserved.push(n)
        }
      }
      for name in reserved {
        if table.columns.contains(name) && !mappings.contains(name) {
          raise InvalidLineage(
            "\{side}: declared absence is ambiguous with unclaimed column '\{name}'; correct the source or explicitly map its different identity",
          )
        }
      }
    }
  }
  let columns = table.columns.map(name => mappings.get(name).unwrap_or(name))
  let seen : Map[String, Bool] = Map([])
  for column in columns {
    if seen.contains(column) {
      raise InvalidLineage(
        "\{side}: evolved output column '\{column}' collides with another column",
      )
    }
    seen[column] = true
  }
  // Even another explicitly mapped source cannot occupy a declared-absent
  // output identity: that would turn deletion into a retained value silently.
  for c in items {
    let absent = match side {
      "base" => false
      "ours" => c.ours == None
      _ => c.theirs == None
    }
    if absent && seen.contains(c.output) {
      raise InvalidLineage(
        "\{side}: declared-absent output '\{c.output}' is occupied",
      )
    }
  }
  Table::from_rows(columns, table.records)
}
