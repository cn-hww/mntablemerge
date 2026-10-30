///|
/// Publishes an already validated complete table. Exclusive sidecar creation
/// and a no-replace rename protect existing files, including input aliases.
async fn write_new_output(path : String, text : String) -> Unit {
  let temp_path = path + ".mntablemerge.tmp"
  let file = @fs.open(temp_path, mode=WriteOnly, create_mode=CreateNew) catch {
    error =>
      fail(
        "Cannot create output sidecar '\{temp_path}': \{error}; use an existing writable directory and a fresh sidecar path",
      )
  }
  errdefer {
    file.close()
    @fs.remove(temp_path) catch {
      _ => ()
    }
  }
  try {
    file.write(text)
    file.sync()
  } catch {
    error =>
      fail(
        "Cannot write/sync output sidecar '\{temp_path}': \{error}; check writable storage and free space, then retry",
      )
  }
  file.close()
  // The destination check belongs to the filesystem operation, not a racy
  // exists() check. A competing exporter cannot replace the winner's file.
  @fs.rename(temp_path, path, replace=false) catch {
    error =>
      fail(
        "Cannot publish output '\{path}': \{error}; destination must not exist; choose a new file (existing files are never replaced)",
      )
  }
}
