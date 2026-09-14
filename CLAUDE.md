# CLAUDE.md

## What This Repo Is

Static build-configuration repo — no source, no solution, nothing to `dotnet build`/`dotnet test` here. Every family repo downloads these files at restore/build time and imports them. No automated check catches a breaking change here before merge — a mistake breaks every consumer's build.

## What Lives Here

- One file consumers import directly: SDK-wide compiler/target settings + NuGet package metadata + package-id suffix logic.
- A granular split of the same two concerns: pure build/compiler-defaults file, pure packaging-metadata file (also owns a self-contained icon-download-and-cleanup step).
- Analyzer-settings file: turns on .NET analyzers, treats analyzer/compiler warnings as errors.
- Thin auto-import target: pulls analyzer settings into every consumer without touching its project file.
- Editor/formatting-convention file, consumed like a consumer's own copy.
- Package-identity file: one `{Name}PackageId` property per published family package (no family package publishes a `.Cluster`-suffixed variant).
- Optional PowerShell dependency-updater: auto-discovers `{Name}PackageId`-driven entries in a consumer's `Directory.Packages.props` and bumps to latest (prerelease included), cross-referencing the package-identity file. Downloaded best-effort alongside the props files (skipped if present; absence never fails a build). Path resolution walks up from its own folder to find `Directory.Packages.props`.
- Props file wiring the dependency-updater into a consumer's restore pipeline as a report-only, pre-restore check (never mutates a tracked file; failure = warning). Prefers a consumer's own committed script copy over the auto-downloaded one.

## Editing Conventions

- Every property additive/backward-compatible by default — guard consumer-overridable properties with an emptiness condition, don't force a value.
- Validate against at least one consumer repo's restore/build before merging.
- Tags/releases unused — consumers pin to a branch/commit; avoid renaming branches/files a live download target references.
- No smoke-test project — add one for any non-trivial logic beyond property/import declarations.
