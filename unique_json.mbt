///|
/// Versioned envelope retaining original inputs, ordinary policies and repairs.
pub fn UniqueReview::to_json(self : UniqueReview) -> Json raise MergeError {
  let value : Json = {
    "format": "mntablemerge/unique-review-1",
    "merge": self.review.to_json(),
    "unique_rules": unique_rules_json(self.rules_data),
    "repairs": decisions_json(self.repair_data),
  }
  if value.stringify().length() > max_chars {
    raise LimitExceeded("unique review exceeds 16000000 UTF-16 units")
  }
  value
}

///|
/// Rejects duplicate/unknown fields and recomputes every phase; cached results are not trusted.
pub fn UniqueReview::from_json(
  source : String,
) -> UniqueReview raise MergeError {
  guard checked_json(source) is Object(fields) &&
    fields.length() == 4 &&
    fields.get("format") == Some(Json::string("mntablemerge/unique-review-1")) &&
    fields.get("merge") is Some(original) &&
    fields.get("unique_rules") is Some(rules) &&
    fields.get("repairs") is Some(repairs) else {
    raise InvalidReview(
      "expected unique-review-1 with exactly format/merge/unique_rules/repairs; use uniqueness-aware commands",
    )
  }
  make_unique(
    ReviewBundle::from_json(original.stringify()),
    parse_unique_rules(rules.stringify()),
    parse_decisions(repairs.stringify()),
  )
}

///|
fn UniqueConflict::to_json(self : UniqueConflict) -> Json {
  {
    "rule": self.rule,
    "columns": Json::array(self.columns.map(Json::string)),
    "values": Json::array(self.values.map(Json::string)),
    "rows": Json::array(
      self.rows.map(k => Json::array(k.parts.map(Json::string))),
    ),
    "base": values_json(self.base),
    "ours": values_json(self.ours),
    "theirs": values_json(self.theirs),
    "merged": values_json(self.merged),
  }
}

///|
fn UniqueReview::repair_evidence(
  self : UniqueReview,
  decision : Decision,
) -> Json {
  let key = match decision.target {
    Row(k) | Cell(k, _) => k
    _ => abort("validated repair")
  }
  let before = unique_row_values(self.outputs[0], [key])
  let after = unique_row_values(self.outputs[1], [key])
  {
    "target": decision.target.to_json(),
    "choice": decision.choice.to_json(),
    "base": values_json(unique_row_values(self.sources[0], [key])),
    "ours": values_json(unique_row_values(self.sources[1], [key])),
    "theirs": values_json(unique_row_values(self.sources[2], [key])),
    "before": values_json(before),
    "after": values_json(after),
  }
}

///|
/// Full ordinary/unique evidence. Oversized reports fail without truncation.
pub fn UniqueReview::report(self : UniqueReview) -> Json raise MergeError {
  let report = self.ordinary.report()
  guard report is Object(fields) else { abort("report object") }
  fields["format"] = Json::string("mntablemerge/unique-report-1")
  fields["complete"] = Json::boolean(
    self.candidate != None && self.pending_unique.is_empty(),
  )
  fields["unique_rules"] = unique_rules_json(self.rules_data)
  fields["unique_conflicts"] = Json::array(
    self.pending_unique.map(c => c.to_json()),
  )
  fields["unique_repairs"] = Json::array(
    self.repair_data.map(d => self.repair_evidence(d)),
  )
  if report.stringify().length() > max_chars {
    raise LimitExceeded(
      "unique report exceeds 16000000 UTF-16 units; inspect typed conflicts instead",
    )
  }
  report
}

///|
/// Compares equal-input/equal-rule reviews with full before/after repair records.
pub fn UniqueReview::changes_report(
  self : UniqueReview,
  previous : UniqueReview,
) -> Json raise MergeError {
  self.review.require_same_inputs(previous.review)
  if self.rules_data != previous.rules_data {
    raise InvalidReview(
      "unique rules differ; compare reviews of the same policies",
    )
  }
  let ordinary = self.review.changes_report(previous.review)
  guard ordinary is Object(fields) &&
    fields.get("changes") is Some(Array(ordinary_changes)) else {
    abort("audit changes")
  }
  let before : Map[String, Json] = Map([])
  let after : Map[String, Json] = Map([])
  let targets : Map[String, Target] = Map([])
  for (source, values) in [(previous, before), (self, after)] {
    for d in source.repair_data {
      let token = d.target.to_json().stringify()
      values[token] = source.repair_evidence(d)
      targets[token] = d.target
    }
  }
  let ordered = targets.to_array()
  ordered.sort_by((a, b) => lexical_string(a.0, b.0))
  let changes = ordinary_changes.copy()
  for (token, target) in ordered {
    if before.get(token) != after.get(token) {
      changes.push({
        "phase": "unique",
        "target": target.to_json(),
        "before": before.get(token).unwrap_or(Json::null()),
        "after": after.get(token).unwrap_or(Json::null()),
      })
    }
  }
  let report : Json = {
    "format": "mntablemerge/unique-changes-1",
    "merge": ordinary,
    "unique_rules": unique_rules_json(self.rules_data),
    "before_complete": previous.candidate != None &&
    previous.pending_unique.is_empty(),
    "after_complete": self.candidate != None && self.pending_unique.is_empty(),
    "changes": Json::array(changes),
  }
  if report.stringify().length() > max_chars {
    raise LimitExceeded("unique audit exceeds 16000000 UTF-16 units")
  }
  report
}
