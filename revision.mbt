///|
/// An explicit atomic update to current review decisions.
pub(all) enum ReviewEdit {
  Set(Decision)
  Revoke(Target)
} derive(Eq, Debug)

///|
pub extend ReviewEdit with Eq::{equal, not_equal}

///|
pub extend ReviewEdit with @debug.Debug::{to_repr}

///|
fn ReviewEdit::target(self : ReviewEdit) -> Target {
  match self {
    Set(d) => d.target
    Revoke(target) => target
  }
}

///|
fn validate_edit_target(target : Target) -> Unit raise MergeError {
  fn column(name : String) -> Unit raise MergeError {
    validate_unicode(name)
    if name.is_empty() {
      raise InvalidDecision("review column must be nonempty")
    }
  }
  fn key(key : RowKey) -> Unit raise MergeError {
    if key.parts.is_empty() || key.parts.length() > max_columns {
      raise InvalidDecision("review row key requires 1..512 components")
    }
    for part in key.parts {
      validate_unicode(part)
      if part.is_empty() {
        raise InvalidDecision("review key components must be nonempty")
      }
    }
  }
  match target {
    Column(name) => column(name)
    Row(id) => key(id)
    Cell(id, name) => {
      key(id)
      column(name)
    }
  }
}

///|
/// Replaces/revokes choices without modifying this plan. Every retained choice
/// must remain applicable; revoke dependencies explicitly in the same batch.
pub fn MergePlan::revise(
  self : MergePlan,
  edits : Array[ReviewEdit],
) -> MergePlan raise MergeError {
  if edits.length() > max_cells {
    raise LimitExceeded("too many review edits")
  }
  let existing : Map[String, Bool] = Map([])
  let pending : Map[String, Bool] = Map([])
  for decision in self.decisions_data {
    existing[decision.target.to_json().stringify()] = true
  }
  for conflict in self.pending {
    pending[conflict.target.to_json().stringify()] = true
  }
  let updates : Map[String, ReviewEdit] = Map([])
  for edit in edits {
    let target = edit.target()
    validate_edit_target(target)
    let token = target.to_json().stringify()
    if updates.contains(token) {
      raise InvalidDecision(
        "duplicate review edit target; use one set/revoke per target",
      )
    }
    match edit {
      Set(_) =>
        if !existing.contains(token) && !pending.contains(token) {
          raise InvalidDecision(
            "cannot set unknown or newly hidden target \{token}; inspect current conflicts and resolve structure first",
          )
        }
      Revoke(_) =>
        if !existing.contains(token) {
          raise InvalidDecision(
            "cannot revoke unrecorded target \{token}; inspect decisions()",
          )
        }
    }
    updates[token] = edit
  }
  let choices : Array[Decision] = []
  // Replacements retain their position, unaffected decisions retain order.
  for decision in self.decisions_data {
    match updates.get(decision.target.to_json().stringify()) {
      Some(Set(replacement)) => choices.push(replacement)
      Some(Revoke(_)) => ()
      None => choices.push(decision)
    }
  }
  // Choices for current pending targets append in supplied edit order.
  for edit in edits {
    if edit is Set(decision) &&
      !existing.contains(decision.target.to_json().stringify()) {
      choices.push(decision)
    }
  }
  calculate(
    self.base,
    self.ours,
    self.theirs,
    self.key_columns,
    choices,
    self.ordering,
    lineage=self.lineage_data,
    rows=self.row_lineage_data,
  ) catch {
    InvalidDecision(reason) =>
      raise InvalidDecision(
        reason +
        "; revision rejected: explicitly revoke decisions that the new structure makes inapplicable, then inspect newly exposed conflicts",
      )
    error => raise error
  }
}

///|
pub fn ReviewBundle::revise(
  self : ReviewBundle,
  edits : Array[ReviewEdit],
) -> ReviewBundle raise MergeError {
  ReviewBundle::from_plan(self.plan().revise(edits))
}

///|
/// Strict export: refuses invalid Unicode and oversized edit documents.
pub fn review_edits_json(edits : Array[ReviewEdit]) -> Json raise MergeError {
  if edits.length() > max_cells {
    raise LimitExceeded("too many review edits")
  }
  let mut total = 0
  for edit in edits {
    let target = edit.target()
    let strings = match target {
      Column(name) => [name]
      Row(key) => key.components()
      Cell(key, name) => {
        let parts = key.components()
        parts.push(name)
        parts
      }
    }
    if edit is Set({ choice: Value(value), .. }) {
      strings.push(value)
    }
    for value in strings {
      if value.length() > max_chars - total {
        raise LimitExceeded(
          "review edit text exceeds 16000000 UTF-16 code units",
        )
      }
      total += value.length()
    }
  }
  let value = Json::array(
    edits.map(edit => {
      validate_edit_target(edit.target())
      match edit {
        Revoke(target) => { "op": "revoke", "target": target.to_json() }
        Set(decision) => {
          if decision.choice is Value(value) {
            validate_unicode(value)
          }
          {
            "op": "set",
            "target": decision.target.to_json(),
            "choice": decision.choice.to_json(),
          }
        }
      }
    }),
  )
  if value.stringify().length() > max_chars {
    raise LimitExceeded("review edit JSON exceeds 16000000 UTF-16 code units")
  }
  value
}

///|
pub fn parse_review_edits(
  source : String,
) -> Array[ReviewEdit] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidDecision("review edits must be an array")
  }
  if items.length() > max_cells {
    raise LimitExceeded("too many review edits")
  }
  items.map(item => {
    guard item is Object(fields) && fields.get("target") is Some(target) else {
      raise InvalidDecision("each review edit requires op and target")
    }
    let target = parse_target(target)
    validate_edit_target(target)
    match fields.get("op") {
      Some(String("revoke")) if fields.length() == 2 => Revoke(target)
      Some(String("set")) if fields.length() == 3 &&
        fields.get("choice") is Some(choice) =>
        Set({ target, choice: parse_choice(choice), })
      _ =>
        raise InvalidDecision(
          "use exactly {op: set, target, choice} or {op: revoke, target}; unknown fields/operations are rejected",
        )
    }
  })
}
