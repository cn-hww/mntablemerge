# Validation evidence

2026-10-11, MoonBit stable `moonc v0.10.14+7d59c7ec9` / `moon 0.1.20260920`.

- Windows: strict check of all targets; 13 test blocks executed successfully on Wasm, Wasm-GC and JavaScript. Native pure-library tests also executed successfully with LLVM/MinGW (not merely compiled).
- Ubuntu 22.04 under WSL: the same toolchain actually executed all 13 native test blocks and the native CLI on the complete OurAirports merge. The end-to-end helper checks CSV output, conflict/error statuses and resolution. Native async dependency C sources produce compiler warnings on this toolchain; MoonBit project sources pass `--deny-warn`.
- Wasm CLI: offline real-data end-to-end helper passed, including a missing intersection and explicit recovery.
- Windows native CLI: **not supported/validated in this environment**. `moonbitlang/async@0.21.3` native Windows I/O requires MSVC; LLVM/MinGW compilation fails in upstream C sources. CI tests the Windows native pure library only, with Wasm CLI I/O. Linux/macOS jobs exercise native CLI I/O.
- CI targets Linux, Windows and macOS. The workflow is a validation plan until its actual run is observed; local Windows/WSL results do not establish macOS execution.

Reproduce with `moon run scripts/verify.mbtx`. On Windows, an optional compiler-bin directory is prepended to PATH. Tests use no private infrastructure. See [demo](../examples/airports/README.md). No performance, stress-scale or cryptographic review-authenticity results are claimed.
