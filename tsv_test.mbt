///|
test "quoted TSV round trips and CSV bytes remain unchanged" {
  let values = [
    "", "007", "a,b", "a\tb", "\"quote\"", "line\nnext", "\r\n", "東京🛫", "\uFEFFdata",
    " space ",
  ]
  for i in 0..<100 {
    let table = @mntablemerge.Table::from_rows(
      ["\uFEFFid", "v\ttab", "other"],
      [["k\{i}", values[i % 10], values[i / 10 % 10]]],
    )
    assert_eq(@mntablemerge.parse_tsv(table.to_tsv()), table)
    assert_eq(
      @mntablemerge.parse_csv(@mntablemerge.parse_tsv(table.to_tsv()).to_csv()),
      table,
    )
    assert_eq(table.to_tsv(), table.to_tsv())
  }
  let table = @mntablemerge.Table::from_rows(["id", "v"], [
    ["a", "x\ty"],
    ["b", "comma,value"],
    ["c", "\"quoted\"\nnext"],
  ])
  assert_eq(
    table.to_csv(),
    "id,v\na,x\ty\nb,\"comma,value\"\nc,\"\"\"quoted\"\"\nnext\"\n",
  )
  assert_eq(
    table.to_tsv(),
    "id\tv\na\t\"x\ty\"\nb\tcomma,value\nc\t\"\"\"quoted\"\"\nnext\"\n",
  )
  assert_eq(@mntablemerge.parse_tsv("\uFEFFid\tv\r\na\t\"x\ty\"\r\n").rows(), [
    ["a", "x\ty"],
  ])
}

///|
test "TSV rejects malformed records and column bounds then recovers" {
  for
    bad in [
      "",
      "id\tv\na\n",
      "id\tid\na\tb\n",
      "id\tv\na\t\"unclosed",
      "id\tv\na\t\"x\"tail\n",
      "id\tv\na\tx\"y\n",
      "id\tv\ra\tb",
      "id\t\na\tb\n",
      "id\tv\na\t" + "🛫".unsafe_substring(start=0, end=1),
    ] {
    try @mntablemerge.parse_tsv(bad) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed TSV")
    }
    assert_eq(@mntablemerge.parse_tsv("id\tv\na\t007\n").rows(), [["a", "007"]])
  }
  let headers = Array::makei(512, i => "c\{i}")
  let boundary = headers.join("\t") + "\n"
  assert_eq(@mntablemerge.parse_tsv(boundary).headers(), headers)
  try @mntablemerge.parse_tsv(headers.join("\t") + "\textra\n") catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 columns")
  }
}

///|
test "TSV merge review retains exact keys tabs and structural missing cells" {
  let b = @mntablemerge.parse_tsv("id\tv\told\n007\tbase\toriginal\n")
  let o = @mntablemerge.parse_tsv("id\tv\n007\t\"ours\tedit\"\n")
  let t = @mntablemerge.parse_tsv(
    "id\tv\told\n007\tbase\tchanged\nnew\tremote\tvalue\n",
  )
  let plan = @mntablemerge.merge(b, o, t, key=["id"])
  let bundle = @mntablemerge.ReviewBundle::from_plan(plan).resolve([
    { target: @mntablemerge.Column("old"), choice: @mntablemerge.Keep, },
  ])
  let imported = @mntablemerge.ReviewBundle::from_json(
    bundle.to_json().stringify(),
  )
  let result = imported.replay(b, o, t, key=["id"]).finish().table()
  assert_eq(@mntablemerge.parse_tsv(result.to_tsv()), result)
  assert_eq(result.rows(), [
    ["007", "ours\tedit", "changed"],
    ["new", "remote", "value"],
  ])
  let missing = @mntablemerge.merge(
    @mntablemerge.parse_tsv("id\na\n"),
    @mntablemerge.parse_tsv("id\tnote\na\tvalue\n"),
    @mntablemerge.parse_tsv("id\na\nb\n"),
    key=["id"],
  )
  assert_eq(missing.conflicts()[0].kind, @mntablemerge.MissingCell)
  assert_eq(
    @mntablemerge.resolve(missing, [
      {
        target: @mntablemerge.Cell(@mntablemerge.RowKey(["b"]), "note"),
        choice: @mntablemerge.Value(""),
      },
    ])
    .finish()
    .table()
    .to_tsv(),
    "id\tnote\na\tvalue\nb\t\n",
  )
}
