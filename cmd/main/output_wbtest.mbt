///|
async test "output publishes exact UTF-8 bytes and leaves no sidecar" {
  let dir = @fs.tmpdir(prefix="mntablemerge-output-test-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/数据 with spaces.csv"
  let text = "id,value\nx,\"007\t😀\n\"\"quoted\"\"\"\n"
  write_new_output(path, text)
  assert_eq(@fs.read_file(path).binary(), @utf8.encode(text))
  assert_true(!@fs.exists(path + ".mntablemerge.tmp"))
}

///|
async test "output refuses existing files and directories and cleans failed publication" {
  let dir = @fs.tmpdir(prefix="mntablemerge-output-test-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/existing.csv"
  let original = b"\xef\xbb\xbfid,value\r\nx,007\r\n"
  @fs.write_file(path, original)
  for destination in [path, dir] {
    try write_new_output(destination, "replacement") catch {
      _ => ()
    } noraise {
      _ => fail("existing destination must be refused")
    }
    assert_eq(@fs.read_file(path).binary(), original)
    assert_true(!@fs.exists(destination + ".mntablemerge.tmp"))
  }
  // A failed publication does not leave a lock/sidecar that prevents retry.
  @fs.remove(path)
  write_new_output(path, "retry")
  assert_eq(@fs.read_file(path).text(), "retry")
}

///|
async test "output sidecar collision preserves unrelated data and permits retry" {
  let dir = @fs.tmpdir(prefix="mntablemerge-output-test-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/result.csv"
  let temp = path + ".mntablemerge.tmp"
  @fs.write_file(temp, "another export's data")
  try write_new_output(path, "new output") catch {
    _ => ()
  } noraise {
    _ => fail("exclusive sidecar creation must refuse a collision")
  }
  assert_eq(@fs.read_file(temp).text(), "another export's data")
  assert_true(!@fs.exists(path))
  @fs.remove(temp)
  write_new_output(path, "new output")
  assert_eq(@fs.read_file(path).text(), "new output")
}

///|
async test "competing exporters publish exactly one complete result" {
  let dir = @fs.tmpdir(prefix="mntablemerge-output-test-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/race.csv"
  let first = "id,value\na,first\n"
  let second = "id,value\na,second\n"
  async fn attempt(text : String) -> Bool {
    try write_new_output(path, text) catch {
      _ => false
    } noraise {
      _ => true
    }
  }
  let (a, b) = @async.with_task_group(group => {
    let a = group.spawn(() => attempt(first))
    let b = group.spawn(() => attempt(second))
    (a.wait(), b.wait())
  })
  assert_true(a != b)
  assert_eq(@fs.read_file(path).text(), if a { first } else { second })
  assert_true(!@fs.exists(path + ".mntablemerge.tmp"))
}
