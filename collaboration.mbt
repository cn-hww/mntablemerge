///|
fn ReviewBundle::require_same_inputs(
  self : ReviewBundle,
  other : ReviewBundle,
) -> Unit raise MergeError {
  if self.base != other.base ||
    self.ours != other.ours ||
    self.theirs != other.theirs ||
    self.keys != other.keys ||
    self.ordering != other.ordering ||
    self.lineage != other.lineage ||
    self.rows != other.rows {
    raise InvalidReview(
      "review snapshots, keys or policies differ; regenerate reviews from the same baseline",
    )
  }
}

///|
/// Combines independently reviewed copies of this baseline without overwrites.
/// Baseline choices must be retained exactly; agreeing additions coalesce.
/// Conflicting choices or invalid structural dependencies reject the whole batch.
pub fn ReviewBundle::combine(
  self : ReviewBundle,
  reviews : Array[ReviewBundle],
) -> ReviewBundle raise MergeError {
  if reviews.length() > 256 {
    raise LimitExceeded("combine accepts at most 256 review bundles per batch")
  }
  let _ = self.plan()
  let inherited : Map[String, Choice] = Map([])
  let additions : Map[String, Decision] = Map([])
  for decision in self.choices {
    inherited[decision.target.to_json().stringify()] = decision.choice
  }
  for review in reviews {
    self.require_same_inputs(review)
    let plan = review.plan()
    let supplied : Map[String, Choice] = Map([])
    for decision in plan.decisions_data {
      supplied[decision.target.to_json().stringify()] = decision.choice
    }
    for token, choice in inherited {
      if supplied.get(token) != Some(choice) {
        raise InvalidReview(
          "review changed or revoked baseline decision at \{token}; revise the baseline explicitly and restart assignments",
        )
      }
    }
    for decision in plan.decisions_data {
      let token = decision.target.to_json().stringify()
      if inherited.contains(token) {
        continue
      }
      match additions.get(token) {
        Some(existing) if existing.choice != decision.choice =>
          raise InvalidReview(
            "reviewers disagree at \{token}; choose explicitly in a new shared baseline",
          )
        Some(_) => ()
        None => {
          if inherited.length() + additions.length() >= max_cells {
            raise LimitExceeded("combined review exceeds 2000000 decisions")
          }
          additions[token] = decision
        }
      }
    }
  }
  let ordered = additions.to_array()
  ordered.sort_by((a, b) => lexical_string(a.0, b.0))
  let decisions = self.choices.copy()
  for (_, decision) in ordered {
    decisions.push(decision)
  }
  let combined = calculate(
    self.base,
    self.ours,
    self.theirs,
    self.keys,
    decisions,
    self.ordering,
    lineage=self.lineage,
    rows=self.rows,
  ) catch {
    InvalidDecision(reason) =>
      raise InvalidReview(
        reason +
        "; combined review rejected: reconcile structural dependencies explicitly",
      )
    error => raise error
  }
  ReviewBundle::from_plan(combined)
}
