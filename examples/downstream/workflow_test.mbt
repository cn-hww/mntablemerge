///|
test "external declared uniqueness detects and repairs a merge-created collision" {
  let b = @tablemerge.parse_csv("id,email\n")
  let o = @tablemerge.parse_csv("id,email\na,x\n")
  let t = @tablemerge.parse_csv("id,email\nb,x\n")
  let review = @tablemerge.UniqueReview::new(
    @tablemerge.ReviewBundle::from_plan(@tablemerge.merge(b, o, t, key=["id"])),
    [@tablemerge.UniqueRule("email", ["email"])],
  )
  assert_eq(review.conflicts().length(), 1)
  let fixed = review.repair([
    {
      target: @tablemerge.Cell(@tablemerge.RowKey(["b"]), "email"),
      choice: @tablemerge.Value("007"),
    },
  ])
  let saved = @tablemerge.UniqueReview::from_json(fixed.to_json().stringify())
  assert_eq(
    saved.replay(b, o, t, key=["id"]).finish().table().to_csv(),
    "id,email\na,x\nb,007\n",
  )
}

///|
test "external compound-key merge preserves string data and round trips" {
  let base = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,10,5\n")
  let ours = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,12,5\n")
  let theirs = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,10,8\n")
  let table = @tablemerge.merge(base, ours, theirs, key=["sku", "warehouse"])
    .finish()
    .table()
  assert_eq(table.to_csv(), "sku,warehouse,price,stock\n007,TW,12,8\n")
  assert_eq(@tablemerge.parse_tsv(table.to_tsv()), table)
  let rows = table.rows()
  rows[0][0] = "mutated"
  assert_eq(table.rows()[0][0], "007")
}

///|
test "external structural review sheet and guarded replay" {
  let base = @tablemerge.parse_csv("id,value\na,old\n")
  let ours = @tablemerge.parse_csv("id,value,owner\na,old,A\n")
  let theirs = @tablemerge.parse_csv("id,value\na,old\nb,new\n")
  let plan = @tablemerge.merge(base, ours, theirs, key=["id"])
  assert_eq(plan.conflicts()[0].kind, @tablemerge.MissingCell)
  let reviewed = @tablemerge.resolve(plan, [
    {
      target: @tablemerge.Cell(@tablemerge.RowKey(["b"]), "owner"),
      choice: @tablemerge.Value(""),
    },
  ])
  let bundle = @tablemerge.ReviewBundle::from_json(
    @tablemerge.ReviewBundle::from_plan(reviewed).to_json().stringify(),
  )
  assert_eq(
    bundle.replay(base, ours, theirs, key=["id"]).finish().table().to_csv(),
    "id,value,owner\na,old,A\nb,new,\n",
  )
  assert_eq(plan.conflicts().length(), 1)
  assert_eq(
    @tablemerge.parse_tsv(plan.review_sheet().to_tsv()),
    plan.review_sheet(),
  )
  let stale = @tablemerge.parse_csv("id,value\na,changed\n")
  try bundle.replay(stale, ours, theirs, key=["id"]) catch {
    @tablemerge.InvalidReview(_) => ()
    _ => fail("expected stale-input diagnostic")
  } noraise {
    _ => fail("stale input must not be replayed")
  }
}

///|
test "external retained-column API remains source compatible" {
  let base = @tablemerge.parse_csv("id,name\na,old\n")
  let ours = @tablemerge.parse_csv("id,title\na,old\n")
  let theirs = @tablemerge.parse_csv("id,name\na,updated\n")
  let columns : Array[@tablemerge.ColumnLineage] = [
    { base: "name", ours: "title", theirs: "name", output: "title", },
  ]
  let plan = @tablemerge.merge(
    base,
    ours,
    theirs,
    key=["id"],
    column_lineage=columns,
  )
  assert_eq(plan.finish().table().to_csv(), "id,title\na,updated\n")
  assert_eq(plan.column_lineage(), columns)
}

///|
test "external rename/delete evolution is additive and input-bound" {
  let base = @tablemerge.parse_csv("id,price\na,007\n")
  let ours = @tablemerge.parse_csv("id,cost\na,007\n")
  let theirs = @tablemerge.parse_csv("id\na\n")
  let evolution : Array[@tablemerge.ColumnEvolution] = [
    { base: "price", ours: Some("cost"), theirs: None, output: "cost", },
  ]
  let plan = @tablemerge.merge(
    base,
    ours,
    theirs,
    key=["id"],
    column_evolution=evolution,
  )
  assert_eq(plan.conflicts()[0].target, @tablemerge.Column("cost"))
  let bundle = @tablemerge.ReviewBundle::from_json(
    @tablemerge.ReviewBundle::from_plan(plan).to_json().stringify(),
  ).resolve([{ target: @tablemerge.Column("cost"), choice: @tablemerge.Keep, }])
  assert_eq(
    bundle.replay(base, ours, theirs, key=["id"]).finish().table(),
    ours,
  )
  assert_eq(
    @tablemerge.parse_column_evolution(
      @tablemerge.column_evolution_json(evolution).stringify(),
    ),
    evolution,
  )
}
