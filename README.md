# ThunderPropagator

**ThunderPropagator** is a cutting-edge software solution designed to redefine real-time data streaming. Our mission is to provide **effortless, blazingly fast, and cloud-native streaming capabilities** for maximum impact. 

# ThunderPropagator.SharedBuild

Shared MSBuild and repository infrastructure for the open-source ThunderPropagator repositories.

This repository is the single source of truth for:
- Common MSBuild properties in Directory.Build.props
- Shared code-style rules in .editorconfig
- Shared analyzer defaults in analysers.props

## Contents

### Directory.Build.props
Defines default SDK-wide build settings expected across ThunderPropagator repositories, including:
- net10.0 default target framework when a project does not override it
- nullable reference types and implicit usings
- warnings as errors and code-style enforcement in build
- package metadata defaults such as author, company, license, SourceLink, symbols, and CI build flags

Properties are guarded with conditions so an individual repository or project can opt out explicitly when needed.

### .editorconfig
Defines shared text-formatting, C# style, and naming rules used across the ThunderPropagator repositories.

### analysers.props
Provides shared Roslyn analyzer defaults that can be imported from a consuming repository if stricter analyzer behavior is needed independently from the rest of the shared props.

## NuGet Package Versions
Package versions are managed in each product repository and packages are published directly to nuget.org from their own CI pipelines.
This repository intentionally does not include Directory.Packages.props or NuGet.Config.

## Consumption
Each ThunderPropagator repository should place these files at its root, either by copying them, consuming them from a dedicated package, or syncing them from this repository.

Minimum migration steps per repository:
1. Add Directory.Build.props to the repository root.
2. Add .editorconfig and analysers.props to the repository root.
3. Manage PackageReference versions in the product repository itself.
4. Ensure packageable projects contain README.md and icon.png if they rely on shared package metadata defaults.

## Using In .NET Projects

Use this section when onboarding a new .NET repository or migrating an existing one.

### 1. Copy shared files to the repository root

At minimum, copy these files from this repository to the root of your target .NET repository:
- Directory.Build.props
- .editorconfig
- analysers.props

Place them in the same folder as your solution file when possible.

### 2. Verify Directory.Build.props is auto-imported

MSBuild automatically imports Directory.Build.props for all SDK-style projects under that directory tree.

You can validate with:

```bash
dotnet build
```

If the file is being applied, settings like TreatWarningsAsErrors and Nullable will affect all projects without any csproj changes.

### 3. Import analysers.props for all projects (recommended)

Create a Directory.Build.targets file at the repository root to import analyzers for every project in the solution.

```xml
<Project>
	<Import Project="$(MSBuildThisFileDirectory)analysers.props"
					Condition="Exists('$(MSBuildThisFileDirectory)analysers.props')" />
</Project>
```

This keeps analyzer policy centralized and avoids repeating imports in each csproj file.

### 4. Import analysers.props in one project only (optional)

If only one project should opt in, add this inside that project's csproj file:

```xml
<Import Project="analysers.props" Condition="Exists('analysers.props')" />
```

Use this only when you intentionally want project-level differences.

### 5. Keep package versions in the product repository

This shared-build repository does not define package versions.

Each product repository should manage PackageReference versions itself, for example directly in each csproj file or with its own Directory.Packages.props.

### 6. Add a build verification step

In each product repository, run:

```bash
dotnet restore
dotnet build -c Release --no-restore
dotnet test -c Release --no-build
```

This ensures shared build rules are enforced in pull requests and release branches.

## Shortcut Options

If you want faster reuse across many repositories, use one of these shortcuts.

### Option A: One-command copy script (simple)

Create a script in each product repository to copy files from a local checkout of this repository.

PowerShell example:

```powershell
$shared = "C:\path\to\ThunderPropagator.SharedBuild"
Copy-Item "$shared\Directory.Build.props" . -Force
Copy-Item "$shared\.editorconfig" . -Force
Copy-Item "$shared\analysers.props" . -Force
```

Use this when you want explicit updates and full control.

### Option B: Git submodule (version-pinned)

Add this repository as a submodule and copy files from it in a small bootstrap script.

```bash
git submodule add https://github.com/KiarashMinoo/ThunderPropagator.SharedBuild.git build/shared
git submodule update --init --recursive
```

Use this when you want predictable, pinned shared-build versions per repository.

### Option C: Git subtree (single-repo workflow)

Pull shared files directly into each product repository while keeping normal git history in one repo.

```bash
git subtree add --prefix build/shared https://github.com/KiarashMinoo/ThunderPropagator.SharedBuild.git main --squash
```

Use this when teams prefer not to work with submodules.

### Option D: Pack as an MSBuild helper package (advanced)

Publish a small internal package that contains these props/targets and import it once in each repo.

Use this when you want centralized updates delivered via NuGet versioning.

