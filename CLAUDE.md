# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

PSCMake is a PowerShell module (Core 7.0+) that wraps CMake Presets workflows. It provides cmdlets to configure, build, graph, and invoke CMake projects, plus argument completers for preset/target tab-completion. It uses the CMake File API for build introspection.

## Commands

**Run tests:**

```powershell
./Build/RunTests.ps1
```

Runs all Pester tests and writes JaCoCo coverage to `__output/coverage.xml`.

**Run a single test file:**

```powershell
Invoke-Pester ./Tests/CMake.Tests.ps1
```

**Lint:**

```powershell
./Build/RunScriptAnalyzer.ps1
```

Uses PSScriptAnalyzer with settings from `.vscode/PSScriptAnalyzerSettings.psd1`. Runs against all git-tracked `.ps1`/`.psm1`/`.psd1` files. `PSUseApprovedVerbs` is intentionally suppressed — CMake-specific verbs like `Configure-CMakeBuild` are deliberate.

**Build/package:**

```powershell
./Build/Publish.ps1
```

Computes a git-height version, updates the manifest, and copies the module to `__packages/`.

## Architecture

The module is structured as a dot-sourced collection of scripts:

- **`PSCMake/PSCMake.psm1`** — entry point; dot-sources all helpers, defines public cmdlets, registers argument completers, and exports the public API.
- **`PSCMake/Common/CMake.ps1`** — largest file; all CMake preset parsing, CMakePresets.json resolution (including `include` chains), File API queries, and preset/target enumeration.
- **`PSCMake/Common/Common.ps1`** — shared utilities (path searching, file existence helpers, color interpolation).
- **`PSCMake/Common/Console.ps1`** — output/formatting helpers.
- **`PSCMake/Common/Ninja.ps1`** — Ninja build log parsing.

**Public cmdlets** (defined in `PSCMake.psm1`):

| Cmdlet                 | Purpose                           |
|------------------------|-----------------------------------|
| `Configure-CMakeBuild` | Run CMake configure step          |
| `Build-CMakeBuild`     | Run CMake build step              |
| `Write-CMakeBuild`     | Emit DGML or DOT dependency graph |
| `Invoke-CMakeOutput`   | Run a built executable target     |

**Argument completers** are registered via `Register-ArgumentCompleter` at module load time and delegate to functions in `CMake.ps1` for preset, configuration, and target enumeration.

## Tests

Test files live in `Tests/` and follow Pester conventions (`*.Tests.ps1`). Two supporting assets:

- **`Tests/ReferenceBuild/`** — a pre-built CMake output tree used by tests that exercise File API parsing without needing a real CMake invocation.
- **`Tests/ReferencePresets/`** — `CMakePresets.json` fixtures for preset resolution tests.
- **`Tests/TestUtilities.ps1`** — shared helpers dot-sourced by individual test files.

## Versioning

Version is computed from `./Version` (base semver) plus a git commit-height suffix. Branch drives the prerelease label: `develop` → `-beta{N}`, `release/*` → `-release{N}`, `feature/*` → `-alpha{N}`, `main`/`master` → no prerelease.
