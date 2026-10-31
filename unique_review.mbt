///|
fn make_unique(
  review : ReviewBundle,
  rules : Array[UniqueRule],
  repairs : Array[Decision],
) -> UniqueReview raise MergeError {
  let rules = canonical_rules(rules)
  let ordinary = review.plan()
  let sources = [
    unique_source(review, review.base, "base"),
    unique_source(review, review.ours, "ours"),
    unique_source(review, review.theirs, "theirs"),
  ]
  for i, source in sources {
    for rule in rules {
      let groups = unique_groups(source, rule)
      if groups.get(0) is Some((values, rows)) {
        raise InvalidTable(
          "\{["base","ours","theirs"][i]} already violates unique rule '\{rule.label}': values \{Json::array(values.parts.map(Json::string)).stringify()}, rows \{Json::array(rows.map(k => Json::array(k.parts.map(Json::string)))).stringify()}; repair that source first",
        )
      }
    }
  }
  let initial = ordinary.output
  if initial == None {
    if !repairs.is_empty() {
      raise InvalidDecision(
        "resolve ordinary conflicts before uniqueness repairs; revoke repairs before changing the underlying merge",
      )
    }
    return {
      review,
      rules_data: rules,
      repair_data: [],
      ordinary,
      initial: None,
      candidate: None,
      pending_unique: [],
      sources,
      outputs: [],
    }
  }
  let original = index_table(initial.unwrap(), review.keys, "merged")
  let eligible : Map[String, Map[String, Bool]] = Map([])
  for rule in rules {
    for (_, rows) in unique_groups(original, rule) {
      for row in rows {
        let fields = eligible.get_or_init(row.token(), () => Map([]))
        for name in rule.fields {
          if !review.keys.contains(name) {
            fields[name] = true
          }
        }
      }
    }
  }
  if repairs.length() > max_cells {
    raise LimitExceeded("too many uniqueness repairs")
  }
  let changes : Map[String, Decision] = Map([])
  let drops : Map[String, Bool] = Map([])
  let touched : Map[String, Bool] = Map([])
  let mut evidence_cells = 0
  for decision in repairs {
    validate_edit_target(decision.target)
    let (row, name) = match (decision.target, decision.choice) {
      (Row(key), Drop) => (key, None)
      (Cell(key, column), Value(value)) => {
        validate_unicode(value)
        (key, Some(column))
      }
      _ =>
        raise InvalidDecision(
          "unique repairs require Row/Drop or Cell/Value; primary keys and unrelated cells cannot be edited",
        )
    }
    if row.parts.length() != review.keys.length() ||
      !eligible.contains(row.token()) {
      raise InvalidDecision(
        "unique repair row is not in an initial merged duplicate group",
      )
    }
    evidence_cells += 2 * original.source.columns.length()
    for source in sources {
      if source.rows.contains(row.token()) {
        evidence_cells += source.source.columns.length()
      }
    }
    if evidence_cells > max_cells {
      raise LimitExceeded(
        "complete uniqueness repair evidence exceeds 2000000 cells",
      )
    }
    if name is Some(column) && !eligible[row.token()].contains(column) {
      raise InvalidDecision(
        "unique repair column is not an implicated non-key unique field",
      )
    }
    let token = decision.target.to_json().stringify()
    if changes.contains(token) {
      raise InvalidDecision(
        "duplicate unique repair target; use revise_repairs to replace it",
      )
    }
    changes[token] = decision
    match name {
      None => drops[row.token()] = true
      Some(_) => touched[row.token()] = true
    }
  }
  for token, _ in drops {
    if touched.contains(token) {
      raise InvalidDecision(
        "cannot drop and edit the same record; choose one operation",
      )
    }
  }
  let rows = []
  for row in original.source.records {
    let key = RowKey(review.keys.map(name => row[original.columns[name]]))
    if drops.contains(key.token()) {
      continue
    }
    rows.push(
      if !touched.contains(key.token()) {
        row
      } else {
        original.source.columns.mapi((i, name) => {
          match changes.get(Cell(key, name).to_json().stringify()) {
            Some({ choice: Value(value), .. }) => value
            _ => row[i]
          }
        })
      },
    )
  }
  let candidate = Table::from_rows(original.source.columns, rows)
  let indexed = index_table(candidate, review.keys, "repaired")
  for rule in rules {
    for (_, group) in unique_groups(indexed, rule) {
      let expected = unique_tuple(original, group[0], rule)
      if group.any(key => unique_tuple(original, key, rule) != expected) {
        raise InvalidDecision(
          "unique repair introduces a new duplicate pair under '\{rule.label}'; choose a distinct exact value or explicitly drop an implicated record",
        )
      }
    }
  }
  let ordered = repairs.copy()
  ordered.sort_by((a, b) => {
    lexical_string(
      a.target.to_json().stringify(),
      b.target.to_json().stringify(),
    )
  })
  {
    review,
    rules_data: rules,
    repair_data: ordered,
    ordinary,
    initial,
    candidate: Some(candidate),
    pending_unique: unique_conflicts(indexed, sources, rules),
    sources,
    outputs: [original, indexed],
  }
}

///|
/// Validates named rules against all aligned sources, then enters merge/unique phases.
pub fn UniqueReview::new(
  review : ReviewBundle,
  rules : Array[UniqueRule],
) -> UniqueReview raise MergeError {
  make_unique(review, rules, [])
}

///|
/// Canonical rule order; column accessors return defensive copies.
pub fn UniqueReview::rules(self : UniqueReview) -> Array[UniqueRule] {
  self.rules_data.copy()
}

///|
/// Complete unique evidence, defensively copied; ordinary conflicts are separate.
pub fn UniqueReview::conflicts(self : UniqueReview) -> Array[UniqueConflict] {
  self.pending_unique.map(copy_unique)
}

///|
/// Ordinary structural/cell conflicts must be resolved before uniqueness repair.
pub fn UniqueReview::merge_conflicts(self : UniqueReview) -> Array[Conflict] {
  self.ordinary.conflicts()
}

///|
/// Recorded unique decisions in canonical target order, separate from ordinary choices.
pub fn UniqueReview::repairs(self : UniqueReview) -> Array[Decision] {
  self.repair_data.copy()
}

///|
/// Exports only after ordinary and uniqueness phases are complete.
pub fn UniqueReview::finish(
  self : UniqueReview,
) -> MergedTable raise MergeError {
  if self.candidate is Some(result) && self.pending_unique.is_empty() {
    { result, evidence: self.ordinary.evidence.map(copy_resolution), }
  } else {
    raise Unresolved(
      self.ordinary.pending.length() + self.pending_unique.length(),
    )
  }
}

///|
/// Adds explicit Row/Drop or implicated non-key Cell/Value repairs atomically.
/// New duplicate pairs, duplicate targets and unrelated edits are rejected.
pub fn UniqueReview::repair(
  self : UniqueReview,
  decisions : Array[Decision],
) -> UniqueReview raise MergeError {
  if decisions.length() > max_cells - self.repair_data.length() {
    raise LimitExceeded("too many uniqueness repairs")
  }
  let combined = self.repair_data.copy()
  for decision in decisions {
    combined.push(decision)
  }
  make_unique(self.review, self.rules_data, combined)
}

///|
/// Sets/replaces/revokes repairs; every retained repair is revalidated.
pub fn UniqueReview::revise_repairs(
  self : UniqueReview,
  edits : Array[ReviewEdit],
) -> UniqueReview raise MergeError {
  ignore(review_edits_json(edits))
  let choices : Map[String, Decision] = Map([])
  for d in self.repair_data {
    choices[d.target.to_json().stringify()] = d
  }
  let seen : Map[String, Bool] = Map([])
  for edit in edits {
    let token = edit.target().to_json().stringify()
    if seen.contains(token) {
      raise InvalidDecision("duplicate unique repair edit target")
    }
    seen[token] = true
    match edit {
      Set(d) => choices[token] = d
      Revoke(_) => {
        if !choices.contains(token) {
          raise InvalidDecision("cannot revoke an unrecorded uniqueness repair")
        }
        choices.remove(token)
      }
    }
  }
  make_unique(self.review, self.rules_data, choices.values().to_array())
}

///|
/// Revises ordinary choices. Revoke unique repairs first if their candidate changes.
pub fn UniqueReview::revise(
  self : UniqueReview,
  edits : Array[ReviewEdit],
) -> UniqueReview raise MergeError {
  let next = make_unique(self.review.revise(edits), self.rules_data, [])
  if !self.repair_data.is_empty() && next.initial != self.initial {
    raise InvalidDecision(
      "underlying merge changed; explicitly revoke uniqueness repairs before revising ordinary choices",
    )
  }
  make_unique(next.review, self.rules_data, self.repair_data)
}

///|
/// Checks exact original parsed snapshots/key order and retains bound unique rules.
pub fn UniqueReview::replay(
  self : UniqueReview,
  base : Table,
  ours : Table,
  theirs : Table,
  key~ : Array[String],
) -> UniqueReview raise MergeError {
  ignore(self.review.replay(base, ours, theirs, key~))
  self
}
