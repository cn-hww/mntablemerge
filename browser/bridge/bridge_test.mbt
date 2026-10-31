///|
fn value(response : String) -> Json raise {
  guard @json.parse(response) is Object(fields) &&
    fields.get("ok") == Some(Json::boolean(true)) &&
    fields.get("value") is Some(value) else {
    fail("bridge failed: \{response}")
  }
  value
}

///|
fn review(response : String) -> String raise {
  guard value(response) is Object(fields) && fields.get("review") is Some(wire) else {
    fail("missing review")
  }
  wire.stringify()
}

///|
test "browser bridge phases empty value round trip and CLI-equivalent result" {
  let b = "id,v\na,old\n"
  let o = "id,v,owner\na,old,A\n"
  let t = "id,v\na,old\nb,new\n"
  let started = @bridge.mt_begin(
    b, o, t, "csv", "[\"id\"]", "lexical", "[]", "[]", "[]", "",
  )
  let wire = review(started)
  let failure = @bridge.mt_export(wire, "csv")
  assert_true(failure.contains("Unresolved"))
  let updated = review(
    @bridge.mt_update(
      wire, "[{\"op\":\"set\",\"target\":{\"row\":[\"b\"],\"column\":\"owner\"},\"choice\":{\"value\":\"\"}}]",
    ),
  )
  let direct = @merge.ReviewBundle::from_json(updated).plan().finish().table()
  guard value(@bridge.mt_export(updated, "csv")) is Object(fields) else {
    fail("missing output")
  }
  assert_eq(fields.get("text"), Some(Json::string(direct.to_csv())))
  assert_eq(direct.to_csv(), "id,v,owner\na,old,A\nb,new,\n")
  assert_eq(review(@bridge.mt_open(updated)), updated)
  assert_true(
    @bridge.mt_update(
      wire, "[{\"op\":\"set\",\"target\":{\"row\":[\"b\"],\"column\":\"owner\"},\"choice\":\"drop\"}]",
    ).contains("InvalidDecision"),
  )
  assert_eq(review(@bridge.mt_open(wire)), wire)
  let deep = String::make(65, '[') + "0" + String::make(65, ']')
  assert_true(@bridge.mt_open(deep).contains("nesting exceeds 64"))
}

///|
test "browser bridge rename deletion dependency audit and guarded resume" {
  let b = "id,price\na,007\n"
  let o = "id,cost\na,007\n"
  let t = "id\na\nb\n"
  let mapping = "[{\"base\":\"price\",\"ours\":\"cost\",\"theirs\":null,\"output\":\"cost\"}]"
  let initial = review(
    @bridge.mt_begin(
      b, o, t, "csv", "[\"id\"]", "base", "[]", "[]", mapping, "",
    ),
  )
  let kept = review(
    @bridge.mt_update(
      initial, "[{\"op\":\"set\",\"target\":{\"column\":\"cost\"},\"choice\":\"keep\"}]",
    ),
  )
  let filled = review(
    @bridge.mt_update(
      kept, "[{\"op\":\"set\",\"target\":{\"row\":[\"b\"],\"column\":\"cost\"},\"choice\":{\"value\":\"😀\\t\\n\"}}]",
    ),
  )
  assert_true(
    @bridge.mt_update(
      filled, "[{\"op\":\"set\",\"target\":{\"column\":\"cost\"},\"choice\":\"drop\"}]",
    ).contains("revoke"),
  )
  let dropped = value(
    @bridge.mt_update(
      filled, "[{\"op\":\"set\",\"target\":{\"column\":\"cost\"},\"choice\":\"drop\"},{\"op\":\"revoke\",\"target\":{\"row\":[\"b\"],\"column\":\"cost\"}}]",
    ),
  )
  guard dropped is Object(fields) && fields.get("audit") is Some(audit) else {
    fail("missing audit")
  }
  assert_true(audit.stringify().contains("review-changes-2"))
  assert_eq(
    review(
      @bridge.mt_begin(
        b, o, t, "csv", "[\"id\"]", "lexical", "[]", "[]", "[]", filled,
      ),
    ),
    filled,
  )
  assert_true(
    @bridge.mt_begin(
      b.replace_all(old="007", new="008"),
      o,
      t,
      "csv",
      "[\"id\"]",
      "lexical",
      "[]",
      "[]",
      "[]",
      filled,
    ).contains("snapshots"),
  )
}

///|
test "browser bridge refuses unknown malformed duplicate and oversized inputs" {
  let b = "id,v\na,old\n"
  let wire = review(
    @bridge.mt_begin(
      b, b, b, "csv", "[\"id\"]", "lexical", "[]", "[]", "[]", "",
    ),
  )
  for
    invalid in [
      "{}",
      wire.replace_all(old="review-1", new="review-99"),
      wire.replace_all(old="\"format\":", new="\"format\":\"x\",\"format\":"),
    ] {
    assert_true(@bridge.mt_open(invalid).contains("\"ok\":false"))
  }
  assert_true(
    @bridge.mt_begin(
      b, b, b, "json", "[\"id\"]", "lexical", "[]", "[]", "[]", "",
    ).contains("choose csv or tsv"),
  )
  assert_true(
    @bridge.mt_begin(b, b, b, "csv", "{}", "lexical", "[]", "[]", "[]", "").contains(
      "InvalidKey",
    ),
  )
  assert_true(
    @bridge.mt_begin(
      String::make(2000001, 'x'),
      b,
      b,
      "csv",
      "[\"id\"]",
      "lexical",
      "[]",
      "[]",
      "[]",
      "",
    ).contains("2000000"),
  )
  assert_eq(review(@bridge.mt_open(wire)), wire)
}

///|
fn generated_table(rows : Int, columns : Int) -> String {
  let headers = ["id"]
  for i in 1..<columns {
    headers.push("c\{i}")
  }
  let text = StringBuilder()
  text.write_string(headers.join(",") + "\n")
  for row in 0..<rows {
    text.write_string(
      "r\{row}" +
      String::make(columns - 1, ',').replace_all(old=",", new=",x") +
      "\n",
    )
  }
  text.to_string()
}

///|
test "browser exact shape boundary rejects overflow and recovers deterministically" {
  let boundary = generated_table(20000, 10)
  let accepted = @bridge.mt_begin(
    boundary, boundary, boundary, "csv", "[\"id\"]", "lexical", "[]", "[]", "[]",
    "",
  )
  let wire = review(accepted)
  assert_eq(review(@bridge.mt_open(wire)), wire)
  let output = @bridge.mt_export(wire, "csv")
  assert_eq(@bridge.mt_export(wire, "csv"), output)
  assert_true(
    @bridge.mt_begin(
      generated_table(20001, 1),
      "id\n",
      "id\n",
      "csv",
      "[\"id\"]",
      "lexical",
      "[]",
      "[]",
      "[]",
      "",
    ).contains("20000 records"),
  )
  assert_true(
    @bridge.mt_begin(
      generated_table(20000, 11),
      "id\n",
      "id\n",
      "csv",
      "[\"id\"]",
      "lexical",
      "[]",
      "[]",
      "[]",
      "",
    ).contains("200000 cells"),
  )
  assert_eq(@bridge.mt_export(wire, "csv"), output)
  let deep = String::make(65, '[') + "0" + String::make(65, ']')
  assert_true(@bridge.mt_update(wire, deep).contains("nesting exceeds 64"))
  assert_true(
    @bridge.mt_begin(
      "id\na\n", "id\na\n", "id\na\n", "csv", "[\"id\"]", "lexical", deep, "[]",
      "[]", "",
    ).contains("nesting exceeds 64"),
  )
}

///|
test "browser TSV compound keys preserve Unicode and original core API behavior" {
  let b = "id\tlang\tv\n007\t中文\told\n"
  let o = "id\tlang\tv\n007\t中文\tours\n"
  let t = "id\tlang\tv\n007\t中文\ttheirs\n"
  let wire = review(
    @bridge.mt_begin(
      b, o, t, "tsv", "[\"id\",\"lang\"]", "lexical", "[]", "[]", "[]", "",
    ),
  )
  let resolved = review(
    @bridge.mt_update(
      wire, "[{\"op\":\"set\",\"target\":{\"row\":[\"007\",\"中文\"],\"column\":\"v\"},\"choice\":{\"value\":\"  😀\\t\\n\"}}]",
    ),
  )
  guard value(@bridge.mt_export(resolved, "tsv")) is Object(fields) else {
    fail("TSV output")
  }
  assert_eq(
    fields.get("text"),
    Some(Json::string("id\tlang\tv\n007\t中文\t\"  😀\t\n\"\n")),
  )
  assert_eq(
    review(
      @bridge.mt_begin(
        b, o, t, "tsv", "[\"id\",\"lang\"]", "lexical", "[]", "[]", "[]", resolved,
      ),
    ),
    resolved,
  )
}
