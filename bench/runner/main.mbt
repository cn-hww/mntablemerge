///|
fn digest(text : String) -> UInt {
  let mut hash = 2166136261U
  for i in 0..<text.length() {
    hash = (hash ^ text[i].to_uint()) * 16777619U
  }
  hash
}

///|
fn identity(row : Int) -> String {
  let digits = row.to_string()
  "k" + String::make(6 - digits.length(), '0') + digits
}

///|
fn main raise {
  let args = @env.args()
  // Node includes its own executable prefix; all modes use the final 4 args.
  guard args.length() >= 5 else {
    fail("ROWS COLUMNS CONFLICT_ROW_PERCENT merge|review|lineage|unique")
  }
  let args = args[args.length() - 4:].to_owned()
  let n = @string.parse_int(args[0])
  let width = @string.parse_int(args[1])
  let density = @string.parse_int(args[2])
  let mode = args[3]
  guard n > 0 &&
    n <= 100000 &&
    width >= 3 &&
    width <= 64 &&
    n * width <= 2000000 &&
    density >= 0 &&
    density <= 100 &&
    ["merge", "review", "lineage", "unique"].contains(mode) else {
    fail("invalid benchmark dimensions/mode")
  }
  let headers = ["id"]
  for c in 1..<width {
    headers.push("v\{c}")
  }
  let original = Array::makei(n, r => {
    Array::makei(width, c => {
      if c == 0 {
        identity(r)
      } else if mode == "unique" {
        "\{r}:\{c}"
      } else {
        "base"
      }
    })
  })
  let local_rows = original.map(row => row.copy())
  let remote = original.map(row => row.copy())
  let mut count = 0
  for r in 0..<n {
    local_rows[r][1] = "local"
    remote[r][2] = "remote"
    if r % 100 < density {
      remote[r][1] = "conflict"
      count += 1
    }
    if mode == "lineage" && r % 100 == 0 {
      local_rows[r][0] = "new-" + identity(r)
    }
  }
  let local_headers = headers.copy()
  if mode == "lineage" {
    local_headers[1] = "price"
  }
  let b = @merge.Table::from_rows(headers, original)
  let o = @merge.Table::from_rows(local_headers, local_rows)
  let t = @merge.Table::from_rows(headers, remote)
  let columns : Array[@merge.ColumnLineage] = if mode == "lineage" {
    [{ base: "v1", ours: "price", theirs: "v1", output: "v1", }]
  } else {
    []
  }
  let links : Array[@merge.RowLineage] = []
  if mode == "lineage" {
    for r in 0..<n {
      if r % 100 == 0 {
        links.push({
          base: @merge.RowKey([identity(r)]),
          ours: @merge.RowKey(["new-" + identity(r)]),
          theirs: @merge.RowKey([identity(r)]),
          output: @merge.RowKey([identity(r)]),
        })
      }
    }
  }
  let timer = @bench.monotonic_clock_start()
  let plan = @merge.merge(
    b,
    o,
    t,
    key=["id"],
    column_lineage=columns,
    row_lineage=links,
  )
  let pending = plan.conflicts()
  assert_eq(pending.length(), count)
  let decisions = pending.map(c => @merge.Decision::{
    target: c.target,
    choice: @merge.Value("reviewed"),
  })
  let resolved = @merge.resolve(plan, decisions)
  let report_hash = digest(resolved.report().stringify())
  let mut bundle_hash = 0U
  let table = if mode == "review" {
    let wire = @merge.ReviewBundle::from_plan(resolved).to_json().stringify()
    bundle_hash = digest(wire)
    @merge.ReviewBundle::from_json(wire)
    .replay(b, o, t, key=["id"])
    .finish()
    .table()
  } else {
    resolved.finish().table()
  }
  let rows = table.rows()
  assert_eq(rows.length(), n)
  assert_eq(table.headers(), headers)
  for r in 0..<n {
    assert_eq(rows[r][0], identity(r))
    for c in 1..<width {
      let expected = if c == 1 {
        if r % 100 < density {
          "reviewed"
        } else {
          "local"
        }
      } else if c == 2 {
        "remote"
      } else if mode == "unique" {
        "\{r}:\{c}"
      } else {
        "base"
      }
      assert_eq(rows[r][c], expected)
    }
  }
  let csv = table.to_csv()
  let fingerprint : Json = {
    "csv": digest(csv),
    "report": report_hash,
    "bundle": bundle_hash,
    "rows": n,
    "columns": width,
    "conflicts": count,
  }
  let output : Json = {
    "mode": mode,
    "fingerprint": fingerprint,
    "elapsed_us": @bench.monotonic_clock_end(timer),
  }
  println(output.stringify())
}
