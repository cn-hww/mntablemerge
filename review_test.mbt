///|
test "offline bundle round trips incomplete structure and cumulative cell review" {
  let b = @mntablemerge.parse_csv("id,v,w\na,base,old\n")
  let o = @mntablemerge.parse_csv("id,w\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v,w\na,edit,theirs\n")
  let original = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  )
  let imported = @mntablemerge.ReviewBundle::from_json(
    original.to_json().stringify(),
  )
  assert_eq(imported.plan().report(), original.plan().report())
  let structure = imported.resolve([
    { target: @mntablemerge.Column("v"), choice: @mntablemerge.Keep, },
  ])
  let roundtrip = @mntablemerge.ReviewBundle::from_json(
    structure.to_json().stringify(),
  )
  assert_eq(roundtrip.plan().conflicts()[0].kind, @mntablemerge.CellEdit)
  let complete = roundtrip.resolve([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "w"),
      choice: @mntablemerge.Value("reviewed\n臺北"),
    },
  ])
  let parsed = @mntablemerge.ReviewBundle::from_json(
    complete.to_json().stringify(),
  )
  assert_eq(parsed.replay(b, o, t, key=["id"]).finish().table().rows(), [
    ["a", "edit", "reviewed\n臺北"],
  ])
  assert_eq(parsed.plan().finish().resolutions().length(), 2)
  assert_eq(original.plan().conflicts()[0].kind, @mntablemerge.ColumnDeleteEdit)
}

///|
test "review rejects stale values identities schema ordering and key selection then recovers" {
  let b = @mntablemerge.parse_csv("id,v\na,old\nb,unchanged\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours\nb,unchanged\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs\nb,unchanged\n")
  let bundle = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, o, t, key=["id"]),
  ).resolve([
    {
      target: @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v"),
      choice: @mntablemerge.Ours,
    },
  ])
  for
    stale in [
      "id,v\na,old\nb,modified\n", "id,v\na,old\nc,unchanged\n", "id,v,new\na,old,x\nb,unchanged,x\n",
      "id,v\nb,unchanged\na,old\n",
    ] {
    try bundle.replay(@mntablemerge.parse_csv(stale), o, t, key=["id"]) catch {
      _ => ()
    } noraise {
      _ => fail("accepted stale review")
    }
    assert_eq(bundle.replay(b, o, t, key=["id"]).finish().table(), o)
  }
  try bundle.replay(b, o, t, key=["v"]) catch {
    _ => ()
  } noraise {
    _ => fail("accepted another key")
  }
  let formatted = @mntablemerge.parse_csv(
    "\uFEFF\"id\",\"v\"\r\n\"a\",\"old\"\r\n\"b\",\"unchanged\"\r\n",
  )
  assert_eq(bundle.replay(formatted, o, t, key=["id"]).finish().table(), o)
}

///|
test "strict review envelope rejects corruption unknown versions and irrelevant choices" {
  let b = @mntablemerge.parse_csv("id,v\na,old\n")
  let bundle = @mntablemerge.ReviewBundle::from_plan(
    @mntablemerge.merge(b, b, b, key=["id"]),
  )
  let json = bundle.to_json().stringify()
  for
    broken in [
      "{}",
      json.replace_all(old="review-1", new="review-2"),
      json.replace_all(old="\"decisions\":[]", new="\"unknown\":[]"),
      json.replace_all(old="\"key\":[\"id\"]", new="\"key\":[1]"),
      json.replace_all(
        old="\"decisions\":[]",
        new="\"decisions\":[{\"target\":{\"column\":\"v\"},\"choice\":\"drop\"}]",
      ),
    ] {
    try @mntablemerge.ReviewBundle::from_json(broken) catch {
      _ => ()
    } noraise {
      _ => fail("accepted corrupt review")
    }
  }
  assert_eq(
    @mntablemerge.ReviewBundle::from_json(json).to_json().stringify(),
    json,
  )
}
