///|
test "invalid Unicode in tables CSV and programmatic decisions never normalizes silently" {
  // Bounds are valid; deliberately split a surrogate pair to model malformed
  // host-provided strings without asking the compiler to accept bad literals.
  let high = "🛫".unsafe_substring(start=0, end=1)
  let low = "🛫".unsafe_substring(start=1, end=2)
  for invalid in [high, low, high + "x"] {
    try @mntablemerge.Table::from_rows(["id", "v"], [["x", invalid]]) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid Unicode table")
    }
    try @mntablemerge.parse_csv("id,v\nx," + invalid) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid Unicode CSV")
    }
    let b = @mntablemerge.parse_csv("id,v\nx,base\n")
    let o = @mntablemerge.parse_csv("id,v\nx,ours\n")
    let t = @mntablemerge.parse_csv("id,v\nx,theirs\n")
    let plan = @mntablemerge.merge(b, o, t, key=["id"])
    let bad : Array[@mntablemerge.Decision] = [
      {
        target: @mntablemerge.Cell(@mntablemerge.RowKey(["x"]), "v"),
        choice: @mntablemerge.Value(invalid),
      },
    ]
    try @mntablemerge.resolve(plan, bad) catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid Unicode choice")
    }
    assert_eq(
      @mntablemerge.resolve(plan, [
        {
          target: @mntablemerge.Cell(@mntablemerge.RowKey(["x"]), "v"),
          choice: @mntablemerge.Ours,
        },
      ])
      .finish()
      .table(),
      o,
    )
  }
}

///|
test "deep JSON and invalid programmatic target dimensions reject then recover" {
  let nested = String::make(65, '[') + "0" + String::make(65, ']')
  try @mntablemerge.parse_decisions(nested) catch {
    _ => ()
  } noraise {
    _ => fail("accepted deep JSON")
  }
  for
    source in [
      "[{\"target\":{\"column\":\"v\"},\"choice\":{\"value\":\"\\ud800\"}}]", "[null]",
      "[", "[{\"target\":{\"row\":[]},\"choice\":\"drop\"}]",
    ] {
    try @mntablemerge.parse_decisions(source) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed decision JSON")
    }
  }
  let b = @mntablemerge.parse_csv("id,v\nx,base\n")
  let plan = @mntablemerge.merge(b, b, b, key=["id"])
  for
    key in [
      @mntablemerge.RowKey([]),
      @mntablemerge.RowKey([""]),
      @mntablemerge.RowKey(["x", "y"]),
      @mntablemerge.RowKey(["🛫".unsafe_substring(start=0, end=1)]),
    ] {
    try
      @mntablemerge.resolve(plan, [
        { target: @mntablemerge.Row(key), choice: @mntablemerge.Drop, },
      ])
    catch {
      _ => ()
    } noraise {
      _ => fail("accepted invalid target")
    }
  }
  assert_eq(plan.finish().table(), b)
}
