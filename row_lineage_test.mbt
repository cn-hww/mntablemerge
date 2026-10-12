///|
fn row_link(
  b : String,
  o : String,
  t : String,
  out : String,
) -> @mntablemerge.RowLineage {
  {
    base: @mntablemerge.RowKey([b]),
    ours: @mntablemerge.RowKey([o]),
    theirs: @mntablemerge.RowKey([t]),
    output: @mntablemerge.RowKey([out]),
  }
}

///|
test "identity migration preserves independent edits and owns its declarations" {
  let b = @mntablemerge.parse_csv("id,name,note\n007,old,base\nz,last,\n")
  let o = @mntablemerge.parse_csv("id,name,note\nlocal:007,new,base\nz,last,\n")
  let t = @mntablemerge.parse_csv("id,name,note\n007,old,audit\nz,last,\n")
  let links = [row_link("007", "local:007", "007", "canonical:007")]
  let plan = @mntablemerge.merge(b, o, t, key=["id"], row_lineage=links)
  let expected = "id,name,note\ncanonical:007,new,audit\nz,last,\n"
  assert_eq(plan.finish().table().to_csv(), expected)
  assert_eq(@mntablemerge.parse_csv(expected), plan.finish().table())
  assert_eq(
    @mntablemerge.parse_row_lineage(
      @mntablemerge.row_lineage_json(links).stringify(),
    ),
    links,
  )
  assert_eq(
    @mntablemerge.merge(b, o, t, key=["id"]).conflicts()[0].kind,
    @mntablemerge.RowDeleteEdit,
  )
  links.clear()
  plan.row_lineage().clear()
  plan.row_lineage()[0].output.components().clear()
  assert_eq(plan.finish().table().to_csv(), expected)
  assert_eq(plan.row_lineage().length(), 1)
  assert_eq(b.rows()[0][0], "007")
  assert_eq(
    @mntablemerge.merge(b, b, b, key=["id"], row_lineage=[]).report(),
    @mntablemerge.merge(b, b, b, key=["id"]).report(),
  )
}

///|
test "simultaneous identity cycles are independent of declaration order" {
  let table = @mntablemerge.parse_csv("id,value\nb,B\na,A\nc,C\n")
  let links = [
    row_link("a", "a", "a", "b"),
    row_link("b", "b", "b", "c"),
    row_link("c", "c", "c", "a"),
  ]
  let expected = "id,value\nc,B\nb,A\na,C\n"
  for mapping in [links, [links[2], links[0], links[1]]] {
    assert_eq(
      @mntablemerge.merge(
        table,
        table,
        table,
        key=["id"],
        row_order=@mntablemerge.BaseOrder,
        row_lineage=mapping,
      )
      .finish()
      .table()
      .to_csv(),
      expected,
    )
  }
  assert_eq(
    @mntablemerge.merge(table, table, table, key=["id"], row_lineage=links)
    .finish()
    .table()
    .to_csv(),
    "id,value\na,C\nb,A\nc,B\n",
  )
}

///|
test "compound identities compose with key column lineage and output review coordinates" {
  let b = @mntablemerge.parse_csv(
    "old_id,site,value,extra\na|b,東京,base,keep\n",
  )
  let o = @mntablemerge.parse_csv(
    "local_id,site,local,extra\nlocal,東京,ours,keep\n",
  )
  let t = @mntablemerge.parse_csv(
    "id,site,value,extra\na|b,東京,theirs,keep\n",
  )
  let out = @mntablemerge.RowKey(["airport:007", "東京"])
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id", "site"],
    column_lineage=[
      { base: "old_id", ours: "local_id", theirs: "id", output: "id", },
      { base: "value", ours: "local", theirs: "value", output: "value", },
    ],
    row_lineage=[
      {
        base: @mntablemerge.RowKey(["a|b", "東京"]),
        ours: @mntablemerge.RowKey(["local", "東京"]),
        theirs: @mntablemerge.RowKey(["a|b", "東京"]),
        output: out,
      },
    ],
  )
  let target = @mntablemerge.Cell(out, "value")
  assert_eq(plan.conflicts()[0].target, target)
  let wire = @mntablemerge.ReviewBundle::from_plan(plan).to_json().stringify()
  assert_true(wire.contains("review-4"))
  assert_true(wire.contains("old_id"))
  assert_true(wire.contains("local_id"))
  assert_true(plan.report().stringify().contains("row_lineage"))
  let bundle = @mntablemerge.ReviewBundle::from_json(wire)
  try
    bundle.resolve([
      {
        target: @mntablemerge.Cell(
          @mntablemerge.RowKey(["local", "東京"]),
          "value",
        ),
        choice: @mntablemerge.Ours,
      },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted source coordinates")
  }
  let reviewed = bundle.resolve([{ target, choice: @mntablemerge.Theirs, }])
  let restored = @mntablemerge.ReviewBundle::from_json(
    reviewed.to_json().stringify(),
  )
  assert_eq(
    restored.replay(b, o, t, key=["id", "site"]).finish().table().to_csv(),
    "id,site,value,extra\nairport:007,東京,theirs,keep\n",
  )
  for
    stale in [
      "local_id,site,local,extra\nother,東京,ours,keep\n", "local_id,site,local,extra\nlocal,東京,ours,changed\n",
    ] {
    try
      restored.replay(b, @mntablemerge.parse_csv(stale), t, key=["id", "site"])
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted stale input")
    }
  }
  for
    broken in [
      wire.replace_all(old="review-4", new="review-3"),
      wire.replace_all(old="\"row_lineage\"", new="\"unknown\""),
    ] {
    try @mntablemerge.ReviewBundle::from_json(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted unsupported bundle")
    }
  }
  assert_eq(bundle.plan().conflicts().length(), 1)
}

///|
test "row lineage rejects absent duplicate colliding empty malformed and oversized identities" {
  let b = @mntablemerge.parse_csv("id,v\na,A\nb,B\n")
  let good = row_link("a", "a", "a", "out")
  let bad_unicode = @mntablemerge.RowKey([
    "🛫".unsafe_substring(start=0, end=1),
  ])
  for
    links in [
      [row_link("missing", "a", "a", "out")],
      [row_link("a", "missing", "a", "out")],
      [row_link("a", "a", "missing", "out")],
      [row_link("a", "a", "a", "b")],
      [good, good],
      [good, row_link("b", "b", "b", "out")],
      [good, row_link("b", "a", "b", "other")],
      [good, row_link("b", "b", "a", "other")],
      [{ ..good, output: @mntablemerge.RowKey([]), }],
      [{ ..good, output: @mntablemerge.RowKey([""]), }],
      [{ ..good, output: @mntablemerge.RowKey(["x", "y"]), }],
      [{ ..good, output: bad_unicode, }],
    ] {
    try @mntablemerge.merge(b, b, b, key=["id"], row_lineage=links) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid lineage")
    }
    assert_eq(
      @mntablemerge.merge(b, b, b, key=["id"], row_lineage=[good])
      .finish()
      .table()
      .to_csv(),
      "id,v\nb,B\nout,A\n",
    )
  }
  let duplicate = @mntablemerge.parse_csv("id,v\na,A\na,B\n")
  try
    @mntablemerge.merge(duplicate, b, b, key=["id"], row_lineage=[good])
  catch {
    _ => ()
  } noraise {
    _ => fail("mapping hid duplicate original keys")
  }
  for
    bad in [
      "{}", "[{}]", "[{\"base\":\"a\",\"ours\":[\"a\"],\"theirs\":[\"a\"],\"output\":[\"b\"]}]",
      "[{\"base\":[\"a\"],\"ours\":[1],\"theirs\":[\"a\"],\"output\":[\"b\"]}]",
      "[{\"base\":[\"a\"],\"ours\":[\"a\"],\"theirs\":[\"a\"],\"output\":[\"b\"],\"extra\":true}]",
      "[{\"base\":[\"a\"],\"base\":[\"b\"],\"ours\":[\"a\"],\"theirs\":[\"a\"],\"output\":[\"b\"]}]",
    ] {
    try @mntablemerge.parse_row_lineage(bad) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed JSON")
    }
  }
  for links in [[{ ..good, output: bad_unicode, }], Array::make(100001, good)] {
    try @mntablemerge.row_lineage_json(links) catch {
      _ => ()
    } noraise {
      _ => fail("exported invalid lineage")
    }
    try @mntablemerge.merge(b, b, b, key=["id"], row_lineage=links) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid bounds")
    }
  }
  let parts = Array::makei(512, i => "v\{i}")
  let headers = Array::makei(512, i => "k\{i}")
  let wide = @mntablemerge.Table::from_rows(headers, [parts])
  let identity = @mntablemerge.RowKey(parts)
  assert_eq(
    @mntablemerge.merge(wide, wide, wide, key=headers, row_lineage=[
      { base: identity, ours: identity, theirs: identity, output: identity, },
    ])
    .finish()
    .table(),
    wide,
  )
  parts.push("extra")
  let over = @mntablemerge.RowKey(parts)
  try
    @mntablemerge.row_lineage_json([
      { base: over, ours: over, theirs: over, output: over, },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 parts")
  }
}

///|
test "row migration retains orthogonal structural review requirements" {
  let b = @mntablemerge.parse_csv("id,v,old\na,A,original\n")
  let o = @mntablemerge.parse_csv("id,v\nlocal,A\n")
  let t = @mntablemerge.parse_csv("id,v,old\na,A,changed\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"], row_lineage=[
    row_link("a", "local", "a", "out"),
  ])
  assert_eq(plan.conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
  assert_eq(
    @mntablemerge.resolve(plan, [
      { target: @mntablemerge.Column("old"), choice: @mntablemerge.Keep, },
    ])
    .finish()
    .table()
    .to_csv(),
    "id,v,old\nout,A,changed\n",
  )
}
