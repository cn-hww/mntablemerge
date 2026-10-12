///|
test "review choices can be replaced revoked and redone without mutating old evidence" {
  let b = @mntablemerge.parse_csv("id,v,w\na,base,base\n")
  let o = @mntablemerge.parse_csv("id,v,w\na,ours,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\na,theirs,theirs\n")
  let v = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let w = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "w")
  let original = @mntablemerge.merge(b, o, t, key=["id"])
  let complete = original.revise([
    @mntablemerge.Set({ target: v, choice: @mntablemerge.Ours, }),
    @mntablemerge.Set({ target: w, choice: @mntablemerge.Theirs, }),
  ])
  let edits = [
    @mntablemerge.Set({
      target: v,
      choice: @mntablemerge.Value("reviewed\n東京"),
    }),
  ]
  assert_eq(
    @mntablemerge.parse_review_edits(
      @mntablemerge.review_edits_json(edits).stringify(),
    ),
    edits,
  )
  let changed = complete.revise(edits)
  let wire_edits = [
    @mntablemerge.Revoke(v),
    @mntablemerge.Set({
      target: w,
      choice: @mntablemerge.Value("\"quoted\"\n東京"),
    }),
  ]
  assert_eq(
    @mntablemerge.parse_review_edits(
      @mntablemerge.review_edits_json(wire_edits).stringify(),
    ),
    wire_edits,
  )
  edits.clear()
  assert_eq(changed.decisions()[1], complete.decisions()[1])
  assert_eq(changed.finish().table().rows(), [
    ["a", "reviewed\n東京", "theirs"],
  ])
  assert_eq(complete.finish().table().rows(), [["a", "ours", "theirs"]])
  assert_eq(
    changed.finish().resolutions()[0].choice,
    @mntablemerge.Value("reviewed\n東京"),
  )
  assert_eq(changed.revise([]).report(), changed.report())
  let undone = changed.revise([@mntablemerge.Revoke(v)])
  assert_eq(undone.conflicts()[0].target, v)
  assert_eq(undone.decisions().length(), 1)
  assert_eq(
    undone
    .revise([@mntablemerge.Set({ target: v, choice: @mntablemerge.Ours, })])
    .finish()
    .table(),
    complete.finish().table(),
  )
  let bundle = @mntablemerge.ReviewBundle::from_plan(changed)
  let wire = bundle.to_json().stringify()
  let revised = bundle
    .revise([@mntablemerge.Revoke(v)])
    .revise([@mntablemerge.Set({ target: v, choice: @mntablemerge.Ours, })])
  let imported = @mntablemerge.ReviewBundle::from_json(
    revised.to_json().stringify(),
  )
  assert_eq(
    imported.replay(b, o, t, key=["id"]).finish().table(),
    complete.finish().table(),
  )
  assert_eq(bundle.to_json().stringify(), wire)
  assert_eq(original.conflicts().length(), 2)
}

///|
test "review edit wire limits reject raw and escaped expansion before emitting data" {
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  for value in [String::make(16000000, 'x'), String::make(8000000, '\n')] {
    try
      @mntablemerge.review_edits_json([
        @mntablemerge.Set({ target, choice: @mntablemerge.Value(value), }),
      ])
    catch {
      _ => ()
    } noraise {
      _ => fail("exported oversized document")
    }
  }
  try @mntablemerge.parse_review_edits(String::make(16000001, ' ')) catch {
    _ => ()
  } noraise {
    _ => fail("accepted oversized input")
  }
  let parts = Array::makei(512, i => "k\{i}")
  let boundary = [
    @mntablemerge.Revoke(@mntablemerge.Row(@mntablemerge.RowKey(parts))),
  ]
  assert_eq(
    @mntablemerge.parse_review_edits(
      @mntablemerge.review_edits_json(boundary).stringify(),
    ),
    boundary,
  )
  parts.push("too many")
  try
    @mntablemerge.review_edits_json([
      @mntablemerge.Revoke(@mntablemerge.Row(@mntablemerge.RowKey(parts))),
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 key components")
  }
}

///|
test "structural revision requires explicit dependency revocation and reopens review" {
  let b = @mntablemerge.parse_csv("id,v\na,base\n")
  let o = @mntablemerge.parse_csv("id\na\nb\n")
  let t = @mntablemerge.parse_csv("id,v\na,changed\n")
  let column = @mntablemerge.Column("v")
  let cell = @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "v")
  let draft = @mntablemerge.merge(b, o, t, key=["id"])
  let keep = @mntablemerge.Set({ target: column, choice: @mntablemerge.Keep, })
  let drop = @mntablemerge.Set({ target: column, choice: @mntablemerge.Drop, })
  let fill = @mntablemerge.Set({
    target: cell,
    choice: @mntablemerge.Value("explicit"),
  })
  try draft.revise([keep, fill]) catch {
    _ => ()
  } noraise {
    _ => fail("accepted newly hidden cell in structural batch")
  }
  let complete = draft.revise([keep]).revise([fill])
  for edits in [[drop], [@mntablemerge.Revoke(column)]] {
    try complete.revise(edits) catch {
      @mntablemerge.InvalidDecision(reason) =>
        assert_true(reason.contains("explicitly revoke"))
      error => fail("unexpected \{Repr(error)}")
    } noraise {
      _ => fail("silently discarded dependent choice")
    }
    assert_eq(
      complete.finish().table().to_csv(),
      "id,v\na,changed\nb,explicit\n",
    )
  }
  let edits = [drop, @mntablemerge.Revoke(cell)]
  let dropped = complete.revise(edits)
  assert_eq(dropped.finish().table().to_csv(), "id\na\nb\n")
  assert_eq(complete.revise([edits[1], edits[0]]).report(), dropped.report())
  let reopened = dropped.revise([keep])
  assert_eq(reopened.conflicts()[0].kind, @mntablemerge.MissingCell)
  assert_eq(reopened.revise([fill]).finish().table(), complete.finish().table())
  let revoked = complete.revise([
    @mntablemerge.Revoke(column),
    @mntablemerge.Revoke(cell),
  ])
  assert_eq(revoked.report(), draft.report())
  assert_eq(revoked.decisions(), [])
}

///|
test "row source revision rejects obsolete cell choices rather than discarding them" {
  let b = @mntablemerge.parse_csv("id,old\na,base\n")
  let o = @mntablemerge.parse_csv("id\na\nb\n")
  let t = @mntablemerge.parse_csv("id,old\na,changed\nb,remote\n")
  let col = @mntablemerge.Column("old")
  let row = @mntablemerge.Row(@mntablemerge.RowKey(["b"]))
  let cell = @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "old")
  let complete = @mntablemerge.merge(b, o, t, key=["id"])
    .revise([
      @mntablemerge.Set({ target: col, choice: @mntablemerge.Keep, }),
      @mntablemerge.Set({ target: row, choice: @mntablemerge.Ours, }),
    ])
    .revise([
      @mntablemerge.Set({
        target: cell,
        choice: @mntablemerge.Value("reviewed"),
      }),
    ])
  try
    complete.revise([
      @mntablemerge.Set({ target: row, choice: @mntablemerge.Theirs, }),
    ])
  catch {
    _ => ()
  } noraise {
    _ => fail("ignored obsolete missing-cell decision")
  }
  let switched = complete.revise([
    @mntablemerge.Revoke(cell),
    @mntablemerge.Set({ target: row, choice: @mntablemerge.Theirs, }),
  ])
  assert_eq(switched.finish().table().to_csv(), "id,old\na,changed\nb,remote\n")
  assert_eq(complete.finish().table().rows()[1][1], "reviewed")
}

///|
test "strict revision documents reject malformed targets operations and duplicates then recover" {
  let b = @mntablemerge.parse_csv("id,v\na,base\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs\n")
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let draft = @mntablemerge.merge(b, o, t, key=["id"])
  let choice = @mntablemerge.Set({ target, choice: @mntablemerge.Theirs, })
  let complete = draft.revise([choice])
  for
    edits in [
      [@mntablemerge.Revoke(target)],
      [choice, choice],
      [choice, @mntablemerge.Revoke(target)],
      [
        @mntablemerge.Set({
          target: @mntablemerge.Column("unknown"),
          choice: @mntablemerge.Drop,
        }),
      ],
      [@mntablemerge.Set({ target, choice: @mntablemerge.Keep, })],
      [
        @mntablemerge.Set({
          target,
          choice: @mntablemerge.Value("🛫".unsafe_substring(start=0, end=1)),
        }),
      ],
    ] {
    try draft.revise(edits) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid batch")
    }
    assert_eq(draft.revise([choice]).finish().table(), t)
  }
  for
    edits in [
      [choice, choice],
      [choice, @mntablemerge.Revoke(target)],
      [@mntablemerge.Revoke(@mntablemerge.Column("unknown"))],
    ] {
    try complete.revise(edits) catch {
      _ => ()
    } noraise {
      _ => fail("accepted duplicate/unknown edit")
    }
  }
  for
    broken in [
      "{}", "[{}]", "[{\"op\":\"clear\",\"target\":{\"column\":\"v\"}}]", "[{\"op\":\"revoke\",\"target\":{\"row\":[]}}]",
      "[{\"op\":\"revoke\",\"target\":{\"row\":[\"\"]}}]", "[{\"op\":\"revoke\",\"target\":{\"column\":\"v\"},\"choice\":\"drop\"}]",
      "[{\"op\":\"set\",\"target\":{\"column\":\"v\"}}]", "[{\"op\":\"set\",\"target\":{\"column\":\"v\"},\"choice\":1}]",
      "[{\"op\":\"set\",\"target\":{\"column\":\"v\"},\"choice\":\"drop\",\"extra\":true}]",
      "[{\"op\":\"set\",\"op\":\"revoke\",\"target\":{\"column\":\"v\"},\"choice\":\"drop\"}]",
    ] {
    try @mntablemerge.parse_review_edits(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed edit JSON")
    }
  }
  for
    edits in [
      [
        @mntablemerge.Revoke(
          @mntablemerge.Column("🛫".unsafe_substring(start=0, end=1)),
        ),
      ],
      Array::make(2000001, choice),
    ] {
    try @mntablemerge.review_edits_json(edits) catch {
      _ => ()
    } noraise {
      _ => fail("exported invalid edits")
    }
  }
  try complete.revise(Array::make(2000001, choice)) catch {
    _ => ()
  } noraise {
    _ => fail("accepted excessive edits")
  }
  assert_eq(complete.finish().table(), t)
}

///|
test "revision retains row column and ordering policies and rejects stale original inputs" {
  let b = @mntablemerge.parse_csv("id,v\nz,base\n")
  let o = @mntablemerge.parse_csv("local_id,local\nlocal,ours\n")
  let t = @mntablemerge.parse_csv("id,v\nz,theirs\n")
  let plan = @mntablemerge.merge(
    b,
    o,
    t,
    key=["id"],
    row_order=@mntablemerge.OursOrder,
    column_lineage=[
      { base: "id", ours: "local_id", theirs: "id", output: "id", },
      { base: "v", ours: "local", theirs: "v", output: "value", },
    ],
    row_lineage=[row_link("z", "local", "z", "canonical")],
  )
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["canonical"]), "value")
  let complete = plan.revise([
    @mntablemerge.Set({ target, choice: @mntablemerge.Ours, }),
  ])
  let bundle = @mntablemerge.ReviewBundle::from_plan(complete).revise([
    @mntablemerge.Set({ target, choice: @mntablemerge.Theirs, }),
  ])
  let imported = @mntablemerge.ReviewBundle::from_json(
    bundle.to_json().stringify(),
  )
  assert_eq(imported.plan().row_lineage(), plan.row_lineage())
  assert_eq(imported.plan().column_lineage(), plan.column_lineage())
  assert_eq(imported.plan().row_order(), @mntablemerge.OursOrder)
  assert_eq(
    imported.replay(b, o, t, key=["id"]).finish().table().to_csv(),
    "id,value\ncanonical,theirs\n",
  )
  try
    imported.replay(
      b,
      @mntablemerge.parse_csv("local_id,local\nother,ours\n"),
      t,
      key=["id"],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("revision removed snapshot binding")
  }
  assert_eq(complete.finish().table().rows()[0][1], "ours")
}
