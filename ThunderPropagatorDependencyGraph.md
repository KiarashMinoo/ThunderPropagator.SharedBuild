# ThunderPropagator family — project dependency graph

Cross-repo NuGet dependency graph for the ThunderPropagator product family, derived by grepping
each repo's actual `Directory.Packages.props` / `.csproj` `PackageReference` entries (not just
catalog listings — see the note on `ThunderPropagator.Web` below). Verified against the repo
checkouts on 2026-09-06.

```mermaid
graph TD
    Web["ThunderPropagator.Web<br/>(host application)"]
    Core["ThunderPropagator<br/>(core: Application + Infrastructure)"]
    BuildingBlocks["ThunderPropagator.BuildingBlocks"]
    Channels["ThunderPropagator.Channels"]
    Feeviders["ThunderPropagator.Feeviders"]
    RecoveryHandlers["ThunderPropagator.RecoveryHandlers"]
    ClusterMessageBuses["ThunderPropagator.ClusterMessageBuses"]
    FormatSerializers["ThunderPropagator.FormatSerializers"]
    SubscriptionMessageFormatters["ThunderPropagator.SubscriptionMessageFormatters"]
    ClientsDotNet["ThunderPropagator.Clients.DotNet"]
    ClientsSpec["ThunderPropagator.Clients<br/>(spec repo, no code)"]

    Web --> Core
    Web --> BuildingBlocks
    Web --> Channels
    Web --> Feeviders
    Web --> FormatSerializers

    Channels --> Core
    Feeviders --> Core
    RecoveryHandlers --> Core
    ClusterMessageBuses -->|Cluster variant| Core

    FormatSerializers --> BuildingBlocks
    SubscriptionMessageFormatters --> Core
    SubscriptionMessageFormatters --> FormatSerializers

    ClientsDotNet -.->|implements spec, no package dep| ClientsSpec

    classDef host fill:#F0997B,stroke:#993C1D,color:#4A1B0C;
    classDef core fill:#5DCAA5,stroke:#0F6E56,color:#04342C;
    classDef fmt fill:#AFA9EC,stroke:#534AB7,color:#26215C;
    classDef standalone fill:#B4B2A9,stroke:#5F5E5A,color:#2C2C2A;

    class Web host;
    class Core,BuildingBlocks,Channels,Feeviders,RecoveryHandlers,ClusterMessageBuses core;
    class FormatSerializers,SubscriptionMessageFormatters fmt;
    class ClientsDotNet,ClientsSpec standalone;
```

## Edges (verified)

| From | To | How |
|---|---|---|
| `ThunderPropagator.Web` | `ThunderPropagator` (core + Application) | `$(ThunderPropagatorPackageId)`, `$(ThunderPropagatorApplicationPackageId)` |
| `ThunderPropagator.Web` | `ThunderPropagator.BuildingBlocks` | `$(BuildingBlocksPackageId)` (+ `.Modules`) |
| `ThunderPropagator.Web` | `ThunderPropagator.Channels` | 16 `Feeders.*` PackageReferences in `Web.Infrastructure.csproj`, 6 production Channels + Chat + Games/Demo in `Web.csproj` |
| `ThunderPropagator.Web` | `ThunderPropagator.Feeviders` | same 16 `Feeders.*` references above |
| `ThunderPropagator.Web` | `ThunderPropagator.FormatSerializers` | `ThunderPropagator.FormatSerializers.Yaml` in `Web.Infrastructure.csproj` and `Web.Domain.csproj` |
| `ThunderPropagator.Channels` | `ThunderPropagator` (core) | `$(ThunderPropagatorPackageId)` |
| `ThunderPropagator.Feeviders` | `ThunderPropagator` (core) | `$(ThunderPropagatorPackageId)` |
| `ThunderPropagator.RecoveryHandlers` | `ThunderPropagator` (core) | `$(ThunderPropagatorPackageId)` |
| `ThunderPropagator.ClusterMessageBuses` | `ThunderPropagator` (Cluster variant) | `$(ThunderPropagatorClusterPackageId)` |
| `ThunderPropagator.FormatSerializers` | `ThunderPropagator.BuildingBlocks` | `$(BuildingBlocksPackageId)` |
| `ThunderPropagator.SubscriptionMessageFormatters` | `ThunderPropagator` (core) | `$(ThunderPropagatorPackageId)` |
| `ThunderPropagator.SubscriptionMessageFormatters` | `ThunderPropagator.FormatSerializers` | `$(MessagePackPackageId)`, `$(NetJsonPackageId)`, `$(ProtobufPackageId)`, `$(ToonPackageId)`, `$(XmlPackageId)`, `$(YamlPackageId)` (all 6 formats) |
| `ThunderPropagator.Clients.DotNet` | — | no family package dependency; implements the wire protocol documented in `ThunderPropagator.Clients` (spec-only repo, nothing to build) |

Repos with **no incoming** family dependency (foundational): `ThunderPropagator` (core), `ThunderPropagator.BuildingBlocks`.

Repos with **no outgoing** family dependency: `ThunderPropagator`, `ThunderPropagator.BuildingBlocks`, `ThunderPropagator.Clients.DotNet`.

## Note on `ThunderPropagator.Web`'s catalog

`ThunderPropagator.Web`'s `Directory.Packages.props` also lists `PackageVersion` catalog entries for
every package published by `ThunderPropagator.RecoveryHandlers`, `ThunderPropagator.SubscriptionMessageFormatters`,
and `ThunderPropagator.ClusterMessageBuses` (it doubles as a full family catalog, by its own header
comment), but **no `.csproj` in that repo actually has a `PackageReference` to any of them** — confirmed
by grepping every `.csproj` under the repo. Those three are shown above only via their real dependents
(each other / core), not via Web, since Web doesn't genuinely depend on them today.

## Build-time-only dependency (not shown above)

Every repo in this graph — including this one's own siblings — also depends on
`ThunderPropagator.SharedBuild` at *build* time (via `Directory.Build.props` → `SharedProps.props` →
the `Shared.NugetBuild.props` router), for centrally-managed build/package properties, `Shared.PackageIds.props`,
and the `Update-ThunderPropagatorDependencies.ps1` dependency updater. That's tooling, not a NuGet
package reference, so it's intentionally left off the graph above to keep it a genuine *product*
dependency graph rather than a build-infrastructure one.
