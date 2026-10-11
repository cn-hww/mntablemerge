///|
/// Strict comma-delimited CSV, with LF/CRLF and doubled quotes.
/// A leading BOM is accepted; no spaces, values or unknown columns are discarded.
pub fn parse_csv(source : String) -> Table raise MergeError {
  if source.length() > max_csv_chars {
    raise LimitExceeded("CSV exceeds 40000000 UTF-16 code units")
  }
  validate_unicode(source)
  let chars = source.to_array()
  let rows : Array[Array[String]] = []
  let mut row : Array[String] = []
  let field = StringBuilder()
  // 0: start, 1: unquoted, 2: quoted, 3: closed quote.
  let mut state = 0
  let mut i = if chars.get(0) == Some('\uFEFF') { 1 } else { 0 }
  let mut active = false
  let mut cells = 0
  while i < chars.length() {
    let c = chars[i]
    active = true
    if state == 2 {
      if c == '"' {
        if chars.get(i + 1) == Some('"') {
          field.write_char('"')
          i += 1
        } else {
          state = 3
        }
      } else {
        field.write_char(c)
      }
    } else if c == ',' || c == '\n' || c == '\r' {
      if c == '\r' {
        if chars.get(i + 1) != Some('\n') {
          raise InvalidCsv(
            record=rows.length() + 1,
            column=row.length() + 1,
            reason="bare CR outside quotes; use LF or CRLF",
          )
        }
        i += 1
      }
      row.push(field.to_string())
      cells += 1
      if cells > max_cells + max_columns {
        raise LimitExceeded("too many CSV fields")
      }
      field.reset()
      state = 0
      if row.length() > max_columns {
        raise LimitExceeded("CSV exceeds 512 columns")
      }
      if c != ',' {
        rows.push(row)
        row = []
        active = false
        if rows.length() > max_rows + 1 {
          raise LimitExceeded("CSV exceeds 100000 data rows")
        }
      }
    } else if state == 3 {
      raise InvalidCsv(
        record=rows.length() + 1,
        column=row.length() + 1,
        reason="characters after a closing quote; remove them or quote the entire field",
      )
    } else if c == '"' {
      if state != 0 {
        raise InvalidCsv(
          record=rows.length() + 1,
          column=row.length() + 1,
          reason="quote inside an unquoted field; quote the entire field",
        )
      }
      state = 2
    } else {
      field.write_char(c)
      state = 1
    }
    i += 1
  }
  if state == 2 {
    raise InvalidCsv(
      record=rows.length() + 1,
      column=row.length() + 1,
      reason="unterminated quoted field; add the closing quote",
    )
  }
  if active {
    row.push(field.to_string())
    rows.push(row)
  }
  guard rows.get(0) is Some(header) else {
    raise InvalidTable("empty CSV; a header is required")
  }
  Table::from_rows(header, rows[1:].to_owned())
}

///|
/// Deterministic CSV. Cell strings round-trip; original formatting does not.
pub fn Table::to_csv(self : Table) -> String {
  let out = StringBuilder()
  write_record(out, self.columns)
  for row in self.records {
    write_record(out, row)
  }
  out.to_string()
}

///|
fn write_record(out : StringBuilder, values : Array[String]) -> Unit {
  for i, value in values {
    if i != 0 {
      out.write_char(',')
    }
    if value.has_prefix("\uFEFF") ||
      value.contains(",") ||
      value.contains("\"") ||
      value.contains("\n") ||
      value.contains("\r") {
      out.write_char('"')
      for c in value {
        out.write_char(c)
        if c == '"' {
          out.write_char('"')
        }
      }
      out.write_char('"')
    } else {
      out.write_string(value)
    }
  }
  out.write_char('\n')
}
