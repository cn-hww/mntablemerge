///|
fn collaborative_fixture() -> @mntablemerge.ReviewBundle raise @mntablemerge.MergeError {
  @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(
      @mntablemerge.parse_csv("id,v,w\n007,base,base\n"),
      @mntablemerge.parse_csv("id,v,w\n007,ours,ours\n"),
      @mntablemerge.parse_csv("id,v,w\n007,theirs,theirs\n"),
      key=["id"],
    ),
  )
}

///|
test "combine independent assignments deduplicates agreeing choices and is order independent" {
  let baseline = collaborative_fixture()
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "w")
  let first = baseline.resolve([{ target: v, choice: @mntablemerge.Ours, }])
  let second = baseline.resolve([
    { target: w, choice: @mntablemerge.Value("東京\t\"007\"\n"), },
  ])
  let combined = baseline.combine([first, second, first])
  assert_eq(combined.plan().finish().table().rows(), [
    ["007", "ours", "東京\t\"007\"\n"],
  ])
  assert_eq(combined.to_json(), baseline.combine([second, first]).to_json())
  assert_eq(baseline.combine([first]).plan().conflicts().length(), 1)
  assert_eq(baseline.combine([]).to_json(), baseline.to_json())
  assert_eq(
    combined.combine([combined, combined]).to_json(),
    combined.to_json(),
  )
  assert_eq(
    @mntablemerge.ReviewBundle::from_json(combined.to_json().stringify()).to_json(),
    combined.to_json(),
  )
  assert_eq(baseline.plan().decisions(), [])
  let many = Array::make(256, first)
  assert_eq(baseline.combine(many).plan().decisions().length(), 1)
  many.push(second)
  try baseline.combine(many) catch {
    @mntablemerge.LimitExceeded(_) => ()
    _ => fail("wrong batch boundary")
  } noraise {
    _ => fail("unbounded batch")
  }
  assert_eq(baseline.combine([first, second]).to_json(), combined.to_json())
}

///|
test "combine refuses disagreement implicit revision and revocation atomically" {
  let baseline = collaborative_fixture()
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "v")
  let first = baseline.resolve([{ target: v, choice: @mntablemerge.Ours, }])
  let opposite = baseline.resolve([{ target: v, choice: @mntablemerge.Theirs, }])
  let before = baseline.to_json()
  try baseline.combine([first, opposite]) catch {
    @mntablemerge.InvalidReview(reason) =>
      assert_true(reason.contains("disagree"))
    _ => fail("wrong disagreement")
  } noraise {
    _ => fail("overwrote disagreement")
  }
  for changed in [baseline, opposite, first.revise([@mntablemerge.Revoke(v)])] {
    try first.combine([changed]) catch {
      @mntablemerge.InvalidReview(reason) =>
        assert_true(reason.contains("baseline decision"))
      _ => fail("wrong inheritance")
    } noraise {
      _ => fail("silently changed baseline")
    }
  }
  assert_eq(baseline.to_json(), before)
  assert_eq(first.combine([first]).to_json(), first.to_json())
}

///|
test "combine binds all original snapshots keys ordering and both lineages" {
  let b = @mntablemerge.parse_csv("id,v\na,base\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs\n")
  let baseline = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  )
  for
    plan in [
      @mntablemerge.merge(b, @mntablemerge.parse_csv("id,v\na,changed\n"), t, key=[
        "id",
      ]),
      @mntablemerge.merge(b, o, t, key=["v"]),
      @mntablemerge.merge(
        b,
        o,
        t,
        key=["id"],
        row_order=@mntablemerge.OursOrder,
      ),
      @mntablemerge.merge(b, o, t, key=["id"], column_lineage=[
        { base: "v", ours: "v", theirs: "v", output: "value", },
      ]),
      @mntablemerge.merge(b, o, t, key=["id"], row_lineage=[
        row_link("a", "a", "a", "out"),
      ]),
    ] {
    try baseline.combine([@mntablemerge.ReviewBundle::from_plan(plan)]) catch {
      @mntablemerge.InvalidReview(_) => ()
      _ => fail("wrong binding error")
    } noraise {
      _ => fail("accepted foreign review")
    }
  }
  let mapped = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(
      b,
      o,
      t,
      key=["id"],
      row_lineage=[row_link("a", "a", "a", "out")],
      column_lineage=[{ base: "v", ours: "v", theirs: "v", output: "value", }],
      row_order=@mntablemerge.BaseOrder,
    ),
  )
  let reviewed = mapped.resolve([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["out"]), "value"),
      choice: @mntablemerge.Theirs,
    },
  ])
  let result = mapped.combine([reviewed]).plan()
  assert_eq(result.row_lineage(), mapped.plan().row_lineage())
  assert_eq(result.column_lineage(), mapped.plan().column_lineage())
  assert_eq(result.row_order(), @mntablemerge.BaseOrder)
  assert_eq(result.finish().table().to_csv(), "id,value\nout,theirs\n")
}

///|
test "combine structural row selections preserves indivisible records and phase boundaries" {
  let b = @mntablemerge.parse_csv("id\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours-a\nb,ours-b\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs-a\nb,theirs-b\n")
  let baseline = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  )
  let a = baseline.resolve([
    {
      target: @mntablemerge.Row(@mntablemerge.RowKey(["a"])),
      choice: @mntablemerge.Ours,
    },
  ])
  let z = baseline.resolve([
    {
      target: @mntablemerge.Row(@mntablemerge.RowKey(["b"])),
      choice: @mntablemerge.Theirs,
    },
  ])
  assert_eq(
    baseline.combine([a, z]).plan().finish().table().to_csv(),
    "id,v\na,ours-a\nb,theirs-b\n",
  )
  let structural = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(
      @mntablemerge.parse_csv("id,v\na,base\n"),
      @mntablemerge.parse_csv("id\na\nb\n"),
      @mntablemerge.parse_csv("id,v\na,changed\n"),
      key=["id"],
    ),
  )
  let kept = structural.resolve([
    { target: @mntablemerge.Column("v"), choice: @mntablemerge.Keep, },
  ])
  let combined = structural.combine([kept])
  assert_eq(combined.plan().conflicts()[0].kind, @mntablemerge.MissingCell)
  let filled = combined.resolve([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "v"),
      choice: @mntablemerge.Value(""),
    },
  ])
  assert_eq(
    combined.combine([filled]).plan().finish().table().to_csv(),
    "id,v\na,changed\nb,\n",
  )
  assert_eq(
    structural.plan().conflicts()[0].kind,
    @mntablemerge.ColumnDeleteEdit,
  )
}
