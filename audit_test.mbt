///|
test "review comparison reports addition replacement revocation with exact evidence and round trips" {
  let baseline = collaborative_fixture()
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "w")
  let old = baseline.resolve([{ target: v, choice: @mntablemerge.Ours, }])
  let changed = old.revise([
    @mntablemerge.Set({
      target: v,
      choice: @mntablemerge.Value("東京\t\"007\"\n"),
    }),
    @mntablemerge.Set({ target: w, choice: @mntablemerge.Value(""), }),
  ])
  let changes = changed.changes_since(old)
  assert_eq(changes.length(), 2)
  assert_eq(changes[0].target, v)
  assert_eq(changes[0].before.unwrap().choice, @mntablemerge.Ours)
  assert_eq(
    changes[0].after.unwrap().choice,
    @mntablemerge.Value("東京\t\"007\"\n"),
  )
  assert_eq(changes[0].after.unwrap().conflict.ours[0].value, "ours")
  assert_eq(changes[1].before, None)
  assert_eq(changes[1].after.unwrap().choice, @mntablemerge.Value(""))
  let reverse = old.changes_since(changed)
  for i in 0..<2 {
    assert_eq(reverse[i].before, changes[i].after)
    assert_eq(reverse[i].after, changes[i].before)
  }
  let undone = changed.revise([@mntablemerge.Revoke(v)])
  let revoked = undone.changes_since(changed)
  assert_eq(revoked.length(), 1)
  assert_eq(revoked[0].after, None)
  assert_eq(changed.changes_since(changed), [])
  let wire = changed.to_json().stringify()
  let restored = @mntablemerge.ReviewBundle::from_json(wire)
  assert_eq(restored.changes_report(old), changed.changes_report(old))
  let serialized = changed.changes_report(old).stringify()
  assert_eq(@json.parse(serialized), changed.changes_report(old))
  assert_true(serialized.contains("\\t\\\"007\\\"\\n"))
  changes[0].after.unwrap().conflict.ours.clear()
  changes.clear()
  assert_eq(
    changed.changes_since(old)[0].after.unwrap().conflict.ours[0].value,
    "ours",
  )
  assert_eq(old.plan().decisions().length(), 1)
  assert_eq(changed.to_json().stringify(), wire)
}

///|
test "structural review audit retains dropped values and explicit revoked dependencies" {
  let baseline = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(
      @mntablemerge.parse_csv("id,v\na,base\n"),
      @mntablemerge.parse_csv("id\na\nb\n"),
      @mntablemerge.parse_csv("id,v\na,changed\n"),
      key=["id"],
    ),
  )
  let column = @mntablemerge.Column("v")
  let cell = @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "v")
  let kept = baseline.resolve([{ target: column, choice: @mntablemerge.Keep, }])
  let filled = kept.resolve([
    { target: cell, choice: @mntablemerge.Value("007"), },
  ])
  let dropped = filled.revise([
    @mntablemerge.Set({ target: column, choice: @mntablemerge.Drop, }),
    @mntablemerge.Revoke(cell),
  ])
  let changes = dropped.changes_since(filled)
  assert_eq(changes.length(), 2)
  let structural = changes.filter(c => c.target == column)[0]
  assert_eq(structural.before.unwrap().choice, @mntablemerge.Keep)
  assert_eq(structural.after.unwrap().choice, @mntablemerge.Drop)
  assert_eq(structural.after.unwrap().conflict.base[0].value, "base")
  assert_eq(structural.after.unwrap().conflict.theirs[0].value, "changed")
  let dependency = changes.filter(c => c.target == cell)[0]
  assert_eq(dependency.before.unwrap().choice, @mntablemerge.Value("007"))
  assert_eq(dependency.before.unwrap().conflict.kind, @mntablemerge.MissingCell)
  assert_eq(dependency.after, None)
  assert_eq(dropped.plan().finish().table().to_csv(), "id\na\nb\n")
  assert_eq(filled.plan().finish().table().to_csv(), "id,v\na,changed\nb,007\n")
  assert_eq(
    dropped.revise([@mntablemerge.Revoke(column)]).changes_since(dropped)[0].after,
    None,
  )
}

///|
test "audit ignores decision ordering binds original policies and reports normalized coordinates" {
  let baseline = collaborative_fixture()
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["007"]), "w")
  let decisions : Array[@mntablemerge.Decision] = [
    { target: w, choice: @mntablemerge.Theirs, },
    { target: v, choice: @mntablemerge.Ours, },
  ]
  let first = baseline.resolve(decisions)
  let second = baseline.resolve([decisions[1], decisions[0]])
  assert_eq(first.changes_since(second), [])
  assert_eq(first.changes_since(baseline), second.changes_since(baseline))
  let b = @mntablemerge.parse_csv("id,v\na,base\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs\n")
  let mapped = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(
      b,
      o,
      t,
      key=["id"],
      column_lineage=[{ base: "v", ours: "v", theirs: "v", output: "value", }],
      row_lineage=[row_link("a", "a", "a", "out")],
      row_order=@mntablemerge.OursOrder,
    ),
  )
  let chosen = mapped.resolve([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["out"]), "value"),
      choice: @mntablemerge.Theirs,
    },
  ])
  assert_eq(
    chosen.changes_since(mapped)[0].target,
    @mntablemerge.Cell(@mntablemerge.RowKey(["out"]), "value"),
  )
  for
    plan in [
      @mntablemerge.merge(b, o, t, key=["id"]),
      @mntablemerge.merge(b, o, t, key=["v"]),
      @mntablemerge.merge(b, @mntablemerge.parse_csv("id,v\na,changed\n"), t, key=[
        "id",
      ]),
    ] {
    let other = @mntablemerge.ReviewBundle::from_plan(plan)
    try chosen.changes_report(other) catch {
      @mntablemerge.InvalidReview(_) => ()
      _ => fail("wrong mismatch error")
    } noraise {
      _ => fail("compared unrelated revisions")
    }
  }
  assert_eq(chosen.changes_since(mapped).length(), 1)
}

///|
test "audit refuses oversized wire output but keeps complete typed evidence" {
  let value = String::make(3000000, 'x')
  let b = @mntablemerge.Table::from_rows(["id", "v"], [["a", value]])
  let o = @mntablemerge.Table::from_rows(["id", "v"], [["a", value + "o"]])
  let t = @mntablemerge.Table::from_rows(["id", "v"], [["a", value + "t"]])
  let baseline = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  )
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let old = baseline.resolve([{ target, choice: @mntablemerge.Ours, }])
  let next = baseline.resolve([{ target, choice: @mntablemerge.Theirs, }])
  try next.changes_report(old) catch {
    @mntablemerge.LimitExceeded(_) => ()
    _ => fail("wrong wire size error")
  } noraise {
    _ => fail("silently truncated audit")
  }
  let changes = next.changes_since(old)
  assert_eq(changes[0].before.unwrap().conflict.base[0].value, value)
  assert_eq(changes[0].after.unwrap().conflict.theirs[0].value, value + "t")
  assert_eq(old.changes_since(old), [])
}
