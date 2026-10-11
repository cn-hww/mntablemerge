///|
test "source ordering preserves survivors and appends all absent rows lexically" {
  let b = @mntablemerge.parse_csv("id,v\nz,0\nb,0\na,0\n")
  let o = @mntablemerge.parse_csv("id,v\nb,1\nz,0\naa,new\n")
  let t = @mntablemerge.parse_csv("id,v\nz,0\nb,0\na,0\nc,new\n")
  for
    (order, expected) in [
      (@mntablemerge.Lexical, ["aa", "b", "c", "z"]),
      (@mntablemerge.BaseOrder, ["z", "b", "aa", "c"]),
      (@mntablemerge.OursOrder, ["b", "z", "aa", "c"]),
      (@mntablemerge.TheirsOrder, ["z", "b", "c", "aa"]),
    ] {
    let plan = @mntablemerge.merge(b, o, t, key=["id"], row_order=order)
    assert_eq(plan.row_order(), order)
    let table = plan.finish().table()
    assert_eq(table.rows().map(row => row[0]), expected)
    assert_eq(@mntablemerge.parse_csv(table.to_csv()), table)
    let imported = @mntablemerge.ReviewBundle::from_json(
      @mntablemerge.ReviewBundle::from_plan(plan).to_json().stringify(),
    )
    assert_eq(imported.replay(b, o, t, key=["id"]).finish().table(), table)
    assert_eq(
      @mntablemerge.merge(b, o, t, key=["id"], row_order=order).finish().table(),
      table,
    )
  }
  assert_eq(
    @mntablemerge.merge(b, o, t, key=["id"]).row_order(),
    @mntablemerge.Lexical,
  )
}

///|
test "ordering survives conflict resolution compound keys and empty preferred source" {
  let b = @mntablemerge.parse_csv("id,site,v\nz,2,old\na,1,old\n")
  let o = @mntablemerge.parse_csv("site,v,id\n1,ours,a\n2,old,z\n")
  let t = @mntablemerge.parse_csv("id,site,v\nz,2,old\na,1,theirs\n")
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id", "site"],
    row_order=@mntablemerge.OursOrder,
  )
  let resolved = @mntablemerge.resolve(plan, [
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a", "1"]), "v"),
      choice: @mntablemerge.Theirs,
    },
  ])
  assert_eq(resolved.finish().table().rows(), [
    ["a", "1", "theirs"],
    ["z", "2", "old"],
  ])
  assert_eq(plan.conflicts().length(), 1)
  let empty = @mntablemerge.parse_csv("id,site,v\n")
  assert_eq(
    @mntablemerge.merge(
      empty,
      o,
      empty,
      key=["id", "site"],
      row_order=@mntablemerge.BaseOrder,
    )
    .finish()
    .table()
    .rows(),
    [["a", "1", "ours"], ["z", "2", "old"]],
  )
}

///|
test "strict order import rejects unsupported metadata and recovers" {
  let b = @mntablemerge.parse_csv("id\nz\na\n")
  let bundle = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, b, b, key=["id"], row_order=@mntablemerge.BaseOrder),
  )
  let json = bundle.to_json().stringify()
  for
    broken in [
      json.replace_all(
        old="\"row_order\":\"base\"",
        new="\"row_order\":\"guess\"",
      ),
      json.replace_all(old="\"row_order\":\"base\"", new="\"row_order\":true"),
      json.replace_all(old="review-2", new="review-1"),
      json.replace_all(old="\"row_order\":\"base\"", new="\"extra\":\"base\""),
    ] {
    try @mntablemerge.ReviewBundle::from_json(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid order")
    }
  }
  assert_eq(
    @mntablemerge.ReviewBundle::from_json(json).plan().finish().table(),
    b,
  )
  assert_eq(@mntablemerge.RowOrder::parse("base").name(), "base")
}
