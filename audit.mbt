///|
/// A change in recorded resolution, including complete source evidence.
/// None means no recorded decision, never a stored empty cell value.
pub(all) struct ReviewChange {
  target : Target
  before : Resolution?
  after : Resolution?
} derive(Eq, Debug)

///|
pub extend ReviewChange with Eq::{equal, not_equal}

///|
pub extend ReviewChange with @debug.Debug::{to_repr}

///|
fn resolution_changes(
  before : MergePlan,
  after : MergePlan,
) -> Array[ReviewChange] raise MergeError {
  let old : Map[String, Resolution] = Map([])
  let current : Map[String, Resolution] = Map([])
  let targets : Map[String, Target] = Map([])
  for resolution in before.evidence {
    let token = resolution.conflict.target.to_json().stringify()
    old[token] = resolution
    targets[token] = resolution.conflict.target
  }
  for resolution in after.evidence {
    let token = resolution.conflict.target.to_json().stringify()
    current[token] = resolution
    targets[token] = resolution.conflict.target
  }
  let ordered = targets.to_array()
  ordered.sort_by((a, b) => lexical_string(a.0, b.0))
  let changes : Array[ReviewChange] = []
  for (token, target) in ordered {
    let prior = old.get(token)
    let next = current.get(token)
    if prior != next {
      if changes.length() >= max_cells {
        raise LimitExceeded(
          "review comparison exceeds 2000000 changed resolutions",
        )
      }
      changes.push({
        target,
        before: prior.map(copy_resolution),
        after: next.map(copy_resolution),
      })
    }
  }
  changes
}

///|
/// Compares validated reviews of exactly the same inputs and policies.
/// Added, changed and revoked decisions are sorted by canonical target.
/// This is a comparison, not an authenticated history or a replayable patch.
pub fn ReviewBundle::changes_since(
  self : ReviewBundle,
  previous : ReviewBundle,
) -> Array[ReviewChange] raise MergeError {
  self.require_same_inputs(previous)
  resolution_changes(previous.plan(), self.plan())
}

///|
fn resolution_json(resolution : Resolution?) -> Json {
  match resolution {
    None => Json::null()
    Some(r) =>
      { "conflict": r.conflict.to_json(), "choice": r.choice.to_json() }
  }
}

///|
/// Emits full before/after evidence or refuses an oversized report.
pub fn ReviewBundle::changes_report(
  self : ReviewBundle,
  previous : ReviewBundle,
) -> Json raise MergeError {
  self.require_same_inputs(previous)
  let before = previous.plan()
  let after = self.plan()
  let changes = resolution_changes(before, after)
  let report : Json = {
    "format": "mntablemerge/review-changes-1",
    "key": Json::array(self.keys.map(Json::string)),
    "row_order": self.ordering.name(),
    "column_lineage": lineage_json(self.lineage),
    "row_lineage": row_lineage_json_unchecked(self.rows),
    "before_complete": before.output != None,
    "after_complete": after.output != None,
    "changes": Json::array(
      changes.map(c => {
        "target": c.target.to_json(),
        "before": resolution_json(c.before),
        "after": resolution_json(c.after),
      }),
    ),
  }
  if report.stringify().length() > max_chars {
    raise LimitExceeded(
      "review change report exceeds 16000000 escaped UTF-16 units; use changes_since for complete typed evidence",
    )
  }
  report
}
