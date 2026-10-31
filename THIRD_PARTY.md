# Sources and licenses

- Project implementation and synthetic unit test inputs were authored for this repository. No competing implementation was copied or ported. Three-way merge itself is established practice; this statement does not claim algorithm originality.
- `moonbitlang/core`: [MoonBit core](https://github.com/moonbitlang/core), Apache-2.0, distributed with the toolchain. Used for collections, Unicode/UTF-8 and JSON syntax validation/serialization.
- `moonbitlang/async@0.21.3`: [async](https://github.com/moonbitlang/async), Apache-2.0. Used for CLI/script file and process I/O. Its license stays with the fetched dependency; sources are not vendored.
- `moonbitlang/x@0.5.5`: [x](https://github.com/moonbitlang/x), Apache-2.0, used by the CLI for process exit status.
- OurAirports: public-domain dataset, mirror [Unlicense](https://github.com/davidmegginson/ourairports-data/blob/ecead39624006017b34acf27a4b098c9cc8a4635/LICENSE). Only three complete records retained, with clearly labeled simulated edits. See [fixture provenance](examples/airports/README.md).
- [hustcer/setup-moonbit](https://github.com/hustcer/setup-moonbit), MIT; referenced GitHub Action, not vendored. CI also references GitHub's checkout/setup-node actions.
- Research references daff (MIT), csv-diff (Apache-2.0), csvdiff3 (MIT) and adjacent MoonBit projects. Their code/tests/data are not incorporated. The prior Python daff experiment used synthetic catalog CSV outside this repository; daff is not a runtime dependency.

Standard CSV doubled-quote escaping and scalar three-way truth tables are format/behavior contracts. No external benchmark corpus or third-party performance results are included; the checked-in reference measurements are generated from this repository's workloads.

Quoted TSV and editable-sheet implementation, synthetic tests and automation were authored in this repository under its MIT license. The TSV/sheet demonstrations reuse only the existing licensed OurAirports fixtures; no third-party parser, review code or test corpus was incorporated.

Review assignments use repository-authored code/tests under MIT and the same licensed source records. No external assignment engine or additional data corpus is incorporated.

Independent-review combination likewise uses repository-authored code/tests under MIT and simulated edits of the existing source records. No third-party collaboration implementation or test corpus is reused.

Review version comparison and tests are repository-authored under MIT. Its real-data helper reuses this repository's revision-demo fixture transformation and the same licensed OurAirports records; no external diff code or tests are incorporated.

Complete-table file export, its tests and automation are repository-authored under MIT. File creation/sync/no-replace rename use the existing Apache-2.0 async dependency; no upstream source was copied. The end-to-end helper reuses the same licensed OurAirports fixtures with no additional external data.

The independent downstream module and package-check automation are repository-authored under MIT. Synthetic catalog records are not copied from another project. The generated external real-data test uses the same public-domain OurAirports archive fixtures and existing expected output. Extraction delegates to host tar/unzip tools; their implementations are not vendored.

Column evolution, tests and automation are independently repository-authored under MIT. The demonstration's renamed/deleted keywords and added audit tags are simulations on the same licensed OurAirports records. No competitor rename/delete implementation or test cases were copied.

Scale workloads, snapshot-sharing tests and measurement scripts are repository-authored under MIT. Synthetic catalog-like strings and reference measurements are generated from this code, not an external benchmark corpus. Timing uses the existing Apache-2.0 core bench clock. GNU time (GPL-3.0-or-later), Git/unzip and the host compiler are invoked as external tools; no tool implementation is incorporated. This is not an upstream benchmark comparison.

Browser bridge, UI, styles, build helper and regression scenarios are
repository-authored under MIT. Both built-in demonstrations reuse the same
public-domain OurAirports records and simulated transformations as the CLI
helpers. No third-party frontend framework, images, fonts or merge implementation
is incorporated. The generated HTML embeds compiled MoonBit core: the complete
[LICENSE](browser/licenses/moonbit-core-LICENSE.txt) and
[NOTICE](browser/licenses/moonbit-core-NOTICE.txt) copied verbatim from the bundled
core distribution are preserved in the HTML's expandable license section. They
include upstream attribution and transitive notices; these license texts are
the only vendored core files. The module sources remain external dependencies.

[Playwright CLI](https://github.com/microsoft/playwright-cli), version 0.1.22,
Apache-2.0, is invoked externally for actual browser QA; no upstream tests are
copied and no Playwright runtime is embedded. Product sources were formatted
using external [Prettier](https://github.com/prettier/prettier) 3.6.2, MIT.
GitHub's upload-artifact action is referenced in CI to expose the generated HTML
and QA screenshots; its implementation is not vendored.
