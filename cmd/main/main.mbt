///|
async fn read_text(path : String) -> String {
  let file = @fs.open(path, mode=ReadOnly)
  defer file.close()
  let buffer = @buffer.Buffer()
  while file.read_some(max_len=65536) is Some(chunk) {
    if buffer.length() + chunk.length() > 64000000 {
      fail("Input exceeds 64000000 bytes: \{path}")
    }
    buffer.write_bytes(chunk)
  }
  @utf8.decode(buffer.to_bytes())
}

///|
async fn run(args : Array[String]) -> Int {
  if args == ["--help"] {
    @stdio.stdout.write(
      "Usage: mntablemerge merge BASE OURS THEIRS --key NAME[,NAME] [--decisions FILE] [--report]\nExit: 0 complete, 1 unresolved, 2 invalid input. Complete CSV goes to stdout; conflicts go to stderr. --report emits JSON only.\n",
    )
    return 0
  }
  guard args.length() >= 6 && args[0] == "merge" && args[4] == "--key" else {
    fail("Expected: merge BASE OURS THEIRS --key NAME[,NAME]; use --help")
  }
  let keys = args[5].split(",").map(s => s.to_owned()).to_array()
  let mut decisions : String? = None
  let mut report = false
  let mut i = 6
  while i < args.length() {
    match args[i] {
      "--decisions" => {
        if decisions != None || i + 1 >= args.length() {
          fail("--decisions requires exactly one file")
        }
        decisions = Some(args[i + 1])
        i += 2
      }
      "--report" => {
        if report {
          fail("Duplicate --report")
        }
        report = true
        i += 1
      }
      _ => fail("Unknown option: \{args[i]}")
    }
  }
  let base = @tablemerge.parse_csv(read_text(args[1]))
  let ours = @tablemerge.parse_csv(read_text(args[2]))
  let theirs = @tablemerge.parse_csv(read_text(args[3]))
  let initial = @tablemerge.merge(base, ours, theirs, key=keys)
  let plan = match decisions {
    None => initial
    Some(path) =>
      @tablemerge.resolve(initial, @tablemerge.parse_decisions(read_text(path)))
  }
  if report {
    @stdio.stdout.write(plan.report().stringify() + "\n")
  } else if plan.conflicts().is_empty() {
    @stdio.stdout.write(plan.finish().table().to_csv())
  } else {
    @stdio.stderr.write(plan.report().stringify() + "\n")
  }
  if plan.conflicts().is_empty() {
    0
  } else {
    1
  }
}

///|
async fn main {
  let status = run(@env.args()[1:].to_owned()) catch {
    error => {
      @stdio.stderr.write(
        "Input/IO error: \{error}; check the arguments, UTF-8 encoding and readable file paths\n",
      )
      2
    }
  }
  @sys.exit(status)
}
