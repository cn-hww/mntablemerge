# Adopt the library and check the release archive

Version 0.1.0 is published to Mooncakes. Actual registry consumption and
local-package consumption have separate checks; neither check publishes a module.
Publication/installation evidence is recorded in [validation](validation.md).

## Install from Mooncakes

```text
moon add cn-hww/mntablemerge@0.1.0
```

Import `"cn-hww/mntablemerge" @tablemerge` in `moon.pkg`, or copy the public
[`examples/downstream` template](https://github.com/cn-hww/mntablemerge/tree/main/examples/downstream)
to a new directory. Its module declares version 0.1.0 and has no local path
override. Run `moon update`, `moon test --target wasm` and `moon run cmd/main`
there to exercise the public library. Calls raise `MergeError`.

After the release is available, run the repeatable registry check from a checkout:

```text
moon run scripts/registry-check.mbtx
```

On Windows, optionally pass your C compiler's bin directory as the only script
argument. The check creates a fresh consumer outside the repository, executes
`moon add` against the registry, compares downloaded code/interfaces/fixtures to
the release checkout (normalizing source line endings only), then runs six
external tests and the catalog program on all four targets. No `moon.work` or
local library override is used. Exact CSV/TSV tests do not normalize output.
Run this against the matching release checkout (tag `v0.1.0` for this release); subsequent source changes should
be checked against their corresponding published version. It deliberately fails
on an unavailable version or different published source.

## Run the external consumer

```text
moon run scripts/release-check.mbtx
```

This builds the actual `moon package` ZIP, checks its entries, extracts it into a
fresh system temporary directory and creates an independent consumer module next
to it. The consumer imports only `cn-hww/mntablemerge`; it never imports the CLI
or reaches into the checkout. Tests and a runnable program execute on Wasm,
Wasm-GC, JavaScript and native. Node.js and a C compiler are needed. Extraction
uses Windows' `tar.exe` or Unix `unzip`; no account or private service is needed.
The temporary workspace is removed after the check.

The consumer verifies compound-key catalog merging, exact strings/defensive
copies, TSV round trips, retained-column source compatibility, structural
`MissingCell` review, additive column evolution, JSON bundle serialization and stale-input rejection. A
generated test reads complete pinned OurAirports records **from the extracted
archive**, resolves the simulated structural conflict and verifies the full
expected table. Source and fixture licenses remain in `THIRD_PARTY.md`.

The full CI command includes this gate. On Windows with a compiler outside PATH:

```text
moon run scripts/verify.mbtx C:/path/to/compiler/bin
```

## Develop against a checkout

Copy `examples/downstream` to a sibling directory named `catalog`, then from
the parent directory register the two modules:

```text
moon work init mntablemerge catalog
moon -C catalog test --package example/catalog_merge --target wasm --deny-warn
moon -C catalog run cmd/main
```

`catalog/moon.mod` declares the dependency version and `catalog/moon.pkg` imports
the public package with alias `@tablemerge`. `moon.work` supplies the local
module. This workspace selects checkout source instead of a registry release.
Without it, the same template resolves its declared registry dependency.
The release-check script performs equivalent workspace setup automatically using
packaged sources instead of the checkout; registry-check uses neither override.

For a new application, copy the dependency declaration/import and replace the
catalog fixture strings with your own validated CSV/TSV inputs. Calls raise
`MergeError`; use a raising function or handle diagnostics explicitly. Follow
the [API contract](api-contract.md) for merge, review, ownership and wire rules.

## Release preparation

- `moon package --list` creates the local archive and lists its contents.
  `.moonignore` excludes build/cache/output directories and the separate
  downstream development module. Source, public interface, license, docs,
  CLI, automation and the licensed offline fixtures remain included.
- The archive gate rejects hidden/build/output paths and verifies essential
  source/metadata files before compiling the external consumer. Compilation
  checks source completeness beyond the minimum filename checks.
- Before a registry release, set the intended semantic version, align the
  consumer dependency and changelog, run the complete verification, inspect the
  archive and confirm the release identity. Only then use `moon publish` for an
  explicitly authorized registry publication. Git pushes are a separate action.

Commands and workspace syntax were checked against Moon 0.1.20260920 and the
official [package guide](https://docs.moonbitlang.com/en/stable/toolchain/moon/package-manage-tour.html),
[workspace guide](https://docs.moonbitlang.com/en/stable/toolchain/moon/workspace.html)
and [publishing filters](https://docs.moonbitlang.com/en/stable/toolchain/moon/module.html#publishing-files).
