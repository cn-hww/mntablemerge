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
      "Usage: mntablemerge merge|review BASE OURS THEIRS --key NAME[,NAME] [--decisions FILE] [--report]\n       mntablemerge review-resolve BUNDLE DECISIONS\n       mntablemerge replay BASE OURS THEIRS --key NAME[,NAME] --review BUNDLE [--report]\nExit: merge/replay 0 complete, 1 unresolved, 2 invalid input. review commands emit a validated bundle and exit 0 even if review is incomplete.\n",
    )
    return 0
  }
  if args.length() == 3 && args[0] == "review-resolve" {
    let bundle = @tablemerge.ReviewBundle::from_json(read_text(args[1]))
    let resolved = bundle.resolve(
      @tablemerge.parse_decisions(read_text(args[2])),
    )
    @stdio.stdout.write(resolved.to_json().stringify() + "\n")
    return 0
  }
  guard args.length() >= 6 &&
    (args[0] == "merge" || args[0] == "review" || args[0] == "replay") &&
    args[4] == "--key" else {
    fail(
      "Expected: merge/review/replay BASE OURS THEIRS --key NAME[,NAME]; use --help",
    )
  }
  let keys = args[5].split(",").map(s => s.to_owned()).to_array()
  let mut decisions : String? = None
  let mut report = false
  let mut review_path : String? = None
  let mut i = 6
  while i < args.length() {
    match args[i] {
      "--review" => {
        if review_path != None || i + 1 >= args.length() {
          fail("--review requires exactly one bundle file")
        }
        review_path = Some(args[i + 1])
        i += 2
      }
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
  if args[0] == "replay" {
    if review_path == None || decisions != None {
      fail("replay requires --review and does not accept unbound --decisions")
    }
  } else if review_path != None {
    fail("--review is only supported by replay")
  }
  if args[0] == "review" && report {
    fail("review emits a bundle; --report is for merge/replay")
  }
  let base = @tablemerge.parse_csv(read_text(args[1]))
  let ours = @tablemerge.parse_csv(read_text(args[2]))
  let theirs = @tablemerge.parse_csv(read_text(args[3]))
  let initial = match review_path {
    Some(path) =>
      @tablemerge.ReviewBundle::from_json(read_text(path)).replay(
        base,
        ours,
        theirs,
        key=keys,
      )
    None => @tablemerge.merge(base, ours, theirs, key=keys)
  }
  let plan = match decisions {
    None => initial
    Some(path) =>
      @tablemerge.resolve(initial, @tablemerge.parse_decisions(read_text(path)))
  }
  if args[0] == "review" {
    @stdio.stdout.write(
      @tablemerge.ReviewBundle::from_plan(plan).to_json().stringify() + "\n",
    )
    return 0
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
