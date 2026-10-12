///|
test "assigned sheets preserve unassigned conflicts canonical order and exact values" {
  let b = @mntablemerge.parse_csv("id,v,w\n007,base,base\n")
  let o = @mntablemerge.parse_csv("id,v,w\n007,ours,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\n007,theirs,theirs\n")
  let p = @mntablemerge.merge(b, o, t, key=["id"])
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "w")
  let sheet = p.review_sheet_for([v])
  assert_eq(sheet.row_count(), 2)
  assert_eq(sheet.rows()[0][0], "mntablemerge/sheet-2")
  let rows = sheet.rows()
  rows[1][6] = "value"
  rows[1][7] = "東京\t\"007\"\n"
  let selected = @mntablemerge.parse_tsv(
    @mntablemerge.Table::from_rows(sheet.headers(), rows).to_tsv(),
  )
  let next = p.apply_review_sheet_for([v], selected)
  assert_eq(next.conflicts().map(c => c.target), [w])
  assert_eq(
    next.decisions()[0].choice,
    @mntablemerge.Value("東京\t\"007\"\n"),
  )
  assert_eq(p.conflicts().length(), 2)
  assert_eq(p.review_sheet_for([v, w]), p.review_sheet_for([w, v]))
  let empty = p.review_sheet_for([])
  assert_eq(p.apply_review_sheet_for([], empty).report(), p.report())
  assert_eq(
    @mntablemerge.parse_review_targets("[{\"row\":[\"007\"],\"column\":\"v\"}]"),
    [v],
  )
}

///|
test "assigned sheet refuses changed scope missing evidence stale data and recovers" {
  let b = @mntablemerge.parse_csv("id,v,w\na,b,b\n")
  let o = @mntablemerge.parse_csv("id,v,w\na,o,o\n")
  let t = @mntablemerge.parse_csv("id,v,w\na,t,t\n")
  let p = @mntablemerge.merge(b, o, t, key=["id"])
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "w")
  let sheet = p.review_sheet_for([v])
  for targets in [[w], [v, w]] {
    try p.apply_review_sheet_for(targets, sheet) catch {
      _ => ()
    } noraise {
      _ => fail("scope changed")
    }
  }
  try p.apply_review_sheet(sheet) catch {
    _ => ()
  } noraise {
    _ => fail("accepted scoped sheet as full review")
  }
  let missing = @mntablemerge.Table::from_rows(sheet.headers(), [
    sheet.rows()[0],
  ])
  try p.apply_review_sheet_for([v], missing) catch {
    _ => ()
  } noraise {
    _ => fail("assigned evidence lost")
  }
  let stale = @mntablemerge.merge(
    b,
    @mntablemerge.parse_csv("id,v,w\na,o,changed\n"),
    t,
    key=["id"],
  )
  try stale.apply_review_sheet_for([v], sheet) catch {
    _ => ()
  } noraise {
    _ => fail("ignored unassigned input data")
  }
  let rows = sheet.rows()
  rows[1][6] = "ours"
  let updated = p.apply_review_sheet_for(
    [v],
    @mntablemerge.Table::from_rows(sheet.headers(), rows),
  )
  try updated.review_sheet_for([v]) catch {
    _ => ()
  } noraise {
    _ => fail("assigned resolved target")
  }
  assert_eq(updated.conflicts()[0].target, w)
}

///|
test "assignment parser rejects malformed duplicate unknown and dimensional boundaries" {
  for
    source in [
      "{}", "[{}]", "[{\"row\":[]}]", "[{\"column\":\"\"}]", "[{\"row\":[\"\"]}]",
      "[{\"column\":\"v\",\"ignored\":true}]", "[{\"column\":\"v\",\"column\":\"w\"}]",
      "[{\"column\":\"v\"},{\"column\":\"v\"}]", "[{\"column\":\"\\uD800\"}]",
    ] {
    try @mntablemerge.parse_review_targets(source) catch {
      _ => ()
    } noraise {
      _ => fail("bad assignment accepted")
    }
  }
  for count in [512, 513] {
    let source = "[{\"row\":[" + Array::make(count, "\"x\"").join(",") + "]}]"
    if count == 512 {
      assert_eq(@mntablemerge.parse_review_targets(source).length(), 1)
    } else {
      try @mntablemerge.parse_review_targets(source) catch {
        _ => ()
      } noraise {
        _ => fail("oversized key")
      }
    }
  }
  let same = @mntablemerge.parse_csv("id,v\na,b\n")
  let p = @mntablemerge.merge(same, same, same, key=["id"])
  try p.review_sheet_for([@mntablemerge.Column("v")]) catch {
    _ => ()
  } noraise {
    _ => fail("unknown assignment")
  }
  try p.review_sheet_for(Array::make(100000, @mntablemerge.Column("v"))) catch {
    @mntablemerge.LimitExceeded(_) => ()
    _ => fail("wrong count diagnostic")
  } noraise {
    _ => fail("unbounded assignment")
  }
  assert_eq(@mntablemerge.parse_review_targets("[]"), [])
}
