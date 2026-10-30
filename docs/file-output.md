# Complete-table file export

`merge` and `replay` accept `--output FILE` to save a complete, validated CSV or
TSV without shell redirection. The destination must be new. Success returns 0
with empty stdout; the file contains exactly the bytes that the command would
otherwise print. `--format tsv` selects TSV for both input and output; a filename
extension does not select the format.

## Try it with real data

From the repository root, choose a destination that does not exist:

```text
moon run cmd/main -- merge examples/airports/base.csv examples/airports/ours.csv examples/airports/theirs.csv --key id --output merged-airports.csv
```

The result equals `examples/airports/expected.csv`: independent changes on the
two branches are preserved. The inputs are pinned public-domain OurAirports
records with simulated branch edits; [provenance](../examples/airports/README.md)
documents them. Running the command again returns 2 and preserves the existing
result. Choose another filename or move the old result yourself before retrying.

For the structural conflict example, this returns 1, prints `MissingCell` evidence
to stderr, and creates neither the destination nor a temporary file:

```text
moon run cmd/main -- merge examples/airports/base.csv examples/airports/structure-ours.csv examples/airports/structure-theirs.csv --key id --output reviewed-airports.csv
```

Append `--decisions examples/airports/decisions.json` to explicitly fill the
missing value and export `examples/airports/structure-expected.csv`. Offline
review also works: append `--output reviewed-airports.csv` to a `replay` command
from the [review guide](review.md), using a destination that does not exist.
Changed original inputs still fail the review binding before any export.

The automated offline example checks these workflows, CSV/TSV round trips,
existing/input-path preservation, sidecar collisions, competing CLI processes,
malformed/stale inputs, bad options and failure/retry:

```text
moon run scripts/output-demo.mbtx
moon run scripts/output-demo.mbtx native
```

The native command requires a supported Linux/macOS native CLI host and C
compiler. Windows runs the Wasm CLI. The script uses its own temporary directory
and removes it; native Unix runs additionally check regular and dangling symlink
destinations and a symlink sidecar. Windows symlink creation is not required.

## Publication and failures

- Only a complete merge is serialized and published. Unresolved conflicts return
  1 with JSON evidence on stderr. Invalid inputs, stale review, invalid options
  and I/O failures return 2. Both leave stdout empty when `--output` is supplied.
- `--output` cannot be repeated or empty, and is supported only by `merge` and
  `replay`. Combining it with `--report` is rejected before loading inputs.
- The parent directory must already exist. The command exclusively creates
  `FILE.mntablemerge.tmp` beside the destination, writes and syncs all bytes,
  closes it, then renames with replacement disabled. It never falls back to
  truncating a destination. A filesystem without no-replace rename support
  returns an error.
- Existing files, directories, input aliases and dangling symlinks cannot be
  replaced. A competing exporter cannot overwrite an already published result.
  Existing sidecars are preserved; use a different output path or investigate
  the sidecar before removing it. The command removes only the sidecar it
  successfully created, with best-effort cleanup after a handled failure.
- This is complete-file publication, not a power-loss transaction or protection
  against hostile modification of the parent directory. Process termination or
  cleanup failure can leave a sidecar; a subsequent attempt refuses it. Directory
  metadata is not synced. Use an ordinary writable directory under your control.

Without `--output`, stdout, reports and exit statuses retain their existing
behavior. Other artifact commands continue to write stdout. Shell redirection
to an input still truncates it before the CLI starts; use this option when
saving merged tables. Library APIs and the Git driver's deliberate OURS
replacement are unchanged.
