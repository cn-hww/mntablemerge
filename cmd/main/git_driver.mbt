///|
/// Git passes three temporary files. Refuse aliases/symlinks; only replace
/// OURS after a complete validated merge and successful temporary-file write.
async fn git_driver(args : Array[String]) -> Int {
  guard args.length() >= 6 && args[4] == "--key" else {
    fail(
      "Expected: git-driver BASE OURS THEIRS --key NAME[,NAME] [--row-order ORDER] [--columns FILE]",
    )
  }
  let mut order : @tablemerge.RowOrder? = None
  let mut columns : String? = None
  let mut rows_path : String? = None
  let mut i = 6
  while i < args.length() {
    if i + 1 >= args.length() {
      fail("Git driver options require a value")
    }
    match args[i] {
      "--row-order" if order == None =>
        order = Some(@tablemerge.RowOrder::parse(args[i + 1]))
      "--columns" if columns == None => columns = Some(args[i + 1])
      "--rows" if rows_path == None => rows_path = Some(args[i + 1])
      _ => fail("Unknown or duplicate Git driver option: \{args[i]}")
    }
    i += 2
  }
  let lineage = match columns {
    None => []
    Some(path) => @tablemerge.parse_column_lineage(read_text(path))
  }
  let rows = match rows_path {
    None => []
    Some(path) => @tablemerge.parse_row_lineage(read_text(path))
  }
  let paths = args[1:4].to_owned()
  let real = []
  for path in paths {
    if @fs.kind(path, follow_symlink=false) != Regular {
      fail("Git driver inputs must be regular files, not symlinks: \{path}")
    }
    real.push(@fs.realpath(path))
  }
  if real[0] == real[1] || real[0] == real[2] || real[1] == real[2] {
    fail("Git driver requires three distinct input files")
  }
  let base = @tablemerge.parse_csv(read_text(paths[0]))
  let ours = @tablemerge.parse_csv(read_text(paths[1]))
  let theirs = @tablemerge.parse_csv(read_text(paths[2]))
  let keys = args[5].split(",").map(s => s.to_owned()).to_array()
  let plan = @tablemerge.merge(
    base,
    ours,
    theirs,
    key=keys,
    row_order=order.unwrap_or(@tablemerge.Lexical),
    column_lineage=lineage,
    row_lineage=rows,
  )
  if !plan.conflicts().is_empty() {
    @stdio.stderr.write(plan.report().stringify() + "\n")
    @stdio.stderr.write(
      "Table merge requires review. OURS is unchanged; Git index stages retain all three inputs. See docs/git-driver.md.\n",
    )
    return 1
  }
  let csv = plan.finish().table().to_csv()
  let temp_path = paths[1] + ".mntablemerge.tmp"
  // Exclusive creation never truncates an existing sidecar. It is beside OURS
  // so replacement stays on the same filesystem.
  let file = @fs.open(temp_path, mode=WriteOnly, create_mode=CreateNew)
  errdefer {
    file.close()
    @fs.remove(temp_path) catch {
      _ => ()
    }
  }
  file.write(csv)
  file.sync()
  file.close()
  @fs.rename(temp_path, paths[1], replace=true)
  0
}
