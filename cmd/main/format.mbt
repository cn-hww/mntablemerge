///|
/// Explicit transport format; no delimiter guessing or filename inference.
enum Format {
  Csv
  Tsv
} derive(Eq)

///|
fn Format::parse(name : String) -> Format raise {
  match name {
    "csv" => Csv
    "tsv" => Tsv
    _ => fail("--format requires csv or tsv; delimiter guessing is unsupported")
  }
}

///|
fn Format::read(self : Format, text : String) -> @tablemerge.Table raise {
  match self {
    Csv => @tablemerge.parse_csv(text)
    Tsv => @tablemerge.parse_tsv(text)
  }
}

///|
fn Format::write(self : Format, table : @tablemerge.Table) -> String {
  match self {
    Csv => table.to_csv()
    Tsv => table.to_tsv()
  }
}
