# Independent catalog consumer

This is a separate MoonBit module importing only the public table-merge package.
The catalog strings are synthetic; the release check additionally generates a
real-data test from the licensed OurAirports records in the actual archive.

Run `moon run scripts/release-check.mbtx` from the repository root, or follow
[`docs/adoption.md`](../../docs/adoption.md) to create a local workspace. This
module cannot resolve the unpublished registry dependency on its own. All code
here is repository-authored under the project's MIT license.
