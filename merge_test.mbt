///|
fn one(value : String) -> @mntablemerge.Table raise @mntablemerge.MergeError {
  @mntablemerge.Table::from_rows(["id", "v"], [["x", value]])
}

///|
test "exhaustive scalar three-way truth table and explicit recovery" {
  for b in ["", "0", "1", "🛫"] {
    for o in ["", "0", "1", "🛫"] {
      for t in ["", "0", "1", "🛫"] {
        let plan = @mntablemerge.merge(one(b), one(o), one(t), key=["id"])
        let expected = if o == t {
          Some(o)
        } else if o == b {
          Some(t)
        } else if t == b {
          Some(o)
        } else {
          None
        }
        match expected {
          Some(v) => {
            assert_eq(plan.conflicts(), [])
            assert_eq(plan.finish().table().rows(), [["x", v]])
          }
          None => {
            assert_eq(plan.conflicts().length(), 1)
            assert_eq(plan.conflicts()[0].kind, @mntablemerge.CellEdit)
            try plan.finish() catch {
              _ => ()
            } noraise {
              _ => fail("exported unresolved table")
            }
            let fixed = @mntablemerge.resolve(plan, [
              {
                target: @mntablemerge.Cell(@mntablemerge.RowKey(["x"]), "v"),
                choice: @mntablemerge.Ours,
              },
            ])
            assert_eq(fixed.finish().table().rows(), [["x", o]])
            assert_eq(plan.conflicts().length(), 1)
            assert_eq(fixed.finish().resolutions()[0].conflict.base[0].value, b)
          }
        }
        let swapped = @mntablemerge.merge(one(b), one(t), one(o), key=["id"])
        assert_eq(plan.conflicts().length(), swapped.conflicts().length())
      }
    }
  }
}

///|
test "independent edits row reordering additions and deterministic output" {
  let b = @mntablemerge.parse_csv("id,p,q\nb,10,100\na,20,200\n")
  let o = @mntablemerge.parse_csv("q,id,p\n200,a,25\n100,b,10\n")
  let t = @mntablemerge.parse_csv("id,p,q\nb,10,120\na,20,200\nc,3,4\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let expected = "id,p,q\na,25,200\nb,10,120\nc,3,4\n"
  for _ in 0..<10 {
    assert_eq(
      @mntablemerge.merge(b, o, t, key=["id"]).finish().table().to_csv(),
      expected,
    )
  }
  assert_eq(plan.finish().table().to_csv(), expected)
  assert_eq(
    @mntablemerge.merge(b, t, o, key=["id"]).finish().table().to_csv(),
    expected,
  )
}

///|
test "new row cross new column requires explicit value rather than empty" {
  let b = @mntablemerge.parse_csv("id,v\na,old\n")
  let o = @mntablemerge.parse_csv("id,v,owner\na,old,alice\n")
  let t = @mntablemerge.parse_csv("id,v\na,old\nb,new\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  assert_eq(plan.conflicts()[0].kind, @mntablemerge.MissingCell)
  assert_eq(plan.conflicts()[0].ours, [])
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "owner")
  try
    @mntablemerge.resolve(plan, [{ target, choice: @mntablemerge.Ours, }])
  catch {
    _ => ()
  } noraise {
    _ => fail("selected absent source")
  }
  let resolved = @mntablemerge.resolve(plan, [
    { target, choice: @mntablemerge.Value(""), },
  ])
  assert_eq(
    resolved.finish().table().to_csv(),
    "id,v,owner\na,old,alice\nb,new,\n",
  )
  assert_eq(
    @mntablemerge.parse_csv(resolved.finish().table().to_csv()),
    resolved.finish().table(),
  )
}

///|
test "column deletion competes with edits and newly inserted records" {
  let b = @mntablemerge.parse_csv("id,v\na,old\n")
  let o = @mntablemerge.parse_csv("id\na\n")
  for source in ["id,v\na,edit\n", "id,v\na,old\nb,new\n"] {
    let t = @mntablemerge.parse_csv(source)
    let plan = @mntablemerge.merge(b, o, t, key=["id"])
    assert_eq(plan.conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
    let kept = @mntablemerge.resolve(plan, [
      { target: @mntablemerge.Column("v"), choice: @mntablemerge.Keep, },
    ])
    assert_eq(kept.finish().table(), t)
    let dropped = @mntablemerge.resolve(plan, [
      { target: @mntablemerge.Column("v"), choice: @mntablemerge.Drop, },
    ])
    assert_eq(dropped.finish().table().headers(), ["id"])
    assert_eq(
      dropped.finish().resolutions()[0].conflict.theirs.length(),
      t.row_count(),
    )
    let swapped = @mntablemerge.merge(b, t, o, key=["id"])
    assert_eq(swapped.conflicts()[0].target, @mntablemerge.Column("v"))
  }
  assert_eq(@mntablemerge.merge(b, o, b, key=["id"]).finish().table(), o)
}

///|
test "row deletion competes with added column and is auditable" {
  let b = @mntablemerge.parse_csv("id,v\na,old\n")
  let o = @mntablemerge.parse_csv("id,v\n")
  let t = @mntablemerge.parse_csv("id,v,new\na,old,data\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  assert_eq(plan.conflicts()[0].kind, @mntablemerge.RowDeleteEdit)
  let target = @mntablemerge.Row(@mntablemerge.RowKey(["a"]))
  assert_eq(
    @mntablemerge.resolve(plan, [{ target, choice: @mntablemerge.Keep, }])
    .finish()
    .table(),
    t,
  )
  let dropped = @mntablemerge.resolve(plan, [
    { target, choice: @mntablemerge.Drop, },
  ]).finish()
  assert_eq(dropped.table().row_count(), 0)
  assert_eq(dropped.resolutions()[0].conflict.theirs.length(), 3)
  assert_eq(
    @mntablemerge.merge(b, t, o, key=["id"]).conflicts()[0].kind,
    @mntablemerge.RowDeleteEdit,
  )
}

///|
test "structure first then cells with cumulative decisions" {
  let b = @mntablemerge.parse_csv("id,v,w\na,base,old\n")
  let o = @mntablemerge.parse_csv("id,w\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\na,edit,theirs\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let cell : @mntablemerge.Decision = {
    target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "w"),
    choice: @mntablemerge.Value("reviewed"),
  }
  try @mntablemerge.resolve(plan, [cell]) catch {
    _ => ()
  } noraise {
    _ => fail("accepted premature cell choice")
  }
  let structural = @mntablemerge.resolve(plan, [
    { target: @mntablemerge.Column("v"), choice: @mntablemerge.Keep, },
  ])
  assert_eq(structural.conflicts()[0].kind, @mntablemerge.CellEdit)
  let complete = @mntablemerge.resolve(structural, [cell])
  assert_eq(complete.finish().table().to_csv(), "id,v,w\na,edit,reviewed\n")
  assert_eq(complete.finish().resolutions().length(), 2)
  assert_eq(plan.conflicts().length(), 1)
}

///|
test "concurrent insertion selects whole row without mixing branch fields" {
  let b = @mntablemerge.parse_csv("id,p,q\n")
  let o = @mntablemerge.parse_csv("id,p,q\nx,1,A\n")
  let t = @mntablemerge.parse_csv("id,p,q\nx,2,B\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  assert_eq(plan.conflicts()[0].kind, @mntablemerge.ConcurrentInsert)
  let target = @mntablemerge.Row(@mntablemerge.RowKey(["x"]))
  assert_eq(
    @mntablemerge.resolve(plan, [{ target, choice: @mntablemerge.Ours, }])
    .finish()
    .table(),
    o,
  )
  assert_eq(
    @mntablemerge.resolve(plan, [{ target, choice: @mntablemerge.Theirs, }])
    .finish()
    .table(),
    t,
  )
  assert_eq(
    @mntablemerge.resolve(plan, [{ target, choice: @mntablemerge.Drop, }])
    .finish()
    .table(),
    b,
  )
}

///|
test "compound key encoding cannot collide on delimiters and ordering is semantic" {
  let b = @mntablemerge.Table::from_rows(["a", "b", "v"], [
    ["a:b", "c", "0"],
    ["a", "b:c", "1"],
  ])
  let merged = @mntablemerge.merge(b, b, b, key=["a", "b"]).finish().table()
  assert_eq(merged.rows(), [["a", "b:c", "1"], ["a:b", "c", "0"]])
  let unequal = @mntablemerge.parse_csv("id,v\n6523,a\n323361,b\n")
  assert_eq(
    @mntablemerge.merge(unequal, unequal, unequal, key=["id"])
    .finish()
    .table()
    .rows(),
    [["323361", "b"], ["6523", "a"]],
  )
}

///|
test "invalid identities and decisions rejected without mutating plans" {
  let good = one("base")
  for source in ["id,v\nx,a\nx,b\n", "id,v\n,a\n", "other,v\nx,a\n"] {
    try
      @mntablemerge.merge(good, @mntablemerge.parse_csv(source), good, key=[
        "id",
      ])
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid key")
    }
  }
  for keys in [[], ["id", "id"], ["missing"]] {
    try @mntablemerge.merge(good, good, good, key=keys) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid key selection")
    }
  }
  let plan = @mntablemerge.merge(good, one("ours"), one("theirs"), key=["id"])
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["x"]), "v")
  let invalid : Array[Array[@mntablemerge.Decision]] = [
    [{ target, choice: @mntablemerge.Drop, }],
    [
      { target, choice: @mntablemerge.Ours, },
      { target, choice: @mntablemerge.Ours, },
    ],
    [{ target: @mntablemerge.Column("unknown"), choice: @mntablemerge.Keep, }],
  ]
  for decisions in invalid {
    try @mntablemerge.resolve(plan, decisions) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid decisions")
    }
    assert_eq(plan.conflicts()[0].base[0].value, "base")
  }
  let conflicts = plan.conflicts()
  conflicts[0].base[0] = {
    key: @mntablemerge.RowKey(["x"]),
    column: "v",
    value: "corrupted",
  }
  assert_eq(plan.conflicts()[0].base[0].value, "base")
}

///|
test "decision JSON exact round trip and duplicate escaped names rejected" {
  let choices = [
    @mntablemerge.Keep,
    @mntablemerge.Drop,
    @mntablemerge.Base,
    @mntablemerge.Ours,
    @mntablemerge.Theirs,
    @mntablemerge.Value("臺北\n\"x\""),
  ]
  for choice in choices {
    let ds : Array[@mntablemerge.Decision] = [
      {
        target: @mntablemerge.Cell(@mntablemerge.RowKey(["a:b", "c"]), "v"),
        choice,
      },
    ]
    assert_eq(
      @mntablemerge.parse_decisions(
        @mntablemerge.decisions_json(ds).stringify(),
      ),
      ds,
    )
  }
  for
    source in [
      "{}", "[{}]", "[{\"target\":{\"column\":\"v\"},\"choice\":\"ours\",\"unknown\":1}]",
      "[{\"target\":{\"column\":\"v\",\"column\":\"w\"},\"choice\":\"ours\"}]", "[{\"target\":{\"column\":\"v\",\"c\\u006flumn\":\"w\"},\"choice\":\"ours\"}]",
      "[{\"target\":{\"row\":[1]},\"choice\":\"ours\"}]", "[{\"target\":{\"column\":\"v\"},\"choice\":{\"value\":null}}]",
    ] {
    try @mntablemerge.parse_decisions(source) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed decisions")
    }
  }
}
