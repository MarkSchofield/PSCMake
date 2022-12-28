# A PowerShell Module for CMake Builds

This repo contains a PowerShell Module for running CMake builds that use [CMake Presets][cmake-presets]. CMake Presets
provide a declaration - through a JSON file - of the available builds, where their binary directories should be, and all
sorts of useful metadata that makes it easier to build standard tooling around the build. This PowerShell module is one
attempt at such tooling.

At the minute the PowerShell module simply surfaces the ability to configure and build using CMake. By leveraging the
CMake file API, the module is able to offer tab-completion when specifying targets to build.

[![build status](https://github.com/MarkSchofield/PSCMake/actions/workflows/ci.yaml/badge.svg?branch=main)](https://github.com/MarkSchofield/PSCMake/actions/workflows/ci.yaml?query=branch%3Amain)

[![codecov](https://codecov.io/gh/MarkSchofield/PSCMake/branch/develop/graph/badge.svg?token=DS41WQROME)](https://codecov.io/gh/MarkSchofield/PSCMake)

## Installation

To install the module, use PowerShell's `Import-Module` CmdLet:

```powershell
> Import-Module PSCMake.psd1
```

Note: The module uses unapproved PowerShell verbs, preferring CMake verbs. As a result, the Import-Module will report
warnings when importing the module.

## Usage

The module provides the following commands:

1. `Configure-CMakeBuild` - To run CMake configuration for a given preset
2. `Build-CMakeBuild` - To run a CMake build.
3. `Write-CMakeBuild` - To output the CMake build as a DOT or DGML graph.

Running `Build-CMakeBuild` by itself would run the first `buildConfiguration`. Run either command with `-?` to get more
details.

[cmake-presets]: <https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html> "CMake Presets"
