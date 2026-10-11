///|
test "leading BOM stored in header is data and must not become transport metadata" {
  let table = @mntablemerge.Table::from_rows(["\uFEFFid", "v"], [
    ["x", "\uFEFF"],
  ])
  assert_eq(@mntablemerge.parse_csv(table.to_csv()), table)
  assert_eq(table.to_csv(), "\"\uFEFFid\",v\nx,\"\uFEFF\"\n")
  assert_eq(@mntablemerge.parse_csv("\uFEFFid,v\nx,ok\n").headers(), ["id", "v"])
}

///|
test "quote expansion does not make a valid table unreadable on round trip" {
  let value = String::make(8000001, '"')
  let table = @mntablemerge.Table::from_rows(["id", "v"], [["x", value]])
  let csv = table.to_csv()
  assert_true(csv.length() > 16000000)
  assert_eq(@mntablemerge.parse_csv(csv), table)
}
