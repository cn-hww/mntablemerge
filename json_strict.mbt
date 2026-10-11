///|
/// Core JSON syntax validation plus duplicate-key rejection. A duplicate object
/// key must not silently overwrite a review choice, even when escaped differently.
fn checked_json(source : String) -> Json raise MergeError {
  if source.length() > max_chars {
    raise LimitExceeded("JSON exceeds 16000000 UTF-16 code units")
  }
  validate_unicode(source)
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for c in source {
    if quoted {
      if !escaped && c == '"' {
        quoted = false
      }
      if !escaped && c == '\\' {
        escaped = true
      } else {
        escaped = false
      }
    } else if c == '"' {
      quoted = true
    } else if c == '{' || c == '[' {
      depth += 1
      if depth > 64 {
        raise InvalidDecision(
          "JSON nesting exceeds 64; simplify the review file",
        )
      }
    } else if c == '}' || c == ']' {
      depth -= 1
    }
  }
  let value = @json.parse(source) catch {
    _ =>
      raise InvalidDecision(
        "invalid JSON or nesting exceeds 64; correct the review file",
      )
  }
  let scanner : JsonScanner = { chars: source.to_array(), offset: 0, }
  scanner.scan_value()
  value
}

///|
priv struct JsonScanner {
  chars : Array[Char]
  mut offset : Int
}

///|
fn JsonScanner::space(self : JsonScanner) -> Unit {
  while self.offset < self.chars.length() &&
        (
          self.chars[self.offset] == ' ' ||
          self.chars[self.offset] == '\n' ||
          self.chars[self.offset] == '\r' ||
          self.chars[self.offset] == '\t'
        ) {
    self.offset += 1
  }
}

///|
fn JsonScanner::string(self : JsonScanner) -> String raise MergeError {
  let token = StringBuilder()
  token.write_char('"')
  self.offset += 1
  let mut escaped = false
  while self.offset < self.chars.length() {
    let c = self.chars[self.offset]
    token.write_char(c)
    self.offset += 1
    if !escaped && c == '"' {
      break
    }
    if !escaped && c == '\\' {
      escaped = true
    } else {
      escaped = false
    }
  }
  let decoded = @json.parse(token.to_string()) catch {
    _ => raise InvalidDecision("invalid JSON string")
  }
  guard decoded is String(value) else {
    raise InvalidDecision("expected JSON string")
  }
  validate_unicode(value)
  value
}

///|
fn JsonScanner::scan_value(self : JsonScanner) -> Unit raise MergeError {
  self.space()
  match self.chars.get(self.offset) {
    Some('{') => {
      self.offset += 1
      self.space()
      let seen : Map[String, Bool] = Map([])
      while self.chars.get(self.offset) != Some('}') {
        let name = self.string()
        if seen.contains(name) {
          raise InvalidDecision(
            "duplicate JSON object key '\{name}'; keep each field once",
          )
        }
        seen[name] = true
        self.space()
        self.offset += 1 // Colon; syntax was checked before scanning.
        self.scan_value()
        self.space()
        if self.chars.get(self.offset) != Some(',') {
          break
        }
        self.offset += 1
        self.space()
      }
      self.offset += 1
    }
    Some('[') => {
      self.offset += 1
      self.space()
      while self.chars.get(self.offset) != Some(']') {
        self.scan_value()
        self.space()
        if self.chars.get(self.offset) != Some(',') {
          break
        }
        self.offset += 1
      }
      self.offset += 1
    }
    Some('"') => ignore(self.string())
    _ =>
      while self.offset < self.chars.length() &&
            self.chars[self.offset] != ',' &&
            self.chars[self.offset] != '}' &&
            self.chars[self.offset] != ']' &&
            self.chars[self.offset] != ' ' &&
            self.chars[self.offset] != '\n' &&
            self.chars[self.offset] != '\r' &&
            self.chars[self.offset] != '\t' {
        self.offset += 1
      }
  }
}
