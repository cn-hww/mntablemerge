# Sources and licenses

- Project implementation and synthetic unit test inputs were authored for this repository. No competing implementation was copied or ported. Three-way merge itself is established practice; this statement does not claim algorithm originality.
- `moonbitlang/core`: [MoonBit core](https://github.com/moonbitlang/core), Apache-2.0, distributed with the toolchain. Used for collections, Unicode/UTF-8 and JSON syntax validation/serialization.
- `moonbitlang/async@0.21.3`: [async](https://github.com/moonbitlang/async), Apache-2.0. Used for CLI/script file and process I/O. Its license stays with the fetched dependency; sources are not vendored.
- `moonbitlang/x@0.5.5`: [x](https://github.com/moonbitlang/x), Apache-2.0, used by the CLI for process exit status.
- OurAirports: public-domain dataset, mirror [Unlicense](https://github.com/davidmegginson/ourairports-data/blob/ecead39624006017b34acf27a4b098c9cc8a4635/LICENSE). Only three complete records retained, with clearly labeled simulated edits. See [fixture provenance](examples/airports/README.md).
- [hustcer/setup-moonbit](https://github.com/hustcer/setup-moonbit), MIT; referenced GitHub Action, not vendored. CI also references GitHub's checkout/setup-node actions.
- Research references daff (MIT), csv-diff (Apache-2.0), csvdiff3 (MIT) and adjacent MoonBit projects. Their code/tests/data are not incorporated. The prior Python daff experiment used synthetic catalog CSV outside this repository; daff is not a runtime dependency.

Standard CSV doubled-quote escaping and scalar three-way truth tables are format/behavior contracts. No external benchmark corpus or performance results are included.
