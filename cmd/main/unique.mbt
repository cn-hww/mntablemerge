///|
async fn unique_command(args : Array[String]) -> Int {
  if args.length() == 3 && args[0] == "unique-review" {
    let review = @tablemerge.UniqueReview::new(
      @tablemerge.ReviewBundle::from_json(read_text(args[1])),
      @tablemerge.parse_unique_rules(read_text(args[2])),
    )
    @stdio.stdout.write(review.to_json().stringify() + "\n")
    return 0
  }
  if args.length() == 3 &&
    (args[0] == "unique-repair" || args[0] == "unique-revise") {
    let before = @tablemerge.UniqueReview::from_json(read_text(args[1]))
    let edits = @tablemerge.parse_review_edits(read_text(args[2]))
    let after = if args[0] == "unique-repair" {
      before.revise_repairs(edits)
    } else {
      before.revise(edits)
    }
    @stdio.stdout.write(after.to_json().stringify() + "\n")
    return 0
  }
  if args.length() == 3 && args[0] == "unique-changes" {
    let before = @tablemerge.UniqueReview::from_json(read_text(args[1]))
    let after = @tablemerge.UniqueReview::from_json(read_text(args[2]))
    @stdio.stdout.write(after.changes_report(before).stringify() + "\n")
    return 0
  }
  if args.length() == 2 && args[0] == "unique-report" {
    @stdio.stdout.write(
      @tablemerge.UniqueReview::from_json(read_text(args[1]))
      .report()
      .stringify() +
      "\n",
    )
    return 0
  }
  guard args.length() >= 8 && args[0] == "unique-replay" && args[4] == "--key" else {
    fail(
      "Use unique-review BUNDLE RULES, unique-repair BUNDLE EDITS, unique-revise BUNDLE EDITS, unique-report BUNDLE, unique-changes BEFORE AFTER, or unique-replay BASE OURS THEIRS --key NAME[,NAME] --review BUNDLE [--format csv|tsv] [--report | --output NEWFILE]",
    )
  }
  let mut review_path : String? = None
  let mut output : String? = None
  let mut format : Format? = None
  let mut report = false
  let mut i = 6
  while i < args.length() {
    match args[i] {
      "--review" if review_path == None && i + 1 < args.length() => {
        review_path = Some(args[i + 1])
        i += 2
      }
      "--format" if format == None && i + 1 < args.length() => {
        format = Some(Format::parse(args[i + 1]))
        i += 2
      }
      "--output" if output == None &&
        i + 1 < args.length() &&
        !args[i + 1].is_empty() => {
        output = Some(args[i + 1])
        i += 2
      }
      "--report" if !report => {
        report = true
        i += 1
      }
      _ =>
        fail(
          "Invalid/duplicate unique-replay option; rules and decisions are bound by the bundle",
        )
    }
  }
  guard review_path is Some(path) else {
    fail("unique-replay requires --review BUNDLE")
  }
  if report && output != None {
    fail("--report cannot be combined with --output")
  }
  let transport = format.unwrap_or(Csv)
  let review = @tablemerge.UniqueReview::from_json(read_text(path)).replay(
    transport.read(read_text(args[1])),
    transport.read(read_text(args[2])),
    transport.read(read_text(args[3])),
    key=args[5].split(",").map(s => s.to_owned()).to_array(),
  )
  let complete = try review.finish() catch {
    @tablemerge.Unresolved(_) => None
    error => raise error
  } noraise {
    table => Some(table)
  }
  if report {
    @stdio.stdout.write(review.report().stringify() + "\n")
  } else if complete is Some(table) {
    let text = transport.write(table.table())
    match output {
      Some(path) => write_new_output(path, text)
      None => @stdio.stdout.write(text)
    }
  } else {
    @stdio.stderr.write(review.report().stringify() + "\n")
  }
  if complete is None {
    1
  } else {
    0
  }
}
