///|
test "rename/delete requires whole-column review even for unchanged values and empty tables" {
  for value in ["", "007", " ", "报价😀\t\n\"quote\""] {
    let base = @mntablemerge.Table::from_rows(["id", "price"], [["a", value]])
    let renamed = @mntablemerge.Table::from_rows(["id", "cost"], [["a", value]])
    let deleted = @mntablemerge.parse_csv("id\na\n")
    for
      (ours, theirs, ours_name, theirs_name) in [
        (renamed, deleted, Some("cost"), None),
        (deleted, renamed, None, Some("cost")),
      ] {
      let evolution : Array[@mntablemerge.ColumnEvolution] = [
        { base: "price", ours: ours_name, theirs: theirs_name, output: "cost", },
      ]
      let plan = @mntablemerge.merge(
        base,
        ours,
        theirs,
        key=["id"],
        column_evolution=evolution,
      )
      assert_eq(plan.conflicts().length(), 1)
      assert_eq(plan.conflicts()[0].target, @mntablemerge.Column("cost"))
      assert_eq(plan.conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
      assert_eq(plan.conflicts()[0].base[0].value, value)
      let kept = @mntablemerge.resolve(plan, [
        { target: @mntablemerge.Column("cost"), choice: @mntablemerge.Keep, },
      ])
      assert_eq(kept.finish().table(), renamed)
      let dropped = @mntablemerge.resolve(plan, [
        { target: @mntablemerge.Column("cost"), choice: @mntablemerge.Drop, },
      ])
      assert_eq(dropped.finish().table(), deleted)
      assert_eq(plan.conflicts().length(), 1)
      evolution.clear()
      let returned = plan.column_evolution()
      returned.clear()
      assert_eq(plan.column_evolution().length(), 1)
    }
  }
  let base = @mntablemerge.parse_csv("id,price\n")
  let ours = @mntablemerge.parse_csv("id,cost\n")
  let theirs = @mntablemerge.parse_csv("id\n")
  let plan = @mntablemerge.merge(base, ours, theirs, key=["id"], column_evolution=[
    { base: "price", ours: Some("cost"), theirs: None, output: "cost", },
  ])
  assert_eq(plan.conflicts().length(), 1)
  assert_eq(plan.conflicts()[0].base, [])
  assert_eq(
    @mntablemerge.resolve(plan, [
      { target: @mntablemerge.Column("cost"), choice: @mntablemerge.Keep, },
    ])
    .finish()
    .table(),
    ours,
  )
}

///|
test "evolution sheet phases dependency revocation and audit retain full evidence" {
  let b = @mntablemerge.parse_csv("id,price\na,007\n")
  let o = @mntablemerge.parse_csv("id,cost\na,009\n")
  let t = @mntablemerge.parse_csv("id\na\nb\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"], column_evolution=[
    { base: "price", ours: Some("cost"), theirs: None, output: "cost", },
  ])
  let sheet = plan.review_sheet()
  let rows = sheet.rows()
  rows[1][6] = "keep"
  let kept = plan.apply_review_sheet(
    @mntablemerge.Table::from_rows(sheet.headers(), rows),
  )
  assert_eq(kept.conflicts()[0].kind, @mntablemerge.MissingCell)
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "cost")
  assert_eq(kept.conflicts()[0].target, target)
  let filled = @mntablemerge.resolve(kept, [
    { target, choice: @mntablemerge.Value(""), },
  ])
  assert_eq(filled.finish().table().to_csv(), "id,cost\na,009\nb,\n")
  try
    filled.revise([
      @mntablemerge.Set({
        target: @mntablemerge.Column("cost"),
        choice: @mntablemerge.Drop,
      }),
    ])
  catch {
    @mntablemerge.InvalidDecision(_) => ()
    _ => fail("expected dependency diagnostic")
  } noraise {
    _ => fail("implicit dependent decision removal")
  }
  let dropped = filled.revise([
    @mntablemerge.Set({
      target: @mntablemerge.Column("cost"),
      choice: @mntablemerge.Drop,
    }),
    @mntablemerge.Revoke(target),
  ])
  assert_eq(dropped.finish().table().to_csv(), "id\na\nb\n")
  let before = @mntablemerge.ReviewBundle::from_plan(filled)
  let after = @mntablemerge.ReviewBundle::from_plan(dropped)
  assert_eq(after.changes_since(before).length(), 2)
  let report = after.changes_report(before).stringify()
  assert_true(report.contains("review-changes-2"))
  assert_true(report.contains("column_evolution"))
  assert_true(report.contains("007") && report.contains("009"))
  assert_eq(filled.finish().table().to_csv(), "id,cost\na,009\nb,\n")
  assert_eq(dropped.column_evolution(), plan.column_evolution())
}

///|
test "evolution versioned review replay assignment and combination bind original policy" {
  let b = @mntablemerge.parse_csv("id,price,stock\na,007,1\n")
  let o = @mntablemerge.parse_csv("id,cost,stock\na,007,2\n")
  let t = @mntablemerge.parse_csv("id,stock\na,1\n")
  let evolution : Array[@mntablemerge.ColumnEvolution] = [
    { base: "price", ours: Some("cost"), theirs: None, output: "cost", },
  ]
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id"],
    column_evolution=evolution,
  )
  let baseline = @mntablemerge.ReviewBundle::from_plan(plan)
  let wire = baseline.to_json().stringify()
  assert_true(
    wire.contains("review-5") &&
    wire.contains("id,price,stock") &&
    wire.contains("id,cost,stock"),
  )
  let restored = @mntablemerge.ReviewBundle::from_json(wire)
  let targets = [@mntablemerge.Column("cost")]
  let sheet = restored.plan().review_sheet_for(targets)
  let rows = sheet.rows()
  rows[1][6] = "keep"
  let kept = @mntablemerge.ReviewBundle::from_plan(
    restored
    .plan()
    .apply_review_sheet_for(
      targets,
      @mntablemerge.Table::from_rows(sheet.headers(), rows),
    ),
  )
  let combined = baseline.combine([kept, kept])
  let result = @mntablemerge.ReviewBundle::from_json(
      combined.to_json().stringify(),
    )
    .replay(b, o, t, key=["id"])
    .finish()
    .table()
  assert_eq(result.to_csv(), "id,cost,stock\na,007,2\n")
  assert_eq(@mntablemerge.parse_csv(result.to_csv()), result)
  let drop = baseline.resolve([
    { target: targets[0], choice: @mntablemerge.Drop, },
  ])
  try baseline.combine([kept, drop]) catch {
    _ => ()
  } noraise {
    _ => fail("accepted reviewer disagreement")
  }
  let other = @mntablemerge.merge(b, o, t, key=["id"], column_evolution=[
    { ..evolution[0], output: "different", },
  ])
  try baseline.combine([@mntablemerge.ReviewBundle::from_plan(other)]) catch {
    _ => ()
  } noraise {
    _ => fail("accepted changed policy")
  }
  try
    other.apply_review_sheet_for([@mntablemerge.Column("different")], sheet)
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted changed sheet policy")
  }
  for changed in ["id,stock\na,3\n", "id,stock\na,1\nb,2\n"] {
    try
      combined.replay(b, o, @mntablemerge.parse_csv(changed), key=["id"])
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted stale snapshot")
    }
  }
  for
    broken in [
      wire.replace_all(old="review-5", new="review-4"),
      wire.replace_all(old="\"column_evolution\"", new="\"unknown\""),
      wire.replace_all(old="\"theirs\":null", new="\"theirs\":\"price\""),
    ] {
    try @mntablemerge.ReviewBundle::from_json(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid evolution bundle")
    }
  }
  assert_eq(restored.plan().column_evolution(), evolution)
}

///|
test "evolution composes retained column row identities and source ordering" {
  let b = @mntablemerge.parse_csv("old_id,price,v\na,007,old\n")
  let o = @mntablemerge.parse_csv("local_id,cost,v\nnew-a,007,ours\n")
  let t = @mntablemerge.parse_csv("old_id,v\na,old\n")
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id"],
    row_order=@mntablemerge.OursOrder,
    column_lineage=[
      { base: "old_id", ours: "local_id", theirs: "old_id", output: "id", },
    ],
    row_lineage=[
      {
        base: @mntablemerge.RowKey(["a"]),
        ours: @mntablemerge.RowKey(["new-a"]),
        theirs: @mntablemerge.RowKey(["a"]),
        output: @mntablemerge.RowKey(["canonical-a"]),
      },
    ],
    column_evolution=[
      { base: "price", ours: Some("cost"), theirs: None, output: "cost", },
    ],
  )
  let resolved = @mntablemerge.resolve(plan, [
    { target: @mntablemerge.Column("cost"), choice: @mntablemerge.Keep, },
  ])
  assert_eq(
    resolved.finish().table().to_csv(),
    "id,cost,v\ncanonical-a,007,ours\n",
  )
  let imported = @mntablemerge.ReviewBundle::from_json(
    @mntablemerge.ReviewBundle::from_plan(resolved).to_json().stringify(),
  )
  assert_eq(
    imported.replay(b, o, t, key=["id"]).finish().table(),
    resolved.finish().table(),
  )
  assert_eq(imported.plan().column_lineage(), plan.column_lineage())
  assert_eq(imported.plan().row_lineage(), plan.row_lineage())
  assert_eq(imported.plan().row_order(), @mntablemerge.OursOrder)
  let deleted = @mntablemerge.parse_csv("id\nx\n")
  let original = @mntablemerge.parse_csv("id,a\nx,A\n")
  let both = @mntablemerge.merge(original, deleted, deleted, key=["id"], column_evolution=[
    { base: "a", ours: None, theirs: None, output: "v", },
  ])
  assert_eq(both.finish().table(), deleted)
  // A reused old name is accepted only with explicit ownership by another mapping.
  let base = @mntablemerge.parse_csv("id,a,b\nx,A,B\n")
  let ours = @mntablemerge.parse_csv("id,a\nx,B\n")
  let mapped = @mntablemerge.merge(
    base,
    ours,
    base,
    key=["id"],
    column_lineage=[{ base: "b", ours: "a", theirs: "b", output: "b", }],
    column_evolution=[
      { base: "a", ours: None, theirs: Some("a"), output: "v", },
    ],
  )
  assert_eq(
    @mntablemerge.resolve(mapped, [
      { target: @mntablemerge.Column("v"), choice: @mntablemerge.Keep, },
    ])
    .finish()
    .table()
    .to_csv(),
    "id,v,b\nx,A,B\n",
  )
}

///|
test "evolution invalid mappings fail atomically and legacy declarations remain strict" {
  let b = @mntablemerge.parse_csv("id,price,extra\na,007,E\n")
  let o = @mntablemerge.parse_csv("id,cost,extra\na,007,E\n")
  let t = @mntablemerge.parse_csv("id,extra\na,E\n")
  let good : @mntablemerge.ColumnEvolution = {
    base: "price",
    ours: Some("cost"),
    theirs: None,
    output: "cost",
  }
  for
    items in [
      [{ ..good, base: "missing", }],
      [{ ..good, ours: Some("missing"), }],
      [{ ..good, theirs: Some("price"), }],
      [{ ..good, ours: None, }],
      [{ ..good, output: "extra", }],
      [{ ..good, output: "", }],
      [good, good],
      [{ ..good, output: "😀".unsafe_substring(start=0, end=1), }],
    ] {
    try @mntablemerge.merge(b, o, t, key=["id"], column_evolution=items) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid evolution")
    }
    assert_eq(
      @mntablemerge.merge(b, o, t, key=["id"], column_evolution=[good])
      .conflicts()
      .length(),
      1,
    )
  }
  try
    @mntablemerge.merge(b, o, t, key=["id"], column_lineage=[
      { base: "price", ours: "cost", theirs: "price", output: "cost", },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("changed retained lineage semantics")
  }
  try
    @mntablemerge.merge(
      b,
      o,
      t,
      key=["id"],
      column_lineage=[
        { base: "extra", ours: "extra", theirs: "extra", output: "cost", },
      ],
      column_evolution=[good],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted overlapping policies")
  }
  try
    @mntablemerge.merge(
      b,
      @mntablemerge.parse_csv("price,extra\n007,E\n"),
      t,
      key=["id"],
      column_evolution=[
        { base: "id", ours: None, theirs: Some("id"), output: "id", },
      ],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("invented deleted key")
  }
  assert_eq(b.to_csv(), "id,price,extra\na,007,E\n")
}

///|
test "evolution strict wire round trips and malformed inputs recover" {
  let item : @mntablemerge.ColumnEvolution = {
    base: "值😀",
    ours: Some("new\t\"\n"),
    theirs: None,
    output: "output",
  }
  let wire = @mntablemerge.column_evolution_json([item]).stringify()
  assert_eq(@mntablemerge.parse_column_evolution(wire), [item])
  for
    broken in [
      "{}", "[{}]", "[{\"base\":null,\"ours\":null,\"theirs\":null,\"output\":\"x\"}]",
      "[{\"base\":\"a\",\"ours\":false,\"theirs\":null,\"output\":\"x\"}]", "[{\"base\":\"a\",\"ours\":\"\",\"theirs\":null,\"output\":\"x\"}]",
      "[{\"base\":\"a\",\"ours\":null,\"theirs\":null,\"output\":\"x\",\"extra\":1}]",
      "[{\"base\":\"a\",\"base\":\"b\",\"ours\":null,\"theirs\":null,\"output\":\"x\"}]",
    ] {
    try @mntablemerge.parse_column_evolution(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed evolution")
    }
    assert_eq(@mntablemerge.parse_column_evolution(wire), [item])
  }
  try
    @mntablemerge.column_evolution_json([
      { ..item, output: "😀".unsafe_substring(start=0, end=1), },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("serialized invalid Unicode")
  }
  let b = @mntablemerge.parse_csv("id,v\nx,old\n")
  assert_eq(
    @mntablemerge.merge(b, b, b, key=["id"], column_evolution=[]).report(),
    @mntablemerge.merge(b, b, b, key=["id"]).report(),
  )
}

///|
test "evolution all presence combinations retain ordinary cell semantics" {
  let base = @mntablemerge.parse_csv("id,price\na,base\n")
  for
    (ov, tv, expected) in [
      ("base", "base", Some("base")),
      ("base", "remote", Some("remote")),
      ("local", "base", Some("local")),
      ("same", "same", Some("same")),
      ("local", "remote", None),
    ] {
    for op in [false, true] {
      for tp in [false, true] {
        let ours = if op {
          @mntablemerge.Table::from_rows(["id", "local"], [["a", ov]])
        } else {
          @mntablemerge.parse_csv("id\na\n")
        }
        let theirs = if tp {
          @mntablemerge.Table::from_rows(["id", "remote"], [["a", tv]])
        } else {
          @mntablemerge.parse_csv("id\na\n")
        }
        let plan = @mntablemerge.merge(base, ours, theirs, key=["id"], column_evolution=[
          {
            base: "price",
            ours: if op {
              Some("local")
            } else {
              None
            },
            theirs: if tp {
              Some("remote")
            } else {
              None
            },
            output: "value",
          },
        ])
        if op && tp {
          match expected {
            Some(value) =>
              assert_eq(plan.finish().table().rows(), [["a", value]])
            None => {
              assert_eq(plan.conflicts()[0].kind, @mntablemerge.CellEdit)
              let resolved = @mntablemerge.resolve(plan, [
                {
                  target: @mntablemerge.Cell(
                    @mntablemerge.RowKey(["a"]),
                    "value",
                  ),
                  choice: @mntablemerge.Value("reviewed"),
                },
              ])
              assert_eq(resolved.finish().table().rows(), [["a", "reviewed"]])
            }
          }
        } else if op || tp {
          assert_eq(plan.conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
          let kept = @mntablemerge.resolve(plan, [
            {
              target: @mntablemerge.Column("value"),
              choice: @mntablemerge.Keep,
            },
          ])
          assert_eq(kept.finish().table().rows(), [
            ["a", if op { ov } else { tv }],
          ])
        } else {
          assert_eq(plan.finish().table().to_csv(), "id\na\n")
        }
      }
    }
  }
}

///|
test "evolution 512 declaration boundary and deterministic mapping order" {
  let headers = Array::makei(512, i => "c\{i}")
  let b = @mntablemerge.Table::from_rows(headers, [])
  let deleted = @mntablemerge.parse_csv("c0\n")
  let items : Array[@mntablemerge.ColumnEvolution] = headers[1:]
    .to_owned()
    .map(name => {
      base: name,
      ours: Some(name),
      theirs: None,
      output: "new_" + name,
    })
  let key : @mntablemerge.ColumnLineage = {
    base: "c0",
    ours: "c0",
    theirs: "c0",
    output: "id",
  }
  let plan = @mntablemerge.merge(
    b,
    b,
    deleted,
    key=["id"],
    column_lineage=[key],
    column_evolution=items,
  )
  assert_eq(plan.conflicts().length(), 511)
  let reversed = items.rev()
  let other = @mntablemerge.merge(
    b,
    b,
    deleted,
    key=["id"],
    column_lineage=[key],
    column_evolution=reversed,
  )
  assert_eq(plan.conflicts(), other.conflicts())
  let decisions = plan
    .conflicts()
    .map(c => @mntablemerge.Decision::{
      target: c.target,
      choice: @mntablemerge.Drop,
    })
  assert_eq(
    @mntablemerge.resolve(plan, decisions).finish().table().to_csv(),
    "id\n",
  )
  items.push({ base: "c0", ours: Some("c0"), theirs: Some("c0"), output: "id", })
  assert_eq(
    @mntablemerge.parse_column_evolution(
      @mntablemerge.column_evolution_json(items).stringify(),
    ).length(),
    512,
  )
  try
    @mntablemerge.merge(
      b,
      b,
      deleted,
      key=["id"],
      column_lineage=[key],
      column_evolution=items,
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 combined declarations")
  }
  items.push(items[0])
  try @mntablemerge.column_evolution_json(items) catch {
    _ => ()
  } noraise {
    _ => fail("serialized 513 declarations")
  }
  let oversized = @mntablemerge.column_evolution_json(items[0:512].to_owned()).stringify()
  let extra = @mntablemerge.column_evolution_json([items[0]]).stringify()
  let too_many = oversized.strip_suffix("]").unwrap().to_owned() +
    "," +
    extra.strip_prefix("[").unwrap().to_owned()
  try @mntablemerge.parse_column_evolution(too_many) catch {
    _ => ()
  } noraise {
    _ => fail("parsed 513 declarations")
  }
  let huge = String::make(16000001, 'x')
  try
    @mntablemerge.column_evolution_json([
      { base: "a", ours: Some("a"), theirs: None, output: huge, },
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("serialized oversized text")
  }
  let escaped = String::make(8000000, '"')
  try
    @mntablemerge.column_evolution_json([
      { base: "a", ours: Some("a"), theirs: None, output: escaped, },
    ])
  catch {
    @mntablemerge.LimitExceeded(reason) => assert_true(reason.contains("JSON"))
    _ => fail("expected escaped-wire limit")
  } noraise {
    _ => fail("serialized an unparseable escaped document")
  }
}
