///|
test "unique exhaustive exact values preserve legacy merge and deterministic repair round trips" {
  for a in ["", " ", "007", "7", "a:b", "😀", "X", "x"] {
    for b in ["", " ", "007", "7", "a:b", "😀", "X", "x"] {
      let base = @mntablemerge.Table::from_rows(["id", "email"], [])
      let ours = @mntablemerge.Table::from_rows(["id", "email"], [["a", a]])
      let theirs = @mntablemerge.Table::from_rows(["id", "email"], [["b", b]])
      let ordinary = @mntablemerge.merge(base, ours, theirs, key=["id"])
      assert_eq(ordinary.finish().table().row_count(), 2)
      let review = @mntablemerge.UniqueReview::new(
        @mntablemerge.ReviewBundle::from_plan(ordinary),
        [@mntablemerge.UniqueRule("email", ["email"])],
      )
      let fixed = if a == b {
        assert_eq(review.conflicts().length(), 1)
        review.repair([
          {
            target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "email"),
            choice: @mntablemerge.Value(a + "!"),
          },
        ])
      } else {
        assert_eq(review.conflicts(), [])
        review
      }
      assert_eq(fixed.finish().table().row_count(), 2)
      assert_eq(
        @mntablemerge.UniqueReview::from_json(fixed.to_json().stringify()).report(),
        fixed.report(),
      )
      assert_eq(fixed.finish().table().rows()[1], ["b", b])
    }
  }
}

///|
fn unique_review(
  b : String,
  o : String,
  t : String,
  rules? : Array[@mntablemerge.UniqueRule] = [
    @mntablemerge.UniqueRule("email", ["email"]),
  ],
) -> @mntablemerge.UniqueReview raise @mntablemerge.MergeError {
  @mntablemerge.UniqueReview::new(
    @mntablemerge.ReviewBundle::from_plan(
      @mntablemerge.merge(
        @mntablemerge.parse_csv(b),
        @mntablemerge.parse_csv(o),
        @mntablemerge.parse_csv(t),
        key=["id"],
      ),
    ),
    rules,
  )
}

///|
fn unique_reject(
  action : () -> Unit raise @mntablemerge.MergeError,
) -> String raise {
  try action() catch {
    e => e.diagnostic()
  } noraise {
    _ => fail("expected refusal")
  }
}

///|
test "unique merge adds a distinct phase with full row evidence explicit drop and audit" {
  let base = "id,email,note\n"
  let ours = "id,email,note\na,x,007\n"
  let theirs = "id,email,note\nb,x,保留\n"
  let review = unique_review(base, ours, theirs)
  assert_eq(review.conflicts().length(), 1)
  let conflict = review.conflicts()[0]
  assert_eq(conflict.rows.map(k => k.components()), [["a"], ["b"]])
  assert_eq(conflict.base, [])
  assert_eq(conflict.ours.length(), 3)
  assert_eq(conflict.theirs.length(), 3)
  assert_eq(conflict.merged.length(), 6)
  assert_true(
    unique_reject(() => ignore(review.finish())).contains("Unresolved"),
  )
  let resolved = review.repair([
    {
      target: @mntablemerge.Row(@mntablemerge.RowKey(["b"])),
      choice: @mntablemerge.Drop,
    },
  ])
  assert_eq(resolved.finish().table().to_csv(), ours)
  assert_eq(review.conflicts().length(), 1)
  let audit = resolved.changes_report(review).stringify()
  assert_true(audit.contains("unique-changes-1") && audit.contains("保留"))
  assert_eq(
    @mntablemerge.UniqueReview::from_json(resolved.to_json().stringify())
    .finish()
    .table(),
    resolved.finish().table(),
  )
  assert_eq(
    resolved
    .replay(
      @mntablemerge.parse_csv(base),
      @mntablemerge.parse_csv(ours),
      @mntablemerge.parse_csv(theirs),
      key=["id"],
    )
    .finish()
    .table()
    .to_csv(),
    ours,
  )
}

///|
test "unique input violations are diagnosed before merge-created conflicts" {
  let bad = "id,email\na,x\nb,x\n"
  let good = "id,email\n"
  for side in 0..<3 {
    let inputs = [good, good, good]
    inputs[side] = bad
    let error = unique_reject(() => {
      ignore(unique_review(inputs[0], inputs[1], inputs[2]))
    })
    assert_true(
      error.contains(["base", "ours", "theirs"][side] + " already violates"),
    )
    assert_true(
      error.contains("email") && error.contains("a") && error.contains("b"),
    )
  }
  assert_true(
    unique_reject(() => {
      ignore(
        unique_review(good, good, good, rules=[
          @mntablemerge.UniqueRule("unknown", ["absent"]),
        ]),
      )
    }).contains("lacks column"),
  )
}

///|
test "unique compound tuples avoid delimiter collisions and preserve exact Unicode and empty values" {
  let rules = [@mntablemerge.UniqueRule("sku", ["country", "sku"])]
  let b = "id,country,sku\n"
  let o = "id,country,sku\na,a:b,c\nb,a,b:c\n"
  let t = "id,country,sku\nc,a:b,c\n"
  let review = unique_review(b, o, t, rules~)
  assert_eq(review.conflicts().length(), 1)
  assert_eq(review.conflicts()[0].rows.map(k => k.components()), [["a"], ["c"]])
  let value = "  😀\t\n\"007\"  "
  let fixed = review.repair([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["c"]), "sku"),
      choice: @mntablemerge.Value(value),
    },
  ])
  assert_eq(
    @mntablemerge.parse_tsv(fixed.finish().table().to_tsv()),
    fixed.finish().table(),
  )
  assert_eq(fixed.finish().table().rows()[2][2], value)
  let empty = unique_review("id,email\n", "id,email\na,\n", "id,email\nb,\n")
  assert_eq(empty.conflicts()[0].values, [""])
  let case_sensitive = unique_review(
    "id,email\n", "id,email\na,X\n", "id,email\nb,x\n",
  )
  assert_eq(case_sensitive.conflicts(), [])
}

///|
test "unique repairs cannot damage other records keys fields or introduce new duplicate pairs" {
  let review = unique_review(
    "id,email,note\nc,z,keep\n", "id,email,note\nc,z,keep\na,x,A\n", "id,email,note\nc,z,keep\nb,x,B\n",
  )
  let invalid : Array[@mntablemerge.Decision] = [
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "email"),
      choice: @mntablemerge.Value("z"),
    },
    {
      target: @mntablemerge.Row(@mntablemerge.RowKey(["c"])),
      choice: @mntablemerge.Drop,
    },
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "id"),
      choice: @mntablemerge.Value("007"),
    },
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "note"),
      choice: @mntablemerge.Value("lost"),
    },
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "email"),
      choice: @mntablemerge.Ours,
    },
  ]
  for decision in invalid {
    ignore(unique_reject(() => ignore(review.repair([decision]))))
  }
  let row = @mntablemerge.RowKey(["a"])
  let edit : @mntablemerge.Decision = {
    target: @mntablemerge.Cell(row, "email"),
    choice: @mntablemerge.Value("new"),
  }
  assert_true(
    unique_reject(() => {
      ignore(
        review.repair([
          edit,
          { target: @mntablemerge.Row(row), choice: @mntablemerge.Drop, },
        ]),
      )
    }).contains("drop and edit"),
  )
  let fixed = review.repair([edit])
  assert_eq(
    fixed.finish().table().to_csv(),
    "id,email,note\na,new,A\nb,x,B\nc,z,keep\n",
  )
  let reopened = fixed.revise_repairs([@mntablemerge.Revoke(edit.target)])
  assert_eq(reopened.to_json(), review.to_json())
  assert_true(
    unique_reject(() => {
      ignore(reopened.revise_repairs([@mntablemerge.Revoke(edit.target)]))
    }).contains("unrecorded"),
  )
  assert_eq(review.conflicts().length(), 1)
}

///|
test "unique partial repair multiple rules ordering replacement and revocation are deterministic" {
  let b = "id,email\n"
  let o = "id,email\na,x\nc,z\n"
  let t = "id,email\nb,x\nd,z\n"
  let review = unique_review(b, o, t)
  let first : @mntablemerge.Decision = {
    target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "email"),
    choice: @mntablemerge.Value("a"),
  }
  let second : @mntablemerge.Decision = {
    target: @mntablemerge.Row(@mntablemerge.RowKey(["d"])),
    choice: @mntablemerge.Drop,
  }
  let partial = review.repair([first])
  assert_eq(partial.conflicts().length(), 1)
  assert_true(
    unique_reject(() => ignore(partial.finish())).contains("Unresolved"),
  )
  let a = review.repair([first, second])
  let other = review.repair([second, first])
  assert_eq(a.to_json(), other.to_json())
  assert_eq(a.report(), other.report())
  let swapped = unique_review(b, t, o).repair([second, first])
  assert_eq(swapped.finish().table(), a.finish().table())
  let replaced = a.revise_repairs([
    @mntablemerge.Set({
      target: first.target,
      choice: @mntablemerge.Value("  "),
    }),
  ])
  assert_eq(replaced.finish().table().rows()[0][1], "  ")
  assert_eq(
    a
    .revise_repairs([
      @mntablemerge.Revoke(first.target),
      @mntablemerge.Revoke(second.target),
    ])
    .to_json(),
    review.to_json(),
  )
}

///|
test "unique follows ordinary conflicts and guards repairs when an ordinary decision changes candidate" {
  let review = unique_review(
    "id,email,v\na,a,old\nb,b,old\n", "id,email,v\na,x,ours\nb,b,old\n", "id,email,v\na,a,theirs\nb,x,old\n",
  )
  assert_eq(review.conflicts(), [])
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let selected = review.revise([
    @mntablemerge.Set({ target, choice: @mntablemerge.Ours, }),
  ])
  assert_eq(selected.conflicts().length(), 1)
  let repair : @mntablemerge.Decision = {
    target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "email"),
    choice: @mntablemerge.Value("a"),
  }
  let fixed = selected.repair([repair])
  assert_true(
    unique_reject(() => {
      ignore(
        fixed.revise([
          @mntablemerge.Set({ target, choice: @mntablemerge.Theirs, }),
        ]),
      )
    }).contains("revoke uniqueness"),
  )
  let cleared = fixed.revise_repairs([@mntablemerge.Revoke(repair.target)])
  let revised = cleared
    .revise([@mntablemerge.Set({ target, choice: @mntablemerge.Theirs, })])
    .repair([repair])
  assert_eq(revised.finish().table().rows()[0], ["a", "a", "theirs"])
}

///|
test "unique declarations and versioned JSON reject malformed unknown duplicate and stale data" {
  let b = "id,email\n"
  let review = unique_review(b, b, b)
  for
    text in [
      "[]", "{}", "[{\"name\":\"\",\"columns\":[\"email\"]}]", "[{\"name\":\"e\",\"columns\":[\"email\",\"email\"]}]",
      "[{\"name\":\"e\",\"columns\":[\"email\"],\"ignore_empty\":true}]", "[{\"name\":\"e\",\"name\":\"f\",\"columns\":[\"email\"]}]",
    ] {
    ignore(unique_reject(() => ignore(@mntablemerge.parse_unique_rules(text))))
  }
  let wire = review.to_json().stringify()
  for
    invalid in [
      wire.replace_all(old="unique-review-1", new="unique-review-9"),
      wire.replace_all(old="\"repairs\":", new="\"repairs\":[],\"repairs\":"),
      wire.replace_all(old="\"key\":", new="\"key\":[\"x\"],\"key\":"),
    ] {
    ignore(
      unique_reject(() => ignore(@mntablemerge.UniqueReview::from_json(invalid))),
    )
  }
  assert_true(
    unique_reject(() => ignore(@mntablemerge.ReviewBundle::from_json(wire))).contains(
      "unsupported",
    ),
  )
  assert_true(
    unique_reject(() => {
      ignore(
        review.replay(
          @mntablemerge.parse_csv("id,email\na,x\n"),
          @mntablemerge.parse_csv(b),
          @mntablemerge.parse_csv(b),
          key=["id"],
        ),
      )
    }).contains("snapshots"),
  )
  assert_eq(
    @mntablemerge.UniqueReview::from_json(wire).to_json(),
    review.to_json(),
  )
}

///|
test "unique snapshots and exposed evidence are defensively owned" {
  let columns = ["email"]
  let rule = @mntablemerge.UniqueRule("email", columns)
  columns[0] = "id"
  let review = unique_review(
    "id,email\n",
    "id,email\na,x\n",
    "id,email\nb,x\n",
    rules=[rule],
  )
  let expected = review.to_json()
  rule.columns()[0] = "changed"
  let conflict = review.conflicts()[0]
  conflict.columns[0] = "changed"
  conflict.values[0] = "changed"
  conflict.rows[0] = @mntablemerge.RowKey(["changed"])
  conflict.merged[0] = {
    key: @mntablemerge.RowKey(["a"]),
    column: "id",
    value: "changed",
  }
  review.rules()[0] = @mntablemerge.UniqueRule("other", ["id"])
  assert_eq(review.to_json(), expected)
  assert_eq(review.conflicts()[0].columns, ["email"])
  assert_eq(review.conflicts()[0].values, ["x"])
  assert_eq(
    @mntablemerge.unique_rules_json([rule]),
    @mntablemerge.unique_rules_json(
      @mntablemerge.parse_unique_rules(
        @mntablemerge.unique_rules_json([rule]).stringify(),
      ),
    ),
  )
}

///|
test "unique rule count column-set and text limits refuse unsupported declarations" {
  let rules = []
  let headers = ["id"]
  for i in 0..<64 {
    let column = "c\{i}"
    headers.push(column)
    rules.push(@mntablemerge.UniqueRule(column, [column]))
  }
  let table = @mntablemerge.Table::from_rows(headers, [])
  let bundle = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(table, table, table, key=["id"]),
  )
  assert_eq(
    @mntablemerge.UniqueReview::new(bundle, rules).finish().table(),
    table,
  )
  rules.push(@mntablemerge.UniqueRule("overflow", ["id"]))
  assert_true(
    unique_reject(() => ignore(@mntablemerge.UniqueReview::new(bundle, rules))).contains(
      "64",
    ),
  )
  ignore(
    unique_reject(() => {
      ignore(
        @mntablemerge.unique_rules_json([
          @mntablemerge.UniqueRule("a", ["x", "y"]),
          @mntablemerge.UniqueRule("b", ["y", "x"]),
        ]),
      )
    }),
  )
  ignore(
    unique_reject(() => {
      ignore(@mntablemerge.parse_unique_rules(String::make(16000001, ' ')))
    }),
  )
}

///|
test "unique declared lineage composes with renamed headers and record identities" {
  let b = @mntablemerge.parse_csv("id,email\na,a\nb,b\n")
  let o = @mntablemerge.parse_csv("id,address\na1,x\nb,b\n")
  let t = @mntablemerge.parse_csv("id,email\na,a\nb,x\n")
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id"],
    column_lineage=[
      { base: "email", ours: "address", theirs: "email", output: "email", },
    ],
    row_lineage=[
      {
        base: @mntablemerge.RowKey(["a"]),
        ours: @mntablemerge.RowKey(["a1"]),
        theirs: @mntablemerge.RowKey(["a"]),
        output: @mntablemerge.RowKey(["A"]),
      },
    ],
  )
  let review = @mntablemerge.UniqueReview::new(
    @mntablemerge.ReviewBundle::from_plan(plan),
    [@mntablemerge.UniqueRule("email", ["email"])],
  )
  assert_eq(review.conflicts()[0].rows.map(k => k.components()), [["A"], ["b"]])
  let fixed = review.repair([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["A"]), "email"),
      choice: @mntablemerge.Value("saved"),
    },
  ])
  assert_eq(
    fixed.replay(b, o, t, key=["id"]).finish().table().to_csv(),
    "id,email\nA,saved\nb,x\n",
  )
  assert_eq(
    @mntablemerge.UniqueReview::from_json(fixed.to_json().stringify()).to_json(),
    fixed.to_json(),
  )
}

///|
test "unique complete-evidence capacity fails before materialization and recovers" {
  let headers = ["id"]
  for i in 1..<128 {
    headers.push("c\{i}")
  }
  let rules = []
  for i in 1..<21 {
    rules.push(@mntablemerge.UniqueRule("u\{i}", ["c\{i}"]))
  }
  let ours = []
  let theirs = []
  for i in 0..<500 {
    let values = headers.map(_ => "v\{i}")
    values[0] = "a\{i}"
    ours.push(values.copy())
    values[0] = "b\{i}"
    theirs.push(values)
  }
  let b = @mntablemerge.Table::from_rows(headers, [])
  let o = @mntablemerge.Table::from_rows(headers, ours)
  let t = @mntablemerge.Table::from_rows(headers, theirs)
  let bundle = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  )
  assert_true(
    unique_reject(() => ignore(@mntablemerge.UniqueReview::new(bundle, rules))).contains(
      "evidence exceeds",
    ),
  )
  assert_eq(
    @mntablemerge.UniqueReview::new(bundle, [rules[0]]).conflicts().length(),
    500,
  )
  assert_eq(bundle.plan().finish().table().row_count(), 1000)
}
