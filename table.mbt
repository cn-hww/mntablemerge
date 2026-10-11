///|
let max_rows = 100000

///|
let max_columns = 512

///|
let max_cells = 2000000

///|
let max_chars = 16000000

///|
/// CSV syntax can expand quotes beyond the semantic table size. This bound
/// accommodates every validated table (including doubled quotes/delimiters).
let max_csv_chars = 40000000

///|
/// Creates a defensive snapshot; values are exact strings, not inferred scalars.
pub fn Table::from_rows(
  headers : Array[String],
  rows : Array[Array[String]],
) -> Table raise MergeError {
  if headers.is_empty() {
    raise InvalidTable("a header is required")
  }
  if headers.length() > max_columns ||
    rows.length() > max_rows ||
    rows.length() * headers.length() > max_cells {
    raise LimitExceeded("maximum 100000 rows, 512 columns, 2000000 cells")
  }
  let seen : Map[String, Bool] = Map([])
  let mut total = 0
  for name in headers {
    validate_unicode(name)
    if name.length() > max_chars - total {
      raise LimitExceeded("header data exceeds 16000000 UTF-16 code units")
    }
    if name.is_empty() {
      raise InvalidTable("empty header; name every column")
    }
    if seen.contains(name) {
      raise InvalidTable("duplicate header '\{name}'; use unique column names")
    }
    seen[name] = true
    total += name.length()
  }
  for index, row in rows {
    if row.length() != headers.length() {
      raise InvalidTable(
        "record \{index + 2} has \{row.length()} fields; expected \{headers.length()}",
      )
    }
    for value in row {
      validate_unicode(value)
      if value.length() > max_chars - total {
        raise LimitExceeded("maximum 16000000 UTF-16 code units of table data")
      }
      total += value.length()
    }
  }
  { columns: headers.copy(), records: rows.map(row => row.copy()), }
}

///|
/// Rejects lone UTF-16 surrogates before character iteration could replace them.
fn validate_unicode(value : String) -> Unit raise MergeError {
  let mut i = 0
  while i < value.length() {
    let unit = value[i].to_int()
    if unit >= 0xD800 && unit <= 0xDBFF {
      if i + 1 >= value.length() {
        raise InvalidTable("unpaired UTF-16 high surrogate")
      }
      let next = value[i + 1].to_int()
      if next < 0xDC00 || next > 0xDFFF {
        raise InvalidTable("unpaired UTF-16 high surrogate")
      }
      i += 2
    } else if unit >= 0xDC00 && unit <= 0xDFFF {
      raise InvalidTable("unpaired UTF-16 low surrogate")
    } else {
      i += 1
    }
  }
}

///|
pub fn Table::headers(self : Table) -> Array[String] {
  self.columns.copy()
}

///|
pub fn Table::rows(self : Table) -> Array[Array[String]] {
  self.records.map(row => row.copy())
}

///|
pub fn Table::row_count(self : Table) -> Int {
  self.records.length()
}

///|
fn Table::snapshot(self : Table) -> Table {
  { columns: self.headers(), records: self.rows(), }
}

///|
fn RowKey::token(self : RowKey) -> String {
  self.parts.map(part => "\{part.length()}:\{part}").join("")
}

///|
priv struct Indexed {
  source : Table
  columns : Map[String, Int]
  rows : Map[String, Array[String]]
  identities : Map[String, RowKey]
}

///|
fn index_table(
  table : Table,
  keys : Array[String],
  side : String,
) -> Indexed raise MergeError {
  let columns : Map[String, Int] = Map([])
  for i, name in table.columns {
    columns[name] = i
  }
  let positions = []
  for name in keys {
    match columns.get(name) {
      Some(i) => positions.push(i)
      None =>
        raise InvalidKey(
          "\{side} lacks key column '\{name}'; restore it or choose another key",
        )
    }
  }
  let rows : Map[String, Array[String]] = Map([])
  let identities : Map[String, RowKey] = Map([])
  for n, row in table.records {
    let parts = positions.map(i => row[i])
    if parts.any(part => part.is_empty()) {
      raise InvalidKey(
        "\{side} record \{n + 2} has an empty key component; supply a nonempty identity",
      )
    }
    let identity = RowKey(parts)
    let token = identity.token()
    if rows.contains(token) {
      raise InvalidKey(
        "\{side} record \{n + 2} duplicates a compound key; deduplicate explicitly",
      )
    }
    rows[token] = row
    identities[token] = identity
  }
  { source: table, columns, rows, identities, }
}

///|
fn Indexed::cell(self : Indexed, id : String, column : String) -> String? {
  match (self.rows.get(id), self.columns.get(column)) {
    (Some(row), Some(index)) => Some(row[index])
    _ => None
  }
}
