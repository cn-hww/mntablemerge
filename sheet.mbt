///|
fn sheet_headers() -> Array[String] {
  ["format", "target", "kind", "base", "ours", "theirs", "choice", "value"]
}

///|
fn conflict_sheet_row(conflict : Conflict) -> Array[String] {
  guard conflict.to_json() is Object(fields) &&
    fields.get("kind") is Some(String(kind)) else {
    abort("conflict object")
  }
  [
    "mntablemerge/sheet-1",
    conflict.target.to_json().stringify(),
    kind,
    values_json(conflict.base).stringify(),
    values_json(conflict.ours).stringify(),
    values_json(conflict.theirs).stringify(),
    "",
    "",
  ]
}

///|
/// Editable table of all current conflicts. Only choice/value may change.
/// The first binding record owns full canonical input snapshots and policies.
pub fn MergePlan::review_sheet(self : MergePlan) -> Table raise MergeError {
  if self.pending.length() >= max_rows {
    raise LimitExceeded(
      "review sheet supports at most 99999 conflicts plus its binding record; use the JSON workflow",
    )
  }
  let binding = ReviewBundle::from_plan(self).to_json().stringify()
  let rows = [["mntablemerge/sheet-1", "", "binding", binding, "", "", "", ""]]
  for conflict in self.pending {
    rows.push(conflict_sheet_row(conflict))
  }
  // Refuse oversized evidence rather than omitting conflicts/source values.
  Table::from_rows(sheet_headers(), rows)
}

///|
/// Atomically applies selected current conflicts from an input-bound sheet.
/// Blank choice means pending; choice=value with empty value is explicit empty.
/// Reordering conflict rows is safe; deletion/duplication/evidence edits fail.
pub fn MergePlan::apply_review_sheet(
  self : MergePlan,
  sheet : Table,
) -> MergePlan raise MergeError {
  let expected = self.review_sheet()
  if sheet.columns != expected.columns ||
    sheet.records.length() != expected.records.length() {
    raise InvalidReview(
      "sheet headers/conflict coverage changed; export a fresh sheet and keep all records",
    )
  }
  if sheet.records[0] != expected.records[0] {
    raise InvalidReview(
      "sheet input binding changed or is stale; export a fresh sheet from the current bundle",
    )
  }
  let evidence : Map[String, Array[String]] = Map([])
  for row in expected.records[1:] {
    evidence[row[1]] = row
  }
  let seen : Map[String, Bool] = Map([])
  let choices : Map[String, Choice] = Map([])
  for row in sheet.records[1:] {
    let target = row[1]
    if seen.contains(target) {
      raise InvalidReview(
        "duplicate sheet target \{target}; retain one row per conflict",
      )
    }
    seen[target] = true
    guard evidence.get(target) is Some(original) else {
      raise InvalidReview(
        "unknown sheet target \{target}; do not change coordinates",
      )
    }
    for i in 0..<6 {
      if row[i] != original[i] {
        raise InvalidReview(
          "sheet evidence changed for \{target}; edit only choice/value",
        )
      }
    }
    if row[6] == "value" {
      choices[target] = Value(row[7])
    } else {
      if row[7] != "" {
        raise InvalidReview(
          "custom text requires choice=value at \{target}; otherwise clear value explicitly",
        )
      }
      if row[6] != "" {
        choices[target] = parse_choice(Json::string(row[6]))
      }
    }
  }
  let decisions : Array[Decision] = []
  // Canonical conflict order makes the result independent of sheet row order.
  for conflict in self.pending {
    if choices.get(conflict.target.to_json().stringify()) is Some(choice) {
      decisions.push({ target: conflict.target, choice, })
    }
  }
  resolve(self, decisions)
}
