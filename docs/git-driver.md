# Git merge driver and review recovery

The driver follows [Git's custom merge-driver contract](https://git-scm.com/docs/gitattributes#_defining_a_custom_merge_driver): `%O` ancestor, `%A` current, `%B` other. Exit 0 means complete; nonzero leaves a conflict. It does not install configuration or modify your repository settings automatically.

Build the portable Wasm executable in this module:

```text
moon build cmd/main --target wasm --release --deny-warn
```

Use the **absolute** generated `_build/wasm/release/build/cmd/main/main.wasm` path. Configure the consuming repository's `.git/config` (replace the example artifact path):

```gitconfig
[merge "mntablemerge"]
    name = keyed structural CSV merge
    driver = moonrun '/absolute/path/main.wasm' -- git-driver "%O" "%A" "%B" --key id
    recursive = binary
```

On Windows use a forward-slash artifact path such as `C:/projects/mntablemerge/_build/wasm/release/build/cmd/main/main.wasm`. Git for Windows uses its shell to evaluate the driver. Keep the path free of single quotes, or apply correct shell quoting yourself. `moonrun` must be on PATH. Choose an appropriate exact/compound key for each dataset; use separate driver names for different key policies. These instructions do not support a comma inside a key header name; the library's array API does.

Add only intended paths to the consuming repository's `.gitattributes`, for example:

```gitattributes
"airport data.csv" text eol=lf merge=mntablemerge
```

`recursive = binary` keeps the table driver from silently choosing virtual ancestors in a criss-cross history. A resulting ambiguous ancestor may contain an unsuitable table and will require manual review. No general Git history/rename resolution is claimed.

Optional `--row-order base|ours|theirs` preserves the chosen source sequence. Optional `--columns FILE` applies [explicit column lineage](lineage.md), and both may be combined. A lineage file describes the three schemas of a particular merge: all declared source headers must exist. Recheck/update it for later ancestors or remove the option once the migration is complete; an outdated mapping fails instead of guessing. For manual conflict recovery, supply the same intended mapping/order to `review`; the resulting bundle carries them through `review-resolve` and `replay`.

## What it writes

`git-driver BASE OURS THEIRS --key id` requires distinct regular input paths and rejects symlinks. On success it constructs a fully validated CSV, exclusively creates `OURS.mntablemerge.tmp` beside OURS, writes/syncs/closes it, and replaces OURS in one same-filesystem rename operation. BASE/THEIRS are never written. An existing temporary sidecar is an error and is preserved. Write/rename failure triggers cleanup of the driver's own sidecar; if cleanup fails, remove that sidecar before retrying.

On unresolved conflict it exits 1, writes a JSON diagnostic to stderr and leaves OURS **byte-for-byte unchanged**. It writes no conflict markers into CSV. Invalid input/I/O exits 2, also without a candidate CSV. Git records nonzero driver results as an unresolved path. The sidecar replacement is not a multi-file transaction or a guarantee against concurrent external file changes/power loss. Git owns its temporary inputs during the invocation; do not share them with concurrent writers. Distinct hard links are not detected.

## Resolve a failed Git merge

Git's index preserves all three stages for the conflicting file. Read them with `git show ":1:airport data.csv"`, `:2:` and `:3:` and save them as **new UTF-8 files**. In programmatic use, pass `:1:airport data.csv` as one literal argument. Do not substitute the current worktree for the reviewed stage accidentally.

1. Run `review BASE OURS THEIRS --key id`, saving the bundle.
2. Inspect the conflicts and source values with `merge ... --report` or `replay ... --review BUNDLE --report`.
3. Use `review-resolve BUNDLE DECISIONS` to accumulate explicit structural/cell decisions.
4. Use `replay BASE OURS THEIRS --key id --review REVIEWED` and save the complete CSV to a new file. Only after exit 0, copy it to the conflicted worktree path, `git add` that exact path and finish the merge.

The [offline-review guide](review.md) describes stale-input rejection. No private infrastructure is required.

## Executable integration proof

`moon run scripts/git-demo.mbtx` creates disposable repositories using your configured Git identity, builds the real Wasm executable and runs actual `git merge` on branches containing the real OurAirports fixture rows. It checks independent edits, structural conflict/unchanged worktree/index stages, explicit offline review and a completed merge. It also checks malformed input, aliased paths, pre-existing sidecar preservation and successful retry. Paths contain spaces. `moon run scripts/git-demo.mbtx native` runs the native executable on Linux/macOS; Windows native CLI remains excluded.

The helper changes configuration only in its newly allocated test repositories. CI configures the known repository owner's identity in its ephemeral checkout so these fixture commits are attributable; no fixture history is pushed. The helper verifies the exact allocated cleanup path. On Windows its final cleanup uses one native `Remove-Item -LiteralPath ... -Recurse -Force` command because Git objects are read-only and async/fs lacks Windows chmod.
