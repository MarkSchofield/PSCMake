#----------------------------------------------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2021 Mark Schofield
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#----------------------------------------------------------------------------------------------------------------------
#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/Common/CMake.ps1
. $PSScriptRoot/Common/Common.ps1

<#
 .Synopsis
  An argument-completer for `Build-CMakeBuild`'s `-Preset` parameter.
#>
function BuildPresetsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    $CMakePresetsJson = GetCMakePresets -Silent
    GetBuildPresetNames $CMakePresetsJson | Where-Object { $_ -ilike "$WordToComplete*" }
}

<#
 .Synopsis
  An argument-completer for `Build-CMakeBuild`'s `-Configurations` parameter.
#>
function BuildConfigurationsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    # TODO: A meaningful implementation would:
    #   * If a buildPreset can be resolved, see if it has a `configuration` and use that.
    #   * If not, look for a code model and use that.
    #   * If not, look at the configure preset and see if CMAKE_CONFIGURATION_TYPES is set, and use that array.
    #   * Otherwise default to Release, Debug, RelWithDebInfo, MinSizeRel
    @(
        'Release'
        'Debug'
        'RelWithDebInfo'
        'MinSizeRel'
    )
}

<#
 .Synopsis
  An argument-completer for `Build-CMakeBuild`'s `-Targets` parameter.
#>
function BuildTargetsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    $CMakePresetsJson = GetCMakePresets -Silent
    $Preset = $FakeBoundParameters.Presets | Select-Object -First 1
    $BuildPreset = $CMakePresetsJson.buildPresets | Where-Object { $_.name -eq $Preset }
    $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $BuildPreset.configurePreset }
    $BinaryDirectory = GetBinaryDirectory $ConfigurePreset
    $CMakeCodeModel = Get-CMakeBuildCodeModel $BinaryDirectory

    # TODO: Rather than picking the first configuration, see of the $FakeBoundParameters has a Configuration, or if the
    # build preset has a configuration
    $CMakeCodeModel.configurations[0].targets.name | Where-Object { $_ -ilike "$WordToComplete*" }
}

<#
 .Synopsis
  An argument-completer for `Configure-CMakeBuild`'s `-Presets` parameter.
#>
function ConfigurePresetsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    $CMakePresetsJson = GetCMakePresets -Silent
    GetConfigurePresetNames $CMakePresetsJson | Where-Object { $_ -ilike "$WordToComplete*" }
}

<#
 .Synopsis
  Configures a CMake build.

 .Description
  Configures the specified 'configurePresets' entries from a CMakePresets.json file in the current-or-higher folder.

 .Parameter Presets
  The configure preset names to use.

 .Example
   # Configure the 'windows-x64' and 'windows-x86' CMake builds.
   Configure-CMakeBuild -Presets windows-x64,windows-x86
#>
function Configure-CMakeBuild {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string[]] $Presets
    )
    $CMakePresetsJson = GetCMakePresets
    if (-not $CMakePresetsJson) {
        Write-Error "Unable to find 'CMakePresets.json' in the current folder scope."
    }

    $PresetNames = GetConfigurePresetNames $CMakePresetsJson
    if (-not $Presets) {
        $Presets = , $PresetNames[0]
        Write-Output "No preset specified, defaulting to: $Presets"
    }

    $CMake = GetCMake
    foreach ($Preset in $Presets) {
        Write-Output "Preset: $Preset"

        $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $Preset }
        if (-not $ConfigurePreset) {
            Write-Error "Unable to find configuration preset '$Preset' in $script:CMakePresetsPath"
        }

        $BinaryDirectory = GetBinaryDirectory $ConfigurePreset
        Enable-CMakeBuildQuery $BinaryDirectory

        $CMakeArguments = @(
            '--preset', $Preset
        )
        & $CMake @CMakeArguments
    }
}

<#
 .Synopsis
  Builds a CMake build.

 .Description
  Builds the specified 'buildPresets' entries from a CMakePresets.json file in the current-or-higher folder.

 .Parameter Presets

 .Parameter Configurations

 .Parameter Targets
   One or more

 .Parameter Configure
   A switch specifying whether the necessary configuration should be performed before the build is run.

 .Example
   # Build the 'windows-x64' and 'windows-x86' CMake builds.
   Build-CMakeBuild -Presets windows-x64,windows-x86

   # Build the 'windows-x64' and 'windows-x86' CMake builds, with the 'Release' configuration.
   Build-CMakeBuild -Presets windows-x64,windows-x86 -Configurations Release

   # Build the 'HelperLibrary' target, for the 'windows-x64' and 'windows-x86' CMake builds, with the 'Release'
   # configuration.
   Build-CMakeBuild -Presets windows-x64,windows-x86 -Configurations Release -Targets HelperLibrary
#>
function Build-CMakeBuild {
    param (
        [Parameter(Position = 0)]
        [string[]] $Presets,

        [Parameter(Position = 1)]
        [string[]] $Configurations,

        [Parameter(Position = 2)]
        [string[]] $Targets,

        [Parameter()]
        [switch] $Configure
    )
    $CMakePresetsJson = GetCMakePresets
    if (-not $CMakePresetsJson) {
        Write-Error "Unable to find 'CMakePresets.json' in the current folder scope."
    }

    $PresetNames = GetBuildPresetNames $CMakePresetsJson

    if (-not $Presets) {
        if (-not $PresetNames) {
            Write-Error "No Presets values specified, and one could not be inferred."
        }
        $Presets = , $PresetNames[0]
        Write-Output "No preset specified, defaulting to: $Presets"
    }

    $CMake = GetCMake
    foreach ($Preset in $Presets) {
        $BuildPreset = $CMakePresetsJson.buildPresets | Where-Object { $_.name -eq $Preset }
        if (-not $BuildPreset) {
            Write-Error "Unable to find build preset '$Preset' in $script:CMakePresetsPath"
        }

        $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $BuildPreset.configurePreset }
        if (-not $ConfigurePreset) {
            Write-Error "Unable to find configuration preset '$($BuildPreset.configurePreset)' in $script:CMakePresetsPath"
        }

        $BinaryDirectory = GetBinaryDirectory $ConfigurePreset
        $CMakeCacheFile = Join-Path -Path $BinaryDirectory -ChildPath 'CMakeCache.txt'

        # Run CMake configure if;
        #  1) "$BinaryDirectory/CMakeCache.txt" doesn't exist
        #  2) '-configure' was specified
        if ((-not (Test-Path -Path $CMakeCacheFile -PathType Leaf)) -or
            $Configure) {
            Configure-CMakeBuild -Presets $BuildPreset.configurePreset
        }

        if (-not $Configurations) {
            $CMakeArguments = @(
                '--build'
                '--preset', $Preset
                if ($Targets) {
                    '--target', $Targets
                }
            )
            & $CMake @CMakeArguments
        }
        else {
            foreach ($Configuration in $Configurations) {
                $CMakeArguments = @(
                    '--build'
                    '--preset', $Preset
                    '--config', $Configuration
                    if ($Targets) {
                        '--target', $Targets
                    }
                )
                & $CMake @CMakeArguments
            }
        }
    }
}

Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Presets -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Configurations -ScriptBlock $function:BuildConfigurationsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Targets -ScriptBlock $function:BuildTargetsCompleter
Register-ArgumentCompleter -CommandName Configure-CMakeBuild -ParameterName Presets -ScriptBlock $function:ConfigurePresetsCompleter