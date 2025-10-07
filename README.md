# A PowerShell Module for CMake Builds

This repo contains a PowerShell Module for running CMake builds that use [CMake Presets][cmake-presets]. CMake Presets
provide a declaration - through a JSON file - of the available builds, where their binary directories should be, and all
sorts of useful metadata that makes it easier to build standard tooling around the build. This PowerShell module is one
attempt at such tooling.

The PSCMake PowerShell module supports:

1. configuring and building a CMake build,
2. generating a 'DGML'- or 'DOT'- file for a build,
3. invoking executable CMake build outputs.

By leveraging the CMake file API, the module is able to offer tab-completion for presets, configurations and targets, and can implicitly scope the build based on the current working directory.

[![build status](https://github.com/MarkSchofield/PSCMake/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/MarkSchofield/PSCMake/actions/workflows/ci.yaml?query=branch%3Amain)

[![codecov](https://codecov.io/gh/MarkSchofield/PSCMake/branch/develop/graph/badge.svg?token=DS41WQROME)](https://codecov.io/gh/MarkSchofield/PSCMake)

## Installation

To install the module, use PowerShell's `Import-Module` CmdLet:

```powershell
> Import-Module PSCMake
```

Note: The module uses unapproved PowerShell verbs, preferring CMake verbs. As a result, the Import-Module will report
warnings when importing the module.

## Usage

The module provides the following commands:

1. `Configure-CMakeBuild` - To run CMake configuration for a given preset
2. `Build-CMakeBuild` - To run a CMake build.
3. `Write-CMakeBuild` - To output the CMake build as a DOT or DGML graph.
4. `Invoke-CMakeOutput` - To run an executable output from a CMake build, by target name or implicitly by scope.

Running `Build-CMakeBuild` by itself would run the first `buildConfiguration`. Run any command with `-?` to get more
details.

[cmake-presets]: <https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html> "CMake Presets"
