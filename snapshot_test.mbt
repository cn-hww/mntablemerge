///|
test "shared immutable tables retain defensive boundaries through merge and finish" {
  let headers = ["id", "v"]
  let input = [["a", "007"]]
  let table = @mntablemerge.Table::from_rows(headers, input)
  let plan = @mntablemerge.merge(table, table, table, key=["id"])
  let finished = plan.finish()
  let first = finished.table()
  let second = finished.table()
  headers[1] = "changed"
  input[0][1] = "outside"
  input.push(["b", "outside"])
  for exposed in [table, first, second, plan.finish().table()] {
    let names = exposed.headers()
    let rows = exposed.rows()
    names[0] = "broken"
    rows[0][1] = "broken"
    rows.push(["b", "broken"])
  }
  for
    retained in [table, first, second, finished.table(), plan.finish().table()] {
    assert_eq(retained.to_csv(), "id,v\na,007\n")
  }
  assert_eq(
    plan.report().stringify(),
    "{\"format\":\"mntablemerge/report-1\",\"complete\":true,\"conflicts\":[],\"decisions\":[],\"resolutions\":[]}",
  )
}

///|
test "shared review inputs survive exported mutation failed revision and replay" {
  let b = @mntablemerge.parse_csv("id,v\na,base\n")
  let o = @mntablemerge.parse_csv("id,v\na,ours\n")
  let t = @mntablemerge.parse_csv("id,v\na,theirs\n")
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let baseline = @mntablemerge.ReviewBundle::from_plan(plan)
  let original_wire = baseline.to_json().stringify()
  let target = @mntablemerge.Cell(@mntablemerge.RowKey(["a"]), "v")
  let reviewed = baseline.resolve([
    { target, choice: @mntablemerge.Value("\"😀\n\t"), },
  ])
  let wire = reviewed.to_json().stringify()
  let result = reviewed.plan().finish().table()
  let csv = result.to_csv()
  let rows = result.rows()
  rows[0][1] = "mutated output"
  let pending = plan.conflicts()
  pending[0].base.clear()
  let json = reviewed.to_json()
  guard json is Object(fields) else { fail("expected object") }
  fields["base"] = "invalid source"
  try
    reviewed.revise([@mntablemerge.Set({ target, choice: @mntablemerge.Drop, })])
  catch {
    _ => ()
  } noraise {
    _ => fail("accepted dropped cell")
  }
  assert_eq(baseline.to_json().stringify(), original_wire)
  assert_eq(reviewed.to_json().stringify(), wire)
  assert_eq(plan.conflicts()[0].base[0].value, "base")
  assert_eq(reviewed.replay(b, o, t, key=["id"]).finish().table().to_csv(), csv)
  assert_eq(
    @mntablemerge.ReviewBundle::from_json(wire).plan().finish().table().to_csv(),
    csv,
  )
  assert_eq(@mntablemerge.parse_csv(csv), result)
  assert_eq(b.to_csv(), "id,v\na,base\n")
}
