///|
fn validate_scope(
  targets : Array[Target],
) -> Map[String, Bool] raise MergeError {
  if targets.length() >= max_rows {
    raise LimitExceeded("scoped sheets require at most 99999 targets")
  }
  let selected : Map[String, Bool] = Map([])
  let mut total = 0
  for target in targets {
    validate_edit_target(target)
    let token = target.to_json().stringify()
    if token.length() > max_chars - total {
      raise LimitExceeded("scope JSON exceeds 16000000 UTF-16 units")
    }
    total += token.length()
    if selected.contains(token) {
      raise InvalidReview("duplicate scope target; assign each conflict once")
    }
    selected[token] = true
  }
  selected
}

///|
/// Strict coordinate list for CLI assignment, with no wildcard/inferred matches.
pub fn parse_review_targets(source : String) -> Array[Target] raise MergeError {
  guard checked_json(source) is Array(items) else {
    raise InvalidReview("scope must be a JSON array of conflict targets")
  }
  if items.length() >= max_rows {
    raise LimitExceeded("scoped sheets require at most 99999 targets")
  }
  let targets = items.map(parse_target)
  let _ = validate_scope(targets)
  targets
}

///|
fn scoped_conflicts(
  plan : MergePlan,
  targets : Array[Target],
) -> Array[Conflict] raise MergeError {
  let selected = validate_scope(targets)
  let conflicts = plan.pending.filter(c => {
    selected.contains(c.target.to_json().stringify())
  })
  if conflicts.length() != selected.length() {
    raise InvalidReview(
      "scope contains a resolved, hidden or unknown target; select only current conflicts and export again",
    )
  }
  conflicts
}

///|
/// Exports only explicitly assigned current conflicts, binding all original data.
/// Scope order is canonicalized; empty scope makes an explicit no-op assignment.
pub fn MergePlan::review_sheet_for(
  self : MergePlan,
  targets : Array[Target],
) -> Table raise MergeError {
  let conflicts = scoped_conflicts(self, targets)
  let scope = Json::array(conflicts.map(c => c.target.to_json()))
  make_review_sheet(self, conflicts, Some(scope))
}

///|
/// Requires the independently supplied assignment as well as the edited sheet.
/// Omitted assigned rows fail; conflicts outside the assignment stay pending.
pub fn MergePlan::apply_review_sheet_for(
  self : MergePlan,
  targets : Array[Target],
  sheet : Table,
) -> MergePlan raise MergeError {
  self.apply_checked_sheet(self.review_sheet_for(targets), sheet)
}
