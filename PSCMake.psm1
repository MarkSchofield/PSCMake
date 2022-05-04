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
. $PSScriptRoot/Common/Ninja.ps1

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
    ) | Where-Object { $_ -ilike "$WordToComplete*" }
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
    $PresetNames = GetBuildPresetNames $CMakePresetsJson
    $PresetName = $FakeBoundParameters['Presets'] ?? $PresetNames |
        Select-Object -First 1
    $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $PresetName
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
    $CMakeCodeModel = Get-CMakeBuildCodeModel $BinaryDirectory

    # TODO: See if the $BuildPreset has a configuration.
    $ConfigurationName = $FakeBoundParameters['Configurations'] ?? $CMakeCodeModel.configurations.Name |
        Select-Object -First 1
    $ConfigurationsJson = $CMakeCodeModel.configurations |
        Where-Object -Property 'name' -EQ $ConfigurationName
    $TargetNames = $ConfigurationsJson.targets.name
    $TargetNames |
        Where-Object { $_ -ilike "$WordToComplete*" }
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
    param(
        [Parameter()]
        [string[]] $Presets
    )
    $CMakePresetsJson = GetCMakePresets
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

        $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
        Enable-CMakeBuildQuery $BinaryDirectory

        $CMakeArguments = @(
            '--preset', $Preset
            if ($VerbosePreference) {
                '--log-level=VERBOSE'
            }
        )

        Write-Verbose "CMake Arguments: $CMakeArguments"

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

 .Parameter Report
   [Exploration] A switch specifying whether a report should be written of the command times of the build. Ninja builds only.

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
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]] $Presets,

        [Parameter(Position = 1)]
        [string[]] $Configurations = @($null),

        [Parameter(Position = 2)]
        [string[]] $Targets,

        [Parameter()]
        [switch] $Configure,

        [Parameter()]
        [switch] $Report
    )
    $CMakePresetsJson = GetCMakePresets
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
        $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $Preset
        $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
        $CMakeCacheFile = Join-Path -Path $BinaryDirectory -ChildPath 'CMakeCache.txt'

        # Run CMake configure if;
        #  1) "$BinaryDirectory/CMakeCache.txt" doesn't exist
        #  2) '-configure' was specified
        if ((-not (Test-Path -Path $CMakeCacheFile -PathType Leaf)) -or
            $Configure) {
            Configure-CMakeBuild -Presets $BuildPreset.configurePreset
        }

        $CMakeArguments = @(
            '--build'
            '--preset', $Preset
            if ($Targets) {
                '--target', $Targets
            }
        )

        Write-Verbose "CMake Arguments: $CMakeArguments"

        foreach ($Configuration in $Configurations) {
            $StartTime = [datetime]::Now
            & $CMake @CMakeArguments (($Configuration)?('--config', $Configuration):$null)
            if ($Report) {
                Report-NinjaBuild (Join-Path $BinaryDirectory '.ninja_log') $StartTime
            }
        }
    }
}

function Write-CMakeBuild {
    param(
        [Parameter(Position = 0)]
        [string] $Preset,

        [Parameter(Position = 1)]
        [string] $Configuration,

        [ValidateSet('dot')]
        [string] $As
    )
    $CMakePresetsJson = GetCMakePresets
    $PresetNames = GetBuildPresetNames $CMakePresetsJson

    if (-not $Preset) {
        if (-not $PresetNames) {
            Write-Error "No Preset values specified, and one could not be inferred."
        }
        $Preset = $PresetNames[0]
        Write-Output "No preset specified, defaulting to: $Preset"
    }

    $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $Preset
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
    $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory
    $CodeModelDirectory = Get-CMakeBuildCodeModelDirectory $BinaryDirectory

    if (-not $Configuration) {
        $Configuration = 'Debug'
    }

    WriteDot $Configuration $CodeModel $CodeModelDirectory
}

Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Presets -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Configurations -ScriptBlock $function:BuildConfigurationsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Targets -ScriptBlock $function:BuildTargetsCompleter
Register-ArgumentCompleter -CommandName Configure-CMakeBuild -ParameterName Presets -ScriptBlock $function:ConfigurePresetsCompleter
Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Preset -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Configuration -ScriptBlock $function:BuildConfigurationsCompleter
