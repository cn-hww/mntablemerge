# Offline browser review

Build with the pinned MoonBit toolchain described in [validation](validation.md):

```text
moon update
moon run scripts/build-browser.mbtx
```

Open `output/browser/index.html` in Chrome. It is one self-contained file: copy
it to another computer, disconnect the network and open it there. No server,
CDN, account, upload endpoint or npm runtime dependency is needed. Successful
Linux CI uploads an `offline-reviewer` artifact with this HTML and QA screenshots;
this is a development artifact, not a versioned release or hosted service.

The Chinese UI uses the existing MoonBit merge/review core compiled to JavaScript
in a Blob Worker. The four string-only bridge functions in `browser/bridge` are
an internal UI transport. The root library API and existing wire versions stay
unchanged. Inputs and confirmed progress stay in memory; **download the review
bundle before closing or refreshing**. It contains the original table snapshots,
rules and recorded decisions, so treat it as a copy of those tables.

## Three complete workflows

1. **Fill an unknown row/column intersection.** Choose “载入缺失值示例” to load
   three full-record, pinned public-domain OurAirports snapshots with simulated
   branch edits. One branch adds `review_owner`; the other adds record `6524`.
   That intersection has no source value. CSV/TSV export stays disabled. Choose
   “填写明确值”, enter the owner, and apply. A deliberately empty textbox is an
   explicit empty string; leaving a conflict undecided is different. Download
   the complete CSV/TSV, review bundle and full evidence.
2. **Review a renamed field deleted on the other branch.** Choose “载入改名与删除示例”.
   An explicit declaration maps `keywords` to `audit_tags`, with `theirs: null`.
   Review the whole-field keep/drop evidence first. Keeping it exposes a missing
   cell for the new airport; resolve that in the next phase. To change the field
   to drop later, open “已记录决策”, choose drop and explicitly revoke the dependent
   cell decision in the same batch. An incomplete revocation is refused, with
   the previous bundle retained. Download the new table and the **last applied
   batch's** complete before/after audit; this is not an accumulated history.
3. **Hand off and resume real files.** Import BASE/OURS/THEIRS UTF-8 CSV or quoted
   TSV files, select the format and key headers as a JSON string array (compound
   keys supported), and start review. Advanced declarations accept the same
   lineage/evolution JSON as the library and CLI; renames are never inferred.
   Save a partial review, close the page, reopen it and use “打开包内快照”. To verify
   against a fresh checkout, choose all three original files and the review,
   then “校验三份文件并续审”. Core replay checks semantic snapshots and keys and uses
   the bundle's policies. Stale inputs fail without changing the confirmed review.
   Completed bundles can also be used with the existing CLI `replay` command.

The current session's actual rules are expandable above the decisions; conflict
coordinates use the output names/keys. Draft selections survive pagination.
Failed operations retain the last confirmed review and existing drafts. Cancel
terminates the worker; subsequent operations start with a fresh worker. Download
the bundle to preserve work across page reloads; there is no localStorage autosave.

## Explicit boundaries

Each table: at most **20,000 data records, 200,000 cells, 2,000,000 UTF-16 units**
of delimited input. Each selected file: at most **8,000,000 bytes**. Review JSON,
policy/edit JSON and each generated review/report/audit component: at most 8,000,000
UTF-16 units; JSON nesting: at most 64. Core limits still apply. Limits are checked
and reported; nothing is truncated or partially exported. Use the CLI for larger
workloads. Only evidence **previews** are limited to the first 50 values per side,
with an explicit label; downloaded evidence is complete. Conflicts are paged by 12.

UTF-8 decoding is fatal for malformed bytes; an optional encoding BOM is accepted.
Quoted delimiters, newlines, empty strings, spaces, leading zeroes and Unicode use
the core serializers. CSV/TSV syntax is normalized, not preserved byte-for-byte.
No XLSX, encoding guessing, streaming, automatic rename detection, automatic
dependency revocation, shared server session or authenticated audit is implemented.
CSV/TSV export requires a complete core result. Text is inserted with `textContent`;
CSP disallows network connections and external resources. There is no telemetry.

The actual browser gate is **desktop Chrome**, including file-URL operation with
network emulation offline and a 390px layout. Firefox, Safari, mobile devices and
other browser engines have not been verified; the 390px screenshot is desktop
responsive-layout evidence. Library backend tests do not establish browser support.

## Repeatable browser QA

Install Node 22+ and Chrome. Install the pinned external QA tool (Apache-2.0):

```text
npm install --global @playwright/cli@0.1.22
moon run scripts/browser-check.mbtx
```

On Windows, npm's global executable is a `.cmd` wrapper. Set
`MNTABLEMERGE_PLAYWRIGHT_CLI` to that package's `playwright-cli.js` absolute path;
the MoonBit runner then invokes it through Node without shell interpolation.
`npm root --global` locates the global modules directory. No QA tool is shipped
inside the HTML. The check creates an isolated, named Playwright CLI session with
explicit local-file access in its generated test config, and closes that session.
See the [official configuration](https://playwright.dev/agent-cli/configuration).

The `.mbtx` runner drives actual upload, selection, application and download. It
checks exact CSV/TSV bytes against the release Wasm CLI, bundle round trips,
compound keys/TSV imports, empty versus missing, Unicode/markup as data, structural
phases, dependency errors/revocation, audit v2 equality, pagination/draft retention,
incomplete full evidence, stale/malformed/invalid UTF-8 rejection, cancellation,
recovery, no HTTP requests/console errors and mobile-width overflow. Fixtures,
downloads, CLI snapshots/logs and screenshots go to ignored `output/playwright/`.
The default verification also runs five bridge test blocks, strict checks and
the single-file build on all three CI operating systems; UI QA runs on Linux.

The build helper also invokes `moon info` for the JS-only bridge. Because this
module's canonical backend is Wasm, it copies the compiler's generated JS `.mbti`
to the checked-in bridge interface; CI's final Git diff catches interface drift.

The HTML embeds the project's MIT license, MoonBit core's Apache-2.0 license and
complete upstream NOTICE, plus fixture provenance. Browser app/bridge/tests are
repository-authored. See [all sources](../THIRD_PARTY.md).
