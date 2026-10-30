///|
/// Pure library consumption: no CLI, filesystem or internal package imports.
fn main raise {
  let base = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,10,5\n")
  let ours = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,12,5\n")
  let theirs = @tablemerge.parse_csv("sku,warehouse,price,stock\n007,TW,10,8\n")
  let merged = @tablemerge.merge(base, ours, theirs, key=["sku", "warehouse"])
    .finish()
    .table()
  println(merged.to_csv())
}
