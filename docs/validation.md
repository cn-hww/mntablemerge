# Validation evidence

2026-10-11, MoonBit stable `moonc v0.10.14+7d59c7ec9` / `moon 0.1.20260920`. Initial capability evidence:

- Windows: strict check of all targets; 13 test blocks executed successfully on Wasm, Wasm-GC and JavaScript. Native pure-library tests also executed successfully with LLVM/MinGW (not merely compiled).
- Ubuntu 22.04 under WSL: the same toolchain actually executed all 13 native test blocks and the native CLI on the complete OurAirports merge. The end-to-end helper checks CSV output, conflict/error statuses and resolution. Native async dependency C sources produce compiler warnings on this toolchain; MoonBit project sources pass `--deny-warn`.
- Wasm CLI: offline real-data end-to-end helper passed, including a missing intersection and explicit recovery.
- Windows native CLI: **not supported/validated in this environment**. `moonbitlang/async@0.21.3` native Windows I/O requires MSVC; LLVM/MinGW compilation fails in upstream C sources. CI tests the Windows native pure library only, with Wasm CLI I/O. Linux/macOS jobs exercise native CLI I/O.
- CI targets Linux, Windows and macOS. [Run 38126708323](https://github.com/cn-hww/mntablemerge/actions/runs/38126708323) for the second commit passed all three jobs, including all 16 core tests on all four backends, Wasm CLI workflows on every OS, and actual native CLI workflows on Linux/macOS. Windows native CLI remains explicitly excluded.

Reproduce with `moon run scripts/verify.mbtx`. On Windows, an optional compiler-bin directory is prepended to PATH. Tests use no private infrastructure. See [demo](../examples/airports/README.md). No performance, stress-scale or cryptographic review-authenticity results are claimed.

The second capability adds 3 review test blocks (16 total), checking bundle round trips, cumulative structural/cell decisions, stale input/order/key rejection, malformed envelopes and recovery. The review helper runs export → resolve → guarded replay → stale rejection using actual CLI processes.

Remote run [38126449249](https://github.com/cn-hww/mntablemerge/actions/runs/38126449249) for the first commit failed on all three hosts before compilation: the freshly installed toolchain had no registry index, so the `.mbtx` dependency was unavailable. CI now explicitly runs `moon update` before starting the script. Review tests passed on all four backends locally; the review CLI workflow passed on Windows Wasm and actual Linux native execution.

The third capability adds actual Git branch-merge integration plus malformed-CSV/UTF-8, alias and sidecar-collision checks and recovery, including byte preservation of ancestor/other inputs. Four additional preservation test blocks (20 total) reject lone UTF-16 surrogates in programmatic tables/decisions, malformed key dimensions/deep JSON, and cover a stored header BOM plus CSV quote expansion beyond 16 million syntax units. CSV transport limit is 40 million units, separate from the 16 million semantic table limit, so every valid table can round-trip after escaping. The Git helper exercises Wasm and Linux/macOS native; Windows tests the Wasm driver. Assess its CI results on the third commit's own run; the second run does not prove this new integration.

Before the third commit, all 20 tests executed successfully on Windows Wasm/Wasm-GC/JavaScript/native, and the full Wasm CLI workflows passed. Actual native CLI merge, review and Git-driver workflows also passed under Ubuntu 22.04/WSL. Format checking and regenerated interfaces produced no drift.
