///|
test "review sheet round trips exact evidence blank versus empty and canonical row order" {
  let b = @mntablemerge.parse_csv("id,v,w\n007,base,base\n")
  let o = @mntablemerge.parse_csv("id,v,w\n007,ours,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\n007,theirs,theirs\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let sheet = plan.review_sheet()
  assert_eq(@mntablemerge.parse_tsv(sheet.to_tsv()), sheet)
  assert_eq(plan.apply_review_sheet(sheet).report(), plan.report())
  let rows = sheet.rows()
  rows[1][6] = "value"
  rows[1][7] = "\"reviewed\"\t東京\nnext"
  let partial = plan.apply_review_sheet(
    @mntablemerge.Table::from_rows(sheet.headers(), rows),
  )
  assert_eq(partial.conflicts().length(), 1)
  rows[2][6] = "value"
  rows[2][7] = ""
  let edited = @mntablemerge.Table::from_rows(sheet.headers(), rows)
  let complete = plan.apply_review_sheet(
    @mntablemerge.parse_tsv(edited.to_tsv()),
  )
  assert_eq(complete.finish().table().rows(), [
    ["007", "\"reviewed\"\t東京\nnext", ""],
  ])
  assert_eq(
    plan
    .apply_review_sheet(
      @mntablemerge.Table::from_rows(sheet.headers(), [
        rows[0],
        rows[2],
        rows[1],
      ]),
    )
    .report(),
    complete.report(),
  )
  assert_eq(plan.conflicts().length(), 2)
  assert_eq(sheet.rows()[1][6], "")
  assert_eq(
    complete.apply_review_sheet(complete.review_sheet()).report(),
    complete.report(),
  )
  let bundle = @mntablemerge.ReviewBundle::from_json(
    @mntablemerge.ReviewBundle::from_plan(complete).to_json().stringify(),
  )
  assert_eq(
    bundle.replay(b, o, t, key=["id"]).finish().table(),
    complete.finish().table(),
  )
}

///|
test "sheet binds nonconflicting data snapshots order key and previous decisions" {
  let b = @mntablemerge.parse_csv("id,v,extra\na,base,keep\nz,same,untouched\n")
  let o = @mntablemerge.parse_csv("id,v,extra\na,ours,keep\nz,same,untouched\n")
  let t = @mntablemerge.parse_csv(
    "id,v,extra\na,theirs,keep\nz,same,untouched\n",
  )
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let sheet = plan.review_sheet()
  for
    other in [
      @mntablemerge.merge(
        b,
        @mntablemerge.parse_csv("id,v,extra\na,ours,keep\nz,same,changed\n"),
        t,
        key=["id"],
      ),
      @mntablemerge.merge(
        b,
        o,
        t,
        key=["id"],
        row_order=@mntablemerge.OursOrder,
      ),
      @mntablemerge.merge(
        @mntablemerge.parse_csv("id,v,extra\nz,same,untouched\na,base,keep\n"),
        o,
        t,
        key=["id"],
      ),
      @mntablemerge.resolve(plan, [
        {
          target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v"),
          choice: @mntablemerge.Ours,
        },
      ]),
    ] {
    try other.apply_review_sheet(sheet) catch {
      _ => ()
    } noraise {
      _ => fail("accepted stale sheet")
    }
  }
  let rows = sheet.rows()
  rows[1][6] = "theirs"
  assert_eq(
    plan
    .apply_review_sheet(@mntablemerge.Table::from_rows(sheet.headers(), rows))
    .finish()
    .table(),
    t,
  )
}

///|
test "sheet rejects changed evidence headers duplicates missing rows unused text and choices atomically" {
  let b = @mntablemerge.parse_csv("id,v,w\na,base,base\n")
  let o = @mntablemerge.parse_csv("id,v,w\na,ours,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\na,theirs,theirs\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let sheet = plan.review_sheet()
  for column in 0..<8 {
    let rows = sheet.rows()
    rows[1][column] = if column == 6 { "keep" } else { "altered" }
    try
      plan.apply_review_sheet(
        @mntablemerge.Table::from_rows(sheet.headers(), rows),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted altered sheet field")
    }
    assert_eq(plan.apply_review_sheet(sheet).report(), plan.report())
  }
  let rows = sheet.rows()
  for
    records in [
      [rows[0], rows[1]],
      [rows[0], rows[1], rows[1]],
      [rows[1], rows[0], rows[2]],
    ] {
    try
      plan.apply_review_sheet(
        @mntablemerge.Table::from_rows(sheet.headers(), records),
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted missing duplicate or displaced binding")
    }
  }
  let headers = sheet.headers()
  headers[7] = "unrecognized"
  try
    plan.apply_review_sheet(@mntablemerge.Table::from_rows(headers, rows))
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted unknown column")
  }
  let mixed = sheet.rows()
  mixed[1][6] = "ours"
  mixed[2][6] = "theirs"
  mixed[2][7] = "must not be ignored"
  try
    plan.apply_review_sheet(
      @mntablemerge.Table::from_rows(sheet.headers(), mixed),
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("discarded unused custom text")
  }
  assert_eq(plan.decisions(), [])
  mixed[2][7] = ""
  assert_eq(
    plan
    .apply_review_sheet(@mntablemerge.Table::from_rows(sheet.headers(), mixed))
    .finish()
    .table()
    .rows(),
    [["a", "ours", "theirs"]],
  )
}

///|
test "structural sheet exposes a new phase and lineage uses output coordinates" {
  let b = @mntablemerge.parse_csv("id,old\na,base\n")
  let o = @mntablemerge.parse_csv("id\na\nb\n")
  let t = @mntablemerge.parse_csv("id,old\na,changed\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let sheet = plan.review_sheet()
  let rows = sheet.rows()
  rows[1][6] = "keep"
  let kept = plan.apply_review_sheet(
    @mntablemerge.Table::from_rows(sheet.headers(), rows),
  )
  assert_eq(kept.conflicts()[0].kind, @mntablemerge.MissingCell)
  try kept.apply_review_sheet(sheet) catch {
    _ => ()
  } noraise {
    _ => fail("accepted previous review phase")
  }
  let next = kept.review_sheet()
  let filled = next.rows()
  filled[1][6] = "value"
  filled[1][7] = "007"
  assert_eq(
    kept
    .apply_review_sheet(@mntablemerge.Table::from_rows(next.headers(), filled))
    .finish()
    .table()
    .rows(),
    [["a", "changed"], ["b", "007"]],
  )
  let mapped = @mntablemerge.merge(
    @mntablemerge.parse_csv("id,v\na,base\n"),
    @mntablemerge.parse_csv("id,v\nlocal,ours\n"),
    @mntablemerge.parse_csv("id,v\na,theirs\n"),
    key=["id"],
    row_lineage=[row_link("a", "local", "a", "out")],
    column_lineage=[{ base: "v", ours: "v", theirs: "v", output: "value", }],
  )
  let mapped_sheet = mapped.review_sheet()
  let mapped_rows = mapped_sheet.rows()
  assert_eq(mapped_rows[1][1], "{\"row\":[\"out\"],\"column\":\"value\"}")
  mapped_rows[1][6] = "theirs"
  let result = mapped.apply_review_sheet(
    @mntablemerge.Table::from_rows(mapped_sheet.headers(), mapped_rows),
  )
  assert_eq(result.row_lineage(), mapped.row_lineage())
  assert_eq(result.column_lineage(), mapped.column_lineage())
  assert_eq(result.finish().table().to_csv(), "id,value\nout,theirs\n")
}

///|
test "sheet refuses full conflict capacity instead of truncating evidence" {
  let base = Array::makei(100000, i => [i.to_string(), "base"])
  let ours = Array::makei(100000, i => [i.to_string(), "ours"])
  let theirs = Array::makei(100000, i => [i.to_string(), "theirs"])
  let plan = @mntablemerge.merge(
    @mntablemerge.Table::from_rows(["id", "v"], base),
    @mntablemerge.Table::from_rows(["id", "v"], ours),
    @mntablemerge.Table::from_rows(["id", "v"], theirs),
    key=["id"],
  )
  assert_eq(plan.conflicts().length(), 100000)
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["0"]), "v")
  let scoped = plan.review_sheet_for([target])
  assert_eq(scoped.row_count(), 2)
  let rows = scoped.rows()
  rows[1][6] = "ours"
  let partial = plan.apply_review_sheet_for(
    [target],
    @mntablemerge.Table::from_rows(scoped.headers(), rows),
  )
  assert_eq(partial.conflicts().length(), 99999)
  try plan.review_sheet() catch {
    @mntablemerge.LimitExceeded(message) =>
      assert_true(message.contains("99999"))
    _ => fail("wrong diagnostic")
  } noraise {
    _ => fail("truncated conflict sheet")
  }
  assert_eq(plan.decisions(), [])
}
