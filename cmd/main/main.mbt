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
  if args.length() == 6 &&
    args[0] == "convert" &&
    args[2] == "--from" &&
    args[4] == "--to" {
    let source_format = Format::parse(args[3])
    let output_format = Format::parse(args[5])
    @stdio.stdout.write(
      output_format.write(source_format.read(read_text(args[1]))),
    )
    return 0
  }
  if args.get(0) == Some("git-driver") {
    return git_driver(args)
  }
  if args == ["--help"] {
    @stdio.stdout.write(
      "       mntablemerge convert INPUT --from csv|tsv --to csv|tsv\n",
    )
    @stdio.stdout.write(
      "merge/review/replay/git-driver accept --format csv|tsv (default csv), for all three inputs and merged output. Review bundles store canonical CSV snapshots.\n",
    )
    @stdio.stdout.write(
      "Usage: mntablemerge merge|review BASE OURS THEIRS --key NAME[,NAME] [--decisions FILE] [--report]\n       mntablemerge review-resolve BUNDLE DECISIONS\n       mntablemerge replay BASE OURS THEIRS --key NAME[,NAME] --review BUNDLE [--report]\n       mntablemerge git-driver BASE OURS THEIRS --key NAME[,NAME]\nExit: merge/replay/driver 0 complete, 1 unresolved, 2 invalid input. review commands emit a validated bundle and exit 0 even if review is incomplete.\n",
    )
    @stdio.stdout.write(
      "merge/review/git-driver also accept --row-order lexical|base|ours|theirs, --columns LINEAGE.json and --rows ROWS.json. replay uses the bundle's policy.\n",
    )
    @stdio.stdout.write(
      "       mntablemerge review-revise BUNDLE EDITS\nEdits: set a recorded/current conflict choice or revoke a recorded choice; dependent invalidated choices require explicit revocation.\n",
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
  if args.length() == 3 && args[0] == "review-revise" {
    let bundle = @tablemerge.ReviewBundle::from_json(read_text(args[1]))
    let revised = bundle.revise(
      @tablemerge.parse_review_edits(read_text(args[2])),
    )
    @stdio.stdout.write(revised.to_json().stringify() + "\n")
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
  let mut row_order : @tablemerge.RowOrder? = None
  let mut columns_path : String? = None
  let mut rows_path : String? = None
  let mut format : Format? = None
  let mut i = 6
  while i < args.length() {
    match args[i] {
      "--format" => {
        if format != None || i + 1 >= args.length() {
          fail("--format requires exactly one csv/tsv value")
        }
        format = Some(Format::parse(args[i + 1]))
        i += 2
      }
      "--rows" => {
        if rows_path != None || i + 1 >= args.length() {
          fail("--rows requires exactly one row-lineage JSON file")
        }
        rows_path = Some(args[i + 1])
        i += 2
      }
      "--columns" => {
        if columns_path != None || i + 1 >= args.length() {
          fail("--columns requires exactly one column-lineage JSON file")
        }
        columns_path = Some(args[i + 1])
        i += 2
      }
      "--row-order" => {
        if row_order != None || i + 1 >= args.length() {
          fail(
            "--row-order requires exactly one lexical/base/ours/theirs value",
          )
        }
        row_order = Some(@tablemerge.RowOrder::parse(args[i + 1]))
        i += 2
      }
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
    if review_path == None ||
      decisions != None ||
      row_order != None ||
      columns_path != None ||
      rows_path != None {
      fail(
        "replay requires --review; decisions, row/column lineage and row order are bound by the bundle",
      )
    }
  } else if review_path != None {
    fail("--review is only supported by replay")
  }
  if args[0] == "review" && report {
    fail("review emits a bundle; --report is for merge/replay")
  }
  let transport = format.unwrap_or(Csv)
  let base = transport.read(read_text(args[1]))
  let ours = transport.read(read_text(args[2]))
  let theirs = transport.read(read_text(args[3]))
  let lineage = match columns_path {
    None => []
    Some(path) => @tablemerge.parse_column_lineage(read_text(path))
  }
  let rows = match rows_path {
    None => []
    Some(path) => @tablemerge.parse_row_lineage(read_text(path))
  }
  let initial = match review_path {
    Some(path) =>
      @tablemerge.ReviewBundle::from_json(read_text(path)).replay(
        base,
        ours,
        theirs,
        key=keys,
      )
    None =>
      @tablemerge.merge(
        base,
        ours,
        theirs,
        key=keys,
        row_order=row_order.unwrap_or(@tablemerge.Lexical),
        column_lineage=lineage,
        row_lineage=rows,
      )
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
    @stdio.stdout.write(transport.write(plan.finish().table()))
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
    @tablemerge.MergeError::_ as error => {
      @stdio.stderr.write("Input error: " + error.diagnostic() + "\n")
      2
    }
    error => {
      @stdio.stderr.write(
        "Input/IO error: \{error}; check the arguments, UTF-8 encoding and readable file paths\n",
      )
      2
    }
  }
  @sys.exit(status)
}
