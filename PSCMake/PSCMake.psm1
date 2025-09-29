#----------------------------------------------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2025 Mark Schofield
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
    $null = $CommandName
    $null = $ParameterName
    $null = $CommandAst
    $null = $FakeBoundParameters
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
    $null = $CommandName
    $null = $ParameterName
    $null = $CommandAst
    $null = $FakeBoundParameters

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
    $null = $CommandName
    $null = $ParameterName
    $null = $CommandAst
    $CMakePresetsJson = GetCMakePresets -Silent
    $PresetNames = GetBuildPresetNames $CMakePresetsJson
    $PresetName = $FakeBoundParameters['Preset'] ?? $PresetNames |
        Select-Object -First 1
    $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $PresetName
    $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
    $CMakeCodeModel = Get-CMakeBuildCodeModel $BinaryDirectory

    # TODO: See if the $BuildPreset has a configuration.
    $ConfigurationName = $FakeBoundParameters['Configuration'] ?? $CMakeCodeModel.configurations.Name |
        Select-Object -First 1
    $ConfigurationsJson = $CMakeCodeModel.configurations |
        Where-Object -Property 'name' -EQ $ConfigurationName
    $TargetNames = $ConfigurationsJson.targets.name

    # Add standard CMake targets 'all', 'clean', 'install'
    $TargetNames += @(
        'all'
        'clean'
        'install'
    )

    # Add standard CMake target 'test' if 'CTestTestfile.cmake' exists in the binary directory.
    $CTestFilePath = Join-Path -Path $BinaryDirectory -ChildPath 'CTestTestfile.cmake'
    if (Test-Path -Path $CTestFilePath -PathType Leaf -ErrorAction SilentlyContinue) {
        $TargetNames += 'test'
    }

    $TargetNames |
        Where-Object { $_ -ilike "$WordToComplete*" }
}

<#
    .Synopsis
    An argument-completer for `Build-CMakeBuild`'s `-Targets` parameter.
#>
function ExecutableTargetsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    $null = $CommandName
    $null = $ParameterName
    $null = $CommandAst
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

    $TargetTuplesCodeModel = $ConfigurationsJson.targets |
        Where-Object { $_.name -ilike "$WordToComplete*" }

    # Use the 'code model' JSON to load the target-specific JSON to filter to targets with 'type' equal to 'EXECUTABLE'
    $TargetTuples = FilterExecutableTargets (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) $TargetTuplesCodeModel
    $TargetTuples.name
}

<#
    .Synopsis
    An argument-completer for `Configure-CMakeBuild`'s `-Preset` parameter.
#>
function ConfigurePresetsCompleter {
    param(
        $CommandName,
        $ParameterName,
        $WordToComplete,
        $CommandAst,
        $FakeBoundParameters
    )
    $null = $CommandName
    $null = $ParameterName
    $null = $CommandAst
    $null = $FakeBoundParameters
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

    InvokeCMake $CMake $CMakeArguments
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Configuration failed. Command line: '$($CMake.Source)' $($CMakeArguments -join ' ')"
    }
}

<#
    .Synopsis
    Configures a CMake build.

    .Description
    Configures the specified 'configurePresets' entries from a CMakePresets.json file in the current-or-higher folder.

    .Parameter Preset
    The configure preset name to use. Multiple presets can be specified.

    .Parameter Fresh
    A switch specifying whether a 'fresh' configuration is performed - removing any existing cache.

    .Example
    # Configure the 'windows-x64' and 'windows-x86' CMake builds.
    Configure-CMakeBuild -Preset windows-x64,windows-x86
#>
function Configure-CMakeBuild {
    [CmdletBinding()]
    param(
        [Alias('Presets')]
        [SupportsWildcards()]
        [Parameter()]
        [string[]] $Preset,

        [Parameter()]
        [switch] $Fresh
    )
    $CMakeRoot = FindCMakeRoot
    $CMakePresetsJson = GetCMakePresets
    $ConfigurePresetNames = GetConfigurePresetNames $CMakePresetsJson
    $ConfigurePresetNames = if (-not $Preset) {
        $ConfigurePresetNames | Select-Object -First 1
    } else {
        foreach ($CandidatePreset in $Preset) {
            $ConfigurePresetNames | Where-Object { ($_ -eq $CandidatePreset) -or ($_ -like $CandidatePreset) }
        }
    }

    $CMake = GetCMake
    Using-Location $CMakeRoot {
        foreach ($ConfigurePresetName in $ConfigurePresetNames) {
            Write-Output "Preset         : $ConfigurePresetName"

            $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $ConfigurePresetName }
            if (-not $ConfigurePreset) {
                Write-Error "Unable to find configuration preset '$ConfigurePresetName' in $script:CMakePresetsPath"
            }

            ConfigureCMake -CMake $CMake $CMakePresetsJson $ConfigurePreset -Fresh:$Fresh
        }
    }
}

<#
    .Synopsis
    Builds a CMake build.

    .Description
    Builds the specified 'buildPresets' entries from a CMakePresets.json file in the current-or-higher folder.

    .Parameter Preset

    .Parameter Configuration

    .Parameter Target
    One or more

    .Parameter Configure
    A switch specifying whether the necessary configuration should be performed before the build is run.

    .Parameter Report
    [Exploration] A switch specifying whether a report should be written of the command times of the build. Ninja builds only.

    .Parameter Fresh
    A switch specifying whether a 'fresh' configuration should be performed before the build is run.

    .Example
    # Build the 'windows-x64' and 'windows-x86' CMake builds.
    Build-CMakeBuild -Preset windows-x64,windows-x86

    # Build the 'windows-x64' and 'windows-x86' CMake builds, with the 'Release' configuration.
    Build-CMakeBuild -Preset windows-x64,windows-x86 -Configuration Release

    # Build the 'HelperLibrary' target, for the 'windows-x64' and 'windows-x86' CMake builds, with the 'Release'
    # configuration.
    Build-CMakeBuild -Preset windows-x64,windows-x86 -Configuration Release -Target HelperLibrary
#>
function Build-CMakeBuild {
    [CmdletBinding()]
    param(
        [Alias('Presets')]
        [SupportsWildcards()]
        [Parameter(Position = 0)]
        [string[]] $Preset,

        [Alias('Configurations')]
        [SupportsWildcards()]
        [Parameter(Position = 1)]
        [string[]] $Configuration,

        [Alias('Targets')]
        [Parameter(Position = 2)]
        [string[]] $Target,

        [Parameter()]
        [switch] $Configure,

        [Parameter()]
        [switch] $Report,

        [Parameter()]
        [switch] $Fresh
    )
    $CMakeRoot = FindCMakeRoot
    $CMakePresetsJson = GetCMakePresets
    $BuildPresetNames = GetBuildPresetNames $CMakePresetsJson
    $BuildPresetNames = if (-not $Preset) {
        if (-not $BuildPresetNames) {
            Write-Error "No Presets values specified, and one could not be inferred."
        }
        $BuildPresetNames | Select-Object -First 1
    } else {
        foreach ($CandidatePreset in $Preset) {
            $BuildPresetNames | Where-Object { ($_ -eq $CandidatePreset) -or ($_ -like $CandidatePreset) }
        }
    }

    # If;
    #   * no targets were specified, and
    #   * the current location is different from the cmake root
    # Then we're a scoped build!
    $ScopedBuild = (-not $Target) -and ($CMakeRoot -ne ((Get-Location).Path))
    $ScopeLocation = (Get-Location).Path
    $CMake = GetCMake
    Using-Location $CMakeRoot {
        foreach ($BuildPresetName in $BuildPresetNames) {
            Write-Output "Preset         : $BuildPresetName"

            $BuildPreset, $ConfigurePreset = ResolvePresets $CMakePresetsJson 'buildPresets' $BuildPresetName
            $BinaryDirectory = GetBinaryDirectory $CMakePresetsJson $ConfigurePreset
            $CMakeCacheFile = Join-Path -Path $BinaryDirectory -ChildPath 'CMakeCache.txt'

            # Run CMake configure if;
            #  1) '-configure' was specified
            #  2) '-fresh' was specified
            #  3) "$BinaryDirectory/CMakeCache.txt" doesn't exist
            #  4) The "Get-CMakeBuildCodeModelDirectory" folder doesn't exist
            #  5) "Get-CMakeBuildCodeModel" returns $null
            if ($Configure -or
                $Fresh -or
                (-not (Test-Path -Path $CMakeCacheFile -PathType Leaf)) -or
                (-not (Test-Path -Path (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -PathType Container)) -or
                (-not ($CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory))
                ) {
                ConfigureCMake -CMake $CMake $CMakePresetsJson $ConfigurePreset -Fresh:$Fresh
                $CodeModel = Get-CMakeBuildCodeModel $BinaryDirectory
            }

            [string[]] $ConfigurationNames = @($null)
            if ($Configuration) {
                $ConfigurationNames = foreach ($CandidateConfigurationName in $Configuration) {
                    $CodeModel.configurations.name | Where-Object { ($_ -eq $CandidateConfigurationName) -or ($_ -like $CandidateConfigurationName) }
                }
            }

            foreach ($ConfigurationName in $ConfigurationNames) {
                Write-Output "Configuration  : $ConfigurationName"

                $TargetNames = if ($ScopedBuild) {
                    $TargetTuples = GetScopedTargets $CodeModel $ConfigurationName $ScopeLocation
                    if ($TargetTuples) {
                        $TargetTuples.name
                    }
                } else {
                    $Target
                }

                $CMakeArguments = @(
                    '--build'
                    '--preset', $BuildPresetName
                    if ($ConfigurationName) {
                        '--config', $ConfigurationName
                    }
                    if ($TargetNames) {
                        '--target'
                        $TargetNames
                    }
                )

                $StartTime = [datetime]::Now
                InvokeCMake $CMake $CMakeArguments
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
    [CmdletBinding(PositionalBinding = $false)]
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
        Configure-CMakeBuild -Preset $Preset
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

    # Use the 'code model' JSON to load the target-specific JSON to filter to targets with 'type' equal to 'EXECUTABLE'
    $ExecutableTargetTuples = FilterExecutableTargets (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) $TargetTuplesCodeModel
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
Register-ArgumentCompleter -CommandName Invoke-CMakeOutput -ParameterName Target -ScriptBlock $function:ExecutableTargetsCompleter

Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Preset -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Configuration -ScriptBlock $function:BuildConfigurationsCompleter
Register-ArgumentCompleter -CommandName Build-CMakeBuild -ParameterName Target -ScriptBlock $function:BuildTargetsCompleter

Register-ArgumentCompleter -CommandName Configure-CMakeBuild -ParameterName Preset -ScriptBlock $function:ConfigurePresetsCompleter

Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Preset -ScriptBlock $function:BuildPresetsCompleter
Register-ArgumentCompleter -CommandName Write-CMakeBuild -ParameterName Configuration -ScriptBlock $function:BuildConfigurationsCompleter
