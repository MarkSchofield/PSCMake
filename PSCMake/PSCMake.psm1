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

function ConfigureCMake {
    param(
        [Parameter()]
        $CMake,

        [Parameter()]
        $CMakePresetsJson,

        [Parameter()]
        $ConfigurePreset,

        [switch] $Fresh
    )
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
    Enable-CMakeBuildQuery $BinaryDirectory

    $CMakeArguments = @(
        '--preset', $ConfigurePreset.name
        if ($Fresh) {
            '--fresh'
        }
        if ($VerbosePreference) {
            '--log-level=VERBOSE'
        }
    )
    Write-Verbose "CMake Arguments: $CMakeArguments"

    & $CMake @CMakeArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Configuration failed. Command line: '$($CMake.Source)' $($CMakeArguments -join ' ')"
    }
}

<#
 .Synopsis
  Configures a CMake build.

 .Description
  Configures the specified 'configurePresets' entries from a CMakePresets.json file in the current-or-higher folder.

 .Parameter Presets
  The configure preset names to use.

.Parameter Fresh
  A switch specifying whether a 'fresh' configuration is performed - removing any existing cache.

 .Example
   # Configure the 'windows-x64' and 'windows-x86' CMake builds.
   Configure-CMakeBuild -Presets windows-x64,windows-x86
#>
function Configure-CMakeBuild {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]] $Presets,

        [Parameter()]
        [switch] $Fresh
    )
    $CMakeRoot = FindCMakeRoot
    $CMakePresetsJson = GetCMakePresets
    $PresetNames = GetConfigurePresetNames $CMakePresetsJson
    if (-not $Presets) {
        $Presets = $PresetNames | Select-Object -First 1
        Write-Information "No preset specified, defaulting to: $Presets"
    }

    $CMake = GetCMake
    Using-Location $CMakeRoot {
        foreach ($Preset in $Presets) {
            Write-Output "Preset         : $Preset"

            $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $Preset }
            if (-not $ConfigurePreset) {
                Write-Error "Unable to find configuration preset '$Preset' in $script:CMakePresetsPath"
            }

            ConfigureCMake $CMake $CMakePresetsJson $ConfigurePreset -Fresh:$Fresh
        }
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

 .Parameter Fresh
   A switch specifying whether a 'fresh' configuration should be performed before the build is run.

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
        [switch] $Report,

        [Parameter()]
        [switch] $Fresh
    )
    $CMakeRoot = FindCMakeRoot
    $CMakePresetsJson = GetCMakePresets
    $PresetNames = GetBuildPresetNames $CMakePresetsJson

    if (-not $Presets) {
        if (-not $PresetNames) {
            Write-Error "No Presets values specified, and one could not be inferred."
        }
        $Presets = $PresetNames | Select-Object -First 1
    }

    # If;
    #   * no targets were specified, and
    #   * the current location is different from the cmake root
    # Then we're a scoped build!
    $ScopedBuild = (-not $Targets) -and ($CMakeRoot -ne ((Get-Location).Path))
    $ScopeLocation = (Get-Location).Path
    $CMake = GetCMake
    Using-Location $CMakeRoot {
        foreach ($Preset in $Presets) {
            Write-Output "Preset         : $Preset"

            $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $Preset
            $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
            $CMakeCacheFile = Join-Path -Path $BinaryDirectory -ChildPath 'CMakeCache.txt'

            # Run CMake configure if;
            #  1) '-configure' was specified
            #  2) '-fresh' was specified
            #  3) "$BinaryDirectory/CMakeCache.txt" doesn't exist
            #  4) The "Get-CMakeBuildCodeModelDirectory" folder doesn't exist
            if ($Configure -or
                $Fresh -or
                (-not (Test-Path -Path $CMakeCacheFile -PathType Leaf)) -or
                (-not (Test-Path -Path (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -PathType Container))) {
                ConfigureCMake $CMake $CMakePresetsJson $ConfigurePreset -Fresh:$Fresh
            }

            $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory

            foreach ($Configuration in $Configurations) {
                Write-Output "Configuration  : $Configuration"

                if ($ScopedBuild) {
                    $TargetTuples = GetScopedTargets $CodeModel $Configuration $ScopeLocation
                    $Targets = if ($TargetTuples) {
                        $TargetTuples.name
                    } else {
                        @()
                    }
                    Write-Output "Scoped Targets : $Targets"
                }

                $CMakeArguments = @(
                    '--build'
                    '--preset', $Preset
                    if ($Targets) {
                        '--target', $Targets
                    }
                )

                Write-Verbose "CMake Arguments: $CMakeArguments"

                $StartTime = [datetime]::Now
                & $CMake @CMakeArguments (($Configuration)?('--config', $Configuration):$null)
                if ($LASTEXITCODE -ne 0) {
                    Write-Error "Build failed. Command line: '$($CMake.Source)' $($CMakeArguments -join ' ')"
                }

                if ($Report) {
                    Report-NinjaBuild (Join-Path $BinaryDirectory '.ninja_log') $StartTime
                }
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

        [ValidateSet('dot', 'dgml')]
        [string] $As = 'dot'
    )
    $CMakePresetsJson = GetCMakePresets
    $PresetNames = GetBuildPresetNames $CMakePresetsJson

    if (-not $Preset) {
        if (-not $PresetNames) {
            Write-Error "No Preset values specified, and one could not be inferred."
        }
        $Preset = $PresetNames | Select-Object -First 1
        Write-Information "No preset specified, defaulting to: $Preset"
    }

    $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $Preset
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
    $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory
    $CodeModelDirectory = Get-CMakeBuildCodeModelDirectory $BinaryDirectory

    if (-not $Configuration) {
        $Configuration = 'Debug'
    }

    if ($As -eq 'dot') {
        WriteDot $Configuration $CodeModel $CodeModelDirectory
    } elseif ($As -eq 'dgml') {
        WriteDgml $Configuration $CodeModel $CodeModelDirectory
    }
}

<#
 .Synopsis
 Runs the output of a CMake build.

 .Description
 `Invoke-CMakeOutput` runs the output of a CMake build. A {preset,configuration,target} can be specified, and `Invoke-CMakeOutput`
 will build the target, use the CMake code-model to discover the path to the generated executable and run it, passing any
 extra parameter specified. If `Invoke-CMakeOutput` is run from a folder that only contains a single executable target,
 then that target will be built and run.

 .Parameter Preset
 The CMake preset to use. If none is specified, then the first valid preset from CMakePresets.json is used.

 .Parameter Configuration
 The CMake configuration to use. If none is specified, then the first valid configuration is used.

 .Parameter Target
 The CMake target that produces an executable to run.

 .Parameter SkipBuild
 If specified, the build will be skipped, otherwise a build will be run before invoking the output.

 .Parameter Arguments
 All other parameters will be passed to the discovered executable.

#>
function Invoke-CMakeOutput {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [Parameter()]
        [string] $Preset,

        [Parameter()]
        [string] $Configuration,

        [Parameter()]
        [string] $Target,

        [Parameter()]
        [switch] $SkipBuild,

        [Parameter(ValueFromRemainingArguments)]
        [string[]] $Arguments
    )
    $CMakePresetsJson = GetCMakePresets
    $PresetNames = GetBuildPresetNames $CMakePresetsJson

    if (-not $Preset) {
        if (-not $PresetNames) {
            Write-Error "No Presets values specified, and one could not be inferred."
        }
        $Preset = $PresetNames | Select-Object -First 1
    }

    $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $Preset
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset

    # Find the 'code model' for the preset. If no code model is found, configure the build and try again.
    #
    $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory
    if (-not $CodeModel) {
        Configure-CMakeBuild -Presets $Preset
        $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory
    }

    # Find the 'code model' target JSON. If a target was specified, use that, otherwise find targets within the current
    # scope.
    #
    $TargetTuplesCodeModel = if ($Target) {
        GetNamedTarget $CodeModel $Configuration $Target
    } else {
        $ScopeLocation = (Get-Location).Path
        GetScopedTargets $CodeModel $Configuration $ScopeLocation
    }

    # For the 'code model' JSON that was found, load the full 'target' JSON to be able to find 'EXECUTABLE' targets.
    #
    $TargetTuples = $TargetTuplesCodeModel |
        ForEach-Object {
            Join-Path -Path (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -ChildPath $_.jsonFile |
                Get-Item |
                Get-Content |
                ConvertFrom-Json
        }
    $ExecutableTargetTuples = $TargetTuples |
        Where-Object {
            $_.type -eq 'EXECUTABLE'
        }
    $Count = ($ExecutableTargetTuples | Measure-Object).Count
    if ($Count -eq 0) {
        Write-Error "No executable target in scope."
    }

    if ($Count -ne 1) {
        Write-Error "Multiple executable scoped targets match. Specify a target explicitly: $($ExecutableTargetTuples.name)"
    }

    # Having resolved presets/configuration/target, there is enough information to build or run. If we weren't told to
    # skip the build, then build.
    #
    if (-not $SkipBuild) {
        Write-Output "Build: $($ExecutableTargetTuples.name)"
        Write-Output '----'
        Build-CMakeBuild -Presets $Preset -Configurations $Configuration -Targets $ExecutableTargetTuples.name
    }

    # Build the fully qualified path to the output of the target an invoke it with the specified arguments.
    #
    $TargetNamePath = $ExecutableTargetTuples.nameOnDisk
    $TargetRelativePath = ($ExecutableTargetTuples.artifacts | Where-Object { $_.path.endsWith($TargetNamePath) }).path
    $TargetPath = Join-Path -Path $CodeModel.paths.build -ChildPath $TargetRelativePath

    Write-Output "Running: $TargetPath $Arguments"
    Write-Output '----'
    & $TargetPath @Arguments
}

Register-ArgumentCompleter -CommandName Invoke-CMakeOutput -ParameterName Preset -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Invoke-CMakeOutput -ParameterName Configuration -ScriptBlock $function:BuildConfigurationsCompleter
Register-ArgumentCompleter -CommandName Invoke-CMakeOutput -ParameterName Target -ScriptBlock $function:BuildTargetsCompleter

Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Presets -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Configurations -ScriptBlock $function:BuildConfigurationsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Targets -ScriptBlock $function:BuildTargetsCompleter

Register-ArgumentCompleter -CommandName Configure-CMakeBuild -ParameterName Presets -ScriptBlock $function:ConfigurePresetsCompleter

Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Preset -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Configuration -ScriptBlock $function:BuildConfigurationsCompleter
