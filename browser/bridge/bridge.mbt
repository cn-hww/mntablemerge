///|
fn input(source : String, format : String) -> @merge.Table raise {
  if source.length() > 2000000 {
    raise @merge.LimitExceeded(
      "browser input exceeds 2000000 UTF-16 units; use the CLI for larger inputs",
    )
  }
  let table = match format {
    "csv" => @merge.parse_csv(source)
    "tsv" => @merge.parse_tsv(source)
    _ => raise @merge.InvalidReview("choose csv or tsv explicitly")
  }
  if table.row_count() > 20000 ||
    table.row_count() * table.headers().length() > 200000 {
    raise @merge.LimitExceeded(
      "browser input exceeds 20000 records or 200000 cells; use the CLI",
    )
  }
  table
}

///|
fn bounded_json(source : String) -> Json raise {
  if source.length() > 8000000 {
    raise @merge.LimitExceeded(
      "browser JSON exceeds 8000000 UTF-16 units; use the CLI",
    )
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for i in 0..<source.length() {
    let c = source[i]
    if quoted {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        quoted = false
      }
    } else if c == '"' {
      quoted = true
    } else if c == '{' || c == '[' {
      depth += 1
      if depth > 64 {
        raise @merge.InvalidReview("JSON nesting exceeds 64")
      }
    } else if c == '}' || c == ']' {
      depth -= 1
      if depth < 0 {
        raise @merge.InvalidReview("invalid JSON closing delimiter")
      }
    }
  }
  @json.parse(source) catch {
    _ =>
      raise @merge.InvalidReview(
        "invalid JSON syntax; check the review or key array",
      )
  }
}

///|
fn bundle(source : String) -> @merge.ReviewBundle raise {
  if source.length() > 8000000 {
    raise @merge.LimitExceeded(
      "browser review exceeds 8000000 UTF-16 units; use the CLI",
    )
  }
  // Preflight snapshot sizes before the full core import. The core then rejects
  // duplicate/unknown fields, versions and decisions using its strict parser.
  guard bounded_json(source) is Object(fields) else {
    raise @merge.InvalidReview("expected a review bundle object")
  }
  for name in ["base", "ours", "theirs"] {
    guard fields.get(name) is Some(String(csv)) else {
      raise @merge.InvalidReview(
        "review bundle requires original CSV snapshots",
      )
    }
    ignore(input(csv, "csv"))
  }
  @merge.ReviewBundle::from_json(source)
}

///|
fn snapshot(review : @merge.ReviewBundle) -> Json raise {
  let wire = review.to_json()
  let report = review.plan().report()
  if wire.stringify().length() > 8000000 ||
    report.stringify().length() > 8000000 {
    raise @merge.LimitExceeded(
      "browser review/report exceeds 8000000 UTF-16 units; nothing was truncated; use the CLI",
    )
  }
  { "review": wire, "report": report }
}

///|
fn reply(action : () -> Json raise) -> String {
  try action() catch {
    @merge.MergeError::_ as error =>
      ({ "ok": false, "message": error.diagnostic() } : Json).stringify()
    error =>
      (
        {
          "ok": false,
          "message": "Invalid input: \{error}; check JSON syntax and input fields",
        } : Json).stringify()
  } noraise {
    value => ({ "ok": true, "value": value } : Json).stringify()
  }
}

///|
/// String-only browser ABI. Domain validation and merge/review are core calls.
pub fn mt_begin(
  base : String,
  ours : String,
  theirs : String,
  format : String,
  keys_json : String,
  ordering : String,
  columns_json : String,
  rows_json : String,
  evolution_json : String,
  review_json : String,
) -> String {
  reply(() => {
    let b = input(base, format)
    let o = input(ours, format)
    let t = input(theirs, format)
    guard bounded_json(keys_json) is Array(parts) &&
      !parts.is_empty() &&
      parts.length() <= 512 else {
      raise @merge.InvalidKey(
        "key selection must be a JSON array of 1..512 header strings",
      )
    }
    for source in [columns_json, rows_json, evolution_json] {
      ignore(bounded_json(source))
    }
    let keys = parts.map(part => {
      match part {
        String(s) => s
        _ => raise @merge.InvalidKey("key names must be strings")
      }
    })
    let columns = @merge.parse_column_lineage(columns_json)
    let rows = @merge.parse_row_lineage(rows_json)
    let evolution = @merge.parse_column_evolution(evolution_json)
    let order = @merge.RowOrder::parse(ordering)
    let plan = if review_json != "" {
      if order != @merge.Lexical ||
        !columns.is_empty() ||
        !rows.is_empty() ||
        !evolution.is_empty() {
        raise @merge.InvalidReview(
          "resume uses the bundle's policies; clear policy overrides before replay",
        )
      }
      bundle(review_json).replay(b, o, t, key=keys)
    } else {
      @merge.merge(
        b,
        o,
        t,
        key=keys,
        row_order=order,
        column_lineage=columns,
        row_lineage=rows,
        column_evolution=evolution,
      )
    }
    snapshot(@merge.ReviewBundle::from_plan(plan))
  })
}

///|
pub fn mt_open(source : String) -> String {
  reply(() => snapshot(bundle(source)))
}

///|
pub fn mt_update(source : String, edits_json : String) -> String {
  reply(() => {
    ignore(bounded_json(edits_json))
    let before = bundle(source)
    let after = before.revise(@merge.parse_review_edits(edits_json))
    let value = snapshot(after)
    guard value is Object(fields) else { abort("snapshot object") }
    let audit = after.changes_report(before)
    if audit.stringify().length() > 8000000 {
      raise @merge.LimitExceeded(
        "browser audit exceeds 8000000 UTF-16 units; nothing was truncated; use the CLI",
      )
    }
    fields["audit"] = audit
    value
  })
}

///|
pub fn mt_export(source : String, format : String) -> String {
  reply(() => {
    let table = bundle(source).plan().finish().table()
    let text = match format {
      "csv" => table.to_csv()
      "tsv" => table.to_tsv()
      _ => raise @merge.InvalidReview("choose csv or tsv for export")
    }
    { "text": text, "format": format }
  })
}
