///|
test "CSV semantic round trips across quoting Unicode and empty cells" {
  let values = [
    "", "plain", "007", " a ", "a,b", "a\"b", "a\nb", "a\r\nb", "臺北🛫", "\uFEFF",
  ]
  for a in values {
    for b in values {
      let table = @mntablemerge.Table::from_rows(["id", "value"], [[a, b]])
      assert_eq(@mntablemerge.parse_csv(table.to_csv()), table)
    }
  }
  assert_eq(
    @mntablemerge.parse_csv("\uFEFFid,value\r\nx,\"a\r\nb\"\r\n").rows(),
    [["x", "a\r\nb"]],
  )
  assert_eq(@mntablemerge.parse_csv("id,value\nx,").rows(), [["x", ""]])
  assert_eq(@mntablemerge.parse_csv("id\n").row_count(), 0)
}

///|
test "malformed CSV rejected then parser remains usable" {
  for
    source in [
      "", "id,id\nx,y\n", "id,v\nx\n", "id,v\nx,\"a", "id,v\nx,a\"b\n", "id,v\nx,\"a\"z\n",
      "id,v\rx,y\r", ",v\nx,y\n",
    ] {
    try @mntablemerge.parse_csv(source) catch {
      _ => ()
    } noraise {
      _ => fail("accepted malformed CSV")
    }
    assert_eq(@mntablemerge.parse_csv("id,v\nx,ok\n").rows(), [["x", "ok"]])
  }
}

///|
test "constructor limits and defensive snapshots" {
  let headers = ["id", "v"]
  let rows = [["x", "old"]]
  let table = @mntablemerge.Table::from_rows(headers, rows)
  headers[1] = "changed"
  rows[0][1] = "changed"
  let exposed = table.rows()
  exposed[0][1] = "changed again"
  assert_eq(table.to_csv(), "id,v\nx,old\n")
  let wide = Array::makei(512, i => "c\{i}")
  assert_eq(@mntablemerge.Table::from_rows(wide, []).headers().length(), 512)
  wide.push("overflow")
  try @mntablemerge.Table::from_rows(wide, []) catch {
    _ => ()
  } noraise {
    _ => fail("accepted 513 columns")
  }
  let many = Array::make(100000, ["x"])
  assert_eq(@mntablemerge.Table::from_rows(["id"], many).row_count(), 100000)
  many.push(["x"])
  try @mntablemerge.Table::from_rows(["id"], many) catch {
    _ => ()
  } noraise {
    _ => fail("accepted 100001 rows")
  }
}
