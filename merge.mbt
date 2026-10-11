///|
/// Starts a structural merge. Input arrays cannot subsequently alter the plan.
pub fn merge(
  base : Table,
  ours : Table,
  theirs : Table,
  key~ : Array[String],
) -> MergePlan raise MergeError {
  if key.is_empty() {
    raise InvalidKey("specify at least one key column")
  }
  let seen : Map[String, Bool] = Map([])
  for name in key {
    if seen.contains(name) {
      raise InvalidKey("duplicate key column '\{name}'")
    }
    seen[name] = true
  }
  calculate(base.snapshot(), ours.snapshot(), theirs.snapshot(), key.copy(), [])
}

///|
/// Adds decisions and replays from the owned snapshots; errors leave the old plan usable.
pub fn resolve(
  plan : MergePlan,
  decisions : Array[Decision],
) -> MergePlan raise MergeError {
  let combined = plan.decisions_data.copy()
  for decision in decisions {
    combined.push(decision)
  }
  calculate(plan.base, plan.ours, plan.theirs, plan.key_columns, combined)
}

///|
pub fn MergePlan::conflicts(self : MergePlan) -> Array[Conflict] {
  self.pending.map(copy_conflict)
}

///|
pub fn MergePlan::decisions(self : MergePlan) -> Array[Decision] {
  self.decisions_data.copy()
}

///|
/// Refuses to materialize an incomplete table.
pub fn MergePlan::finish(self : MergePlan) -> MergedTable raise MergeError {
  match self.output {
    Some(result) =>
      {
        result: result.snapshot(),
        evidence: self.evidence.map(copy_resolution),
      }
    None => raise Unresolved(self.pending.length())
  }
}

///|
pub fn MergedTable::table(self : MergedTable) -> Table {
  self.result.snapshot()
}

///|
pub fn MergedTable::resolutions(self : MergedTable) -> Array[Resolution] {
  self.evidence.map(copy_resolution)
}

///|
fn copy_conflict(c : Conflict) -> Conflict {
  { ..c, base: c.base.copy(), ours: c.ours.copy(), theirs: c.theirs.copy(), }
}

///|
fn copy_resolution(r : Resolution) -> Resolution {
  { ..r, conflict: copy_conflict(r.conflict), }
}

///|
fn ordered_columns(
  base : Indexed,
  ours : Indexed,
  theirs : Indexed,
) -> Array[String] raise MergeError {
  let out = base.source.columns.copy()
  let added : Map[String, Bool] = Map([])
  for name, _ in ours.columns {
    if !base.columns.contains(name) {
      added[name] = true
    }
  }
  for name, _ in theirs.columns {
    if !base.columns.contains(name) {
      added[name] = true
    }
  }
  let names = added.keys().to_array()
  names.sort_by(lexical_string)
  for name in names {
    out.push(name)
  }
  if out.length() > max_columns {
    raise LimitExceeded("union schema exceeds 512 columns")
  }
  out
}

///|
fn key_compare(a : RowKey, b : RowKey) -> Int {
  for i in 0..<a.parts.length() {
    let order = lexical_string(a.parts[i], b.parts[i])
    if order != 0 {
      return order
    }
  }
  0
}

///|
/// Explicit UTF-16 lexicographic order, including strings of unequal length.
fn lexical_string(a : String, b : String) -> Int {
  let end = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<end {
    let order = a[i].to_int().compare(b[i].to_int())
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn source_values(
  source : Indexed,
  target : Target,
  ids : Array[(String, RowKey)],
  columns : Array[String],
) -> Array[CellValue] {
  let out = []
  match target {
    Column(column) =>
      for (id, identity) in ids {
        if source.cell(id, column) is Some(value) {
          out.push(CellValue::{ key: identity, column, value, })
        }
      }
    Row(key) =>
      for column in columns {
        if source.cell(key.token(), column) is Some(value) {
          out.push(CellValue::{ key, column, value, })
        }
      }
    Cell(key, column) =>
      if source.cell(key.token(), column) is Some(value) {
        out.push(CellValue::{ key, column, value, })
      }
  }
  out
}

///|
fn make_conflict(
  target : Target,
  kind : ConflictKind,
  b : Indexed,
  o : Indexed,
  t : Indexed,
  ids : Array[(String, RowKey)],
  columns : Array[String],
) -> Conflict {
  {
    target,
    kind,
    base: source_values(b, target, ids, columns),
    ours: source_values(o, target, ids, columns),
    theirs: source_values(t, target, ids, columns),
  }
}

///|
fn column_changed(
  b : Indexed,
  side : Indexed,
  column : String,
  ids : Array[(String, RowKey)],
) -> Bool {
  ids.any(pair => b.cell(pair.0, column) != side.cell(pair.0, column))
}

///|
fn row_changed(
  b : Indexed,
  side : Indexed,
  id : String,
  columns : Array[String],
) -> Bool {
  columns.any(column => b.cell(id, column) != side.cell(id, column))
}

///|
priv struct ReviewState {
  choices : Map[String, Choice]
  used : Map[String, Bool]
  pending : Array[Conflict]
  evidence : Array[Resolution]
}

///|
fn ReviewState::find(self : ReviewState, conflict : Conflict) -> Choice? {
  let token = conflict.target.to_json().stringify()
  match self.choices.get(token) {
    Some(choice) => {
      self.used[token] = true
      self.evidence.push({ conflict, choice, })
      Some(choice)
    }
    None => {
      self.pending.push(conflict)
      None
    }
  }
}

///|
fn keep_structure(
  review : ReviewState,
  conflict : Conflict,
) -> Bool raise MergeError {
  match review.find(conflict) {
    Some(Keep) => true
    Some(Drop) | None => false
    Some(_) =>
      raise InvalidDecision(
        "structural deletion conflict requires 'keep' or 'drop'",
      )
  }
}

///|
fn choose_cell(
  review : ReviewState,
  conflict : Conflict,
  b : String?,
  o : String?,
  t : String?,
) -> String? raise MergeError {
  match review.find(conflict) {
    None => None
    Some(Value(value)) => Some(value)
    Some(choice) => {
      let selected = match choice {
        Base => b
        Ours => o
        Theirs => t
        _ =>
          raise InvalidDecision(
            "cell conflicts require base/ours/theirs/value; cells cannot be dropped",
          )
      }
      guard selected is Some(value) else {
        raise InvalidDecision(
          "selected cell source is absent; supply an explicit value instead",
        )
      }
      Some(value)
    }
  }
}

///|
fn calculate(
  base : Table,
  ours : Table,
  theirs : Table,
  keys : Array[String],
  decisions : Array[Decision],
) -> MergePlan raise MergeError {
  let b = index_table(base, keys, "base")
  let o = index_table(ours, keys, "ours")
  let t = index_table(theirs, keys, "theirs")
  let columns = ordered_columns(b, o, t)
  let identities : Map[String, RowKey] = Map([])
  for id, key in b.identities {
    identities[id] = key
  }
  for id, key in o.identities {
    identities[id] = key
  }
  for id, key in t.identities {
    identities[id] = key
  }
  if identities.length() > max_rows {
    raise LimitExceeded("union rows exceed 100000")
  }
  let ids = identities.to_array()
  ids.sort_by((a, b) => key_compare(a.1, b.1))
  let choices : Map[String, Choice] = Map([])
  for decision in decisions {
    match decision.target {
      Column(name) => validate_unicode(name)
      Row(key) | Cell(key, _) => {
        if key.parts.length() != keys.length() ||
          key.parts.any(s => s.is_empty()) {
          raise InvalidDecision(
            "decision row key must have the same nonempty components as the merge key",
          )
        }
        for part in key.parts {
          validate_unicode(part)
        }
      }
    }
    if decision.target is Cell(_, name) {
      validate_unicode(name)
    }
    if decision.choice is Value(value) {
      validate_unicode(value)
    }
    let token = decision.target.to_json().stringify()
    if choices.contains(token) {
      raise InvalidDecision(
        "duplicate decision target; keep exactly one choice per conflict",
      )
    }
    choices[token] = decision.choice
  }
  let review : ReviewState = {
    choices,
    used: Map([]),
    pending: [],
    evidence: [],
  }
  let kept_columns = []
  for column in columns {
    let keep = if b.columns.contains(column) {
      match (o.columns.contains(column), t.columns.contains(column)) {
        (true, true) => true
        (false, false) => false
        (true, false) =>
          if column_changed(b, o, column, ids) {
            keep_structure(
              review,
              make_conflict(
                Column(column),
                ColumnDeleteEdit,
                b,
                o,
                t,
                ids,
                columns,
              ),
            )
          } else {
            false
          }
        (false, true) =>
          if column_changed(b, t, column, ids) {
            keep_structure(
              review,
              make_conflict(
                Column(column),
                ColumnDeleteEdit,
                b,
                o,
                t,
                ids,
                columns,
              ),
            )
          } else {
            false
          }
      }
    } else {
      true
    }
    if keep {
      kept_columns.push(column)
    }
  }
  let kept_ids = []
  let selected_rows : Map[String, Choice] = Map([])
  for (id, identity) in ids {
    let op = o.rows.contains(id)
    let tp = t.rows.contains(id)
    let keep = if b.rows.contains(id) {
      match (op, tp) {
        (true, true) => true
        (false, false) => false
        (true, false) =>
          if row_changed(b, o, id, columns) {
            keep_structure(
              review,
              make_conflict(Row(identity), RowDeleteEdit, b, o, t, ids, columns),
            )
          } else {
            false
          }
        (false, true) =>
          if row_changed(b, t, id, columns) {
            keep_structure(
              review,
              make_conflict(Row(identity), RowDeleteEdit, b, o, t, ids, columns),
            )
          } else {
            false
          }
      }
    } else if op && tp && row_changed(o, t, id, columns) {
      let conflict = make_conflict(
        Row(identity),
        ConcurrentInsert,
        b,
        o,
        t,
        ids,
        columns,
      )
      match review.find(conflict) {
        Some(Ours) => {
          selected_rows[id] = Ours
          true
        }
        Some(Theirs) => {
          selected_rows[id] = Theirs
          true
        }
        Some(Drop) | None => false
        Some(_) =>
          raise InvalidDecision(
            "concurrent row insertion requires ours/theirs/drop",
          )
      }
    } else {
      true
    }
    if keep {
      kept_ids.push((id, identity))
    }
  }
  let rows : Array[Array[String]] = []
  // Structural decisions may expose new cell conflicts. Do not guess their shape.
  if review.pending.is_empty() {
    if kept_ids.length() * kept_columns.length() > max_cells {
      raise LimitExceeded("output exceeds 2000000 cells")
    }
    for (id, identity) in kept_ids {
      let row = []
      for column in kept_columns {
        let pending_before = review.pending.length()
        let bv = b.cell(id, column)
        let ov = o.cell(id, column)
        let tv = t.cell(id, column)
        let value = match selected_rows.get(id) {
          Some(Ours) => ov
          Some(Theirs) => tv
          _ =>
            match (ov, tv) {
              (Some(a), Some(c)) =>
                if a == c {
                  Some(a)
                } else if bv == Some(a) {
                  Some(c)
                } else if bv == Some(c) {
                  Some(a)
                } else {
                  choose_cell(
                    review,
                    make_conflict(
                      Cell(identity, column),
                      CellEdit,
                      b,
                      o,
                      t,
                      [(id, identity)],
                      [column],
                    ),
                    bv,
                    ov,
                    tv,
                  )
                }
              (Some(a), None) => Some(a)
              (None, Some(c)) => Some(c)
              (None, None) => bv
            }
        }
        let value = if value == None &&
          review.pending.length() == pending_before {
          choose_cell(
            review,
            make_conflict(
              Cell(identity, column),
              MissingCell,
              b,
              o,
              t,
              [(id, identity)],
              [column],
            ),
            bv,
            ov,
            tv,
          )
        } else {
          value
        }
        match value {
          Some(value) => row.push(value)
          None => () // The row is never exposed while any conflict remains.
        }
      }
      rows.push(row)
    }
  }
  for token, _ in choices {
    if !review.used.contains(token) {
      raise InvalidDecision(
        "unknown or premature conflict target \{token}; resolve reported structure conflicts first",
      )
    }
  }
  let output = if review.pending.is_empty() {
    let table = Table::from_rows(kept_columns, rows)
    ignore(index_table(table, keys, "merged"))
    Some(table)
  } else {
    None
  }
  {
    base,
    ours,
    theirs,
    key_columns: keys,
    decisions_data: decisions,
    pending: review.pending,
    evidence: review.evidence,
    output,
  }
}
