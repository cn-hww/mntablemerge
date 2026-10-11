///|
test "explicit rename merges independent edits without inventing a column" {
  let b = @mntablemerge.parse_csv("id,price,stock\nz,007,1\n")
  let o = @mntablemerge.parse_csv("id,cost,stock\nz,007,2\n")
  let t = @mntablemerge.parse_csv("id,price,stock\nz,009,1\n")
  let columns : Array[@mntablemerge.ColumnLineage] = [
    { base: "price", ours: "cost", theirs: "price", output: "cost", },
  ]
  let plan = @mntablemerge.merge(b, o, t, key=["id"], column_lineage=columns)
  assert_eq(plan.finish().table().to_csv(), "id,cost,stock\nz,009,2\n")
  assert_eq(
    @mntablemerge.merge(b, o, t, key=["id"]).conflicts()[0].kind,
    @mntablemerge.ColumnDeleteEdit,
  )
  assert_eq(
    @mntablemerge.parse_column_lineage(
      @mntablemerge.column_lineage_json(columns).stringify(),
    ),
    columns,
  )
  let csv = plan.finish().table().to_csv()
  assert_eq(@mntablemerge.parse_csv(csv), plan.finish().table())
  columns.clear()
  let returned = plan.column_lineage()
  returned.clear()
  assert_eq(plan.column_lineage().length(), 1)
  assert_eq(plan.finish().table().to_csv(), csv)
}

///|
test "simultaneous mapping preserves cells under swaps and renamed compound keys" {
  let b = @mntablemerge.parse_csv("old_id,site,a,b\nz,2,A,B\na,1,C,D\n")
  let o = @mntablemerge.parse_csv("b,site,new_id,a\nB,2,z,A\nD,1,a,C\n")
  let t = @mntablemerge.parse_csv("id,site,a,b\nz,2,A,B\na,1,C,D\n")
  let mapping : Array[@mntablemerge.ColumnLineage] = [
    { base: "old_id", ours: "new_id", theirs: "id", output: "id", },
    { base: "a", ours: "a", theirs: "a", output: "b", },
    { base: "b", ours: "b", theirs: "b", output: "a", },
  ]
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id", "site"],
    row_order=@mntablemerge.OursOrder,
    column_lineage=mapping,
  )
  let expected = "id,site,b,a\nz,2,A,B\na,1,C,D\n"
  assert_eq(plan.finish().table().to_csv(), expected)
  assert_eq(
    @mntablemerge.merge(
      b,
      o,
      t,
      key=["id", "site"],
      row_order=@mntablemerge.OursOrder,
      column_lineage=[mapping[2], mapping[1], mapping[0]],
    )
    .finish()
    .table()
    .to_csv(),
    expected,
  )
  let bundle = @mntablemerge.ReviewBundle::from_json(
    @mntablemerge.ReviewBundle::from_plan(plan).to_json().stringify(),
  )
  assert_eq(
    bundle.replay(b, o, t, key=["id", "site"]).finish().table().to_csv(),
    expected,
  )
  assert_eq(b.headers(), ["old_id", "site", "a", "b"])
}

///|
test "rename conflicts use output coordinates and preserve original review snapshots" {
  let b = @mntablemerge.parse_csv("id,v,extra\na,old,keep\n")
  let o = @mntablemerge.parse_csv("id,local,extra\na,ours,keep\n")
  let t = @mntablemerge.parse_csv("id,remote,extra\na,theirs,keep\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"], column_lineage=[
    { base: "v", ours: "local", theirs: "remote", output: "value", },
  ])
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "value")
  assert_eq(plan.conflicts()[0].target, target)
  assert_eq(plan.conflicts()[0].ours[0].value, "ours")
  assert_true(plan.report().stringify().contains("column_lineage"))
  let wire = @mntablemerge.ReviewBundle::from_plan(plan).to_json().stringify()
  assert_true(wire.contains("id,local,extra"))
  assert_true(wire.contains("review-3"))
  let bundle = @mntablemerge.ReviewBundle::from_json(wire)
  let resolved = bundle.resolve([{ target, choice: @mntablemerge.Theirs, }])
  let restored = @mntablemerge.ReviewBundle::from_json(
    resolved.to_json().stringify(),
  )
  assert_eq(
    restored.replay(b, o, t, key=["id"]).finish().table().to_csv(),
    "id,value,extra\na,theirs,keep\n",
  )
  for
    stale in ["id,other,extra\na,ours,keep\n", "id,local,extra\na,ours,stale\n"] {
    try
      restored.replay(b, @mntablemerge.parse_csv(stale), t, key=["id"])
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted stale original input")
    }
  }
  try
    @mntablemerge.resolve(plan, [
      {
        target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "local"),
        choice: @mntablemerge.Ours,
      },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted source coordinate")
  }
  assert_eq(plan.conflicts().length(), 1)
  assert_eq(restored.plan().finish().resolutions()[0].conflict.target, target)
  for
    broken in [
      wire.replace_all(old="review-3", new="review-2"),
      wire.replace_all(old="\"column_lineage\"", new="\"extra\""),
      wire.replace_all(old="\"output\":\"value\"", new="\"output\":\"id\""),
    ] {
    try @mntablemerge.ReviewBundle::from_json(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted corrupt review mapping")
    }
  }
}

///|
test "lineage rejects missing duplicate empty colliding and malformed data and recovers" {
  let b = @mntablemerge.parse_csv("id,a,b\nx,A,B\n")
  let good : @mntablemerge.ColumnLineage = {
    base: "a",
    ours: "a",
    theirs: "a",
    output: "v",
  }
  try
    @mntablemerge.column_lineage_json([
      { ..good, output: "🛫".unsafe_substring(start=0, end=1), },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("serialized invalid Unicode")
  }
  for
    mapping in [
      [{ ..good, base: "missing", }],
      [{ ..good, ours: "missing", }],
      [{ ..good, theirs: "missing", }],
      [{ ..good, output: "", }],
      [{ ..good, output: "b", }],
      [good, good],
      [good, { ..good, base: "b", ours: "b", theirs: "b", }],
      [good, { base: "b", ours: "a", theirs: "b", output: "w", }],
      [good, { base: "b", ours: "b", theirs: "a", output: "w", }],
      [{ ..good, output: "🛫".unsafe_substring(start=0, end=1), }],
    ] {
    try @mntablemerge.merge(b, b, b, key=["id"], column_lineage=mapping) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid mapping")
    }
    assert_eq(
      @mntablemerge.merge(b, b, b, key=["id"], column_lineage=[good])
      .finish()
      .table()
      .to_csv(),
      "id,v,b\nx,A,B\n",
    )
  }
  for
    broken in [
      "{}", "[{}]", "[{\"base\":1,\"ours\":\"a\",\"theirs\":\"a\",\"output\":\"v\"}]",
      "[{\"base\":\"a\",\"ours\":\"a\",\"theirs\":\"a\",\"output\":\"v\",\"extra\":true}]",
      "[{\"base\":\"a\",\"base\":\"b\",\"ours\":\"a\",\"theirs\":\"a\",\"output\":\"v\"}]",
    ] {
    try @mntablemerge.parse_column_lineage(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed JSON")
    }
  }
  assert_eq(
    @mntablemerge.merge(b, b, b, key=["id"], column_lineage=[]).report(),
    @mntablemerge.merge(b, b, b, key=["id"]).report(),
  )
}

///|
test "lineage limits and other structural conflicts are not bypassed" {
  let headers = Array::makei(512, i => "c\{i}")
  let b = @mntablemerge.Table::from_rows(headers, [])
  let mapping : Array[@mntablemerge.ColumnLineage] = headers.map(name => {
    base: name,
    ours: name,
    theirs: name,
    output: "out_" + name,
  })
  assert_eq(
    @mntablemerge.merge(b, b, b, key=["out_c0"], column_lineage=mapping)
    .finish()
    .table()
    .headers(),
    headers.map(name => "out_" + name),
  )
  mapping.push(mapping[0])
  try @mntablemerge.column_lineage_json(mapping) catch {
    _ => ()
  } noraise {
    _ => fail("exported an unparseable oversized array")
  }
  try
    @mntablemerge.merge(b, b, b, key=["out_c0"], column_lineage=mapping)
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 mappings")
  }
  let base = @mntablemerge.parse_csv("id,v,old\nx,base,original\n")
  let ours = @mntablemerge.parse_csv("id,renamed\nx,base\n")
  let theirs = @mntablemerge.parse_csv("id,v,old\nx,base,changed\n")
  let plan = @mntablemerge.merge(base, ours, theirs, key=["id"], column_lineage=[
    { base: "v", ours: "renamed", theirs: "v", output: "value", },
  ])
  assert_eq(plan.conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
  assert_eq(
    @mntablemerge.resolve(plan, [
      { target: @mntablemerge.Column("old"), choice: @mntablemerge.Keep, },
    ])
    .finish()
    .table()
    .to_csv(),
    "id,value,old\nx,base,changed\n",
  )
}
