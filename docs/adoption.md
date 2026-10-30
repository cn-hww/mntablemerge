# Adopt the library and check the release archive

Status: source/package consumption is validated; this module has **not** been
published to Mooncakes. A successful package check does not upload anything.

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
`MissingCell` review, JSON bundle serialization and stale-input rejection. A
generated test reads complete pinned OurAirports records **from the extracted
archive**, resolves the simulated structural conflict and verifies the full
expected table. Source and fixture licenses remain in `THIRD_PARTY.md`.

The full CI command includes this gate. On Windows with a compiler outside PATH:

```text
moon run scripts/verify.mbtx C:/path/to/compiler/bin
```

## Use a checkout before registry publication

Copy `examples/downstream` to a sibling directory named `catalog`, then from
the parent directory register the two modules:

```text
moon work init mntablemerge catalog
moon -C catalog test --package example/catalog_merge --target wasm --deny-warn
moon -C catalog run cmd/main
```

`catalog/moon.mod` declares the dependency version and `catalog/moon.pkg` imports
the public package with alias `@tablemerge`. `moon.work` supplies the local
module. Do not run the template alone without this workspace: the unpublished
registry dependency cannot be fetched yet. The release-check script performs
equivalent setup automatically using packaged sources instead of the checkout.

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
