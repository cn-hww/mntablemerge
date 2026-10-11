///|
/// An offline review owns all three exact parsed snapshots, keys and decisions.
/// It is a revision guard, not a signature or trust boundary.
pub struct ReviewBundle {
  priv base : Table
  priv ours : Table
  priv theirs : Table
  priv keys : Array[String]
  priv choices : Array[Decision]
  priv ordering : RowOrder
}

///|
pub fn ReviewBundle::from_plan(plan : MergePlan) -> ReviewBundle {
  {
    base: plan.base.snapshot(),
    ours: plan.ours.snapshot(),
    theirs: plan.theirs.snapshot(),
    keys: plan.key_columns.copy(),
    choices: plan.decisions(),
    ordering: plan.ordering,
  }
}

///|
/// Recomputes every conflict and checks every supplied decision.
pub fn ReviewBundle::plan(self : ReviewBundle) -> MergePlan raise MergeError {
  calculate(
    self.base,
    self.ours,
    self.theirs,
    self.keys,
    self.choices,
    self.ordering,
  )
}

///|
/// Adds decisions without modifying the existing bundle. Structure can be
/// resolved and serialized before newly exposed cell conflicts are reviewed.
pub fn ReviewBundle::resolve(
  self : ReviewBundle,
  decisions : Array[Decision],
) -> ReviewBundle raise MergeError {
  ReviewBundle::from_plan(resolve(self.plan(), decisions))
}

///|
/// Only replays against the snapshots actually reviewed. CSV whitespace/quote
/// style/BOM differences are tolerated after parsing; row/header order is bound.
pub fn ReviewBundle::replay(
  self : ReviewBundle,
  base : Table,
  ours : Table,
  theirs : Table,
  key~ : Array[String],
) -> MergePlan raise MergeError {
  if base != self.base ||
    ours != self.ours ||
    theirs != self.theirs ||
    key != self.keys {
    raise InvalidReview(
      "input snapshots or key selection changed; regenerate review and inspect conflicts again",
    )
  }
  self.plan()
}

///|
/// Refuses an oversized export rather than emitting a bundle it cannot read.
pub fn ReviewBundle::to_json(self : ReviewBundle) -> Json raise MergeError {
  let value : Json = {
    "format": "mntablemerge/review-1",
    "base": self.base.to_csv(),
    "ours": self.ours.to_csv(),
    "theirs": self.theirs.to_csv(),
    "key": Json::array(self.keys.map(Json::string)),
    "decisions": decisions_json(self.choices),
  }
  if self.ordering != Lexical {
    guard value is Object(fields) else { abort("object literal") }
    fields["format"] = "mntablemerge/review-2"
    fields["row_order"] = Json::string(self.ordering.name())
  }
  if value.stringify().length() > max_chars {
    raise LimitExceeded("review bundle exceeds 16000000 UTF-16 code units")
  }
  value
}

///|
/// Strict, versioned import. Revalidates snapshots, keys and cumulative
/// decisions; accepts incomplete review but never an unsupported field/version.
pub fn ReviewBundle::from_json(
  source : String,
) -> ReviewBundle raise MergeError {
  let value = checked_json(source)
  guard value is Object(fields) else {
    raise InvalidReview(
      "expected exactly format/base/ours/theirs/key/decisions",
    )
  }
  let ordering = match fields.get("format") {
    Some(String("mntablemerge/review-1")) if fields.length() == 6 => Lexical
    Some(String("mntablemerge/review-2")) if fields.length() == 7 => {
      guard fields.get("row_order") is Some(String(order)) else {
        raise InvalidReview("review-2 requires a string row_order")
      }
      RowOrder::parse(order)
    }
    _ =>
      raise InvalidReview(
        "unsupported review format/fields; use review-1 or review-2",
      )
  }
  guard fields.get("base") is Some(String(b)) &&
    fields.get("ours") is Some(String(o)) &&
    fields.get("theirs") is Some(String(t)) &&
    fields.get("key") is Some(Array(keys)) &&
    fields.get("decisions") is Some(decisions) else {
    raise InvalidReview(
      "snapshots must be CSV strings, key a string array, decisions an array",
    )
  }
  let keys = keys.map(k => {
    match k {
      String(name) => name
      _ => raise InvalidReview("key columns must be strings")
    }
  })
  let plan = merge(
    parse_csv(b),
    parse_csv(o),
    parse_csv(t),
    key=keys,
    row_order=ordering,
  )
  ReviewBundle::from_plan(resolve(plan, parse_decisions(decisions.stringify())))
}
