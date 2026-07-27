# CLAUDE.md

Guidance for working in this repository.

## What this repo is

A static build-configuration repo — no source code, no solution, nothing to `dotnet build` or `dotnet test` here. Every other repository in the product family downloads these files at restore/build time and imports them, so a mistake here breaks every consumer's build simultaneously, and there is currently no automated check in this repo to catch that before it's merged.

## What lives here

- One file consumers import directly, combining SDK-wide compiler/target settings with NuGet package metadata and package-id suffix logic.
- A more granular split of the same two concerns into a pure build/compiler-defaults file and a pure packaging-metadata file (the latter also owns a self-contained icon-download-and-cleanup step, so consumers don't vendor the brand image themselves).
- An analyzer-settings file that turns on .NET analyzers and treats analyzer/compiler warnings as errors.
- A thin auto-import target whose only job is pulling the analyzer settings into every consumer without touching that consumer's own project file.
- An editor/formatting-convention file consumed the same way every other repo consumes its own copy.

## Editing conventions

- Every property should be additive/backward-compatible by default — guard consumer-overridable properties with an emptiness condition rather than forcing a value.
- Validate a change against at least one consumer repo's restore/build before merging; there's no CI gate here to catch a regression automatically.
- Tags/releases aren't used for this repo — consumers pin to a branch or commit, so avoid renaming branches or files that a live download target references without checking what breaks.
- No smoke-test project exists; if you add non-trivial logic (beyond property/import declarations), consider adding one rather than relying on downstream repos to be the test suite.
