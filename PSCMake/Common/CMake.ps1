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

. $PSScriptRoot/Common.ps1

$PreviousLocation = $null
$CMakeCandidates = @(
    (Get-Command 'cmake' -ErrorAction SilentlyContinue)
    if ($IsWindows) {
        (Join-Path -Path $env:ProgramFiles -ChildPath 'CMake/bin/cmake.exe')
    }
)

<#
 .Synopsis
  Finds the root of the CMake build - the current or ancestral folder containing a 'CMakePresets.json' file.
#>
function FindCMakeRoot {
    $CurrentLocation = (Get-Location).Path
    if ($CurrentLocation -ne $script:PreviousLocation) {
        Write-Verbose "PreviousLocation = $script:PreviousLocation"
        Write-Verbose "CurrentLocation = $CurrentLocation"
        $script:PreviousLocation = $CurrentLocation
        $script:CMakeRoot = GetPathOfFileAbove $CurrentLocation 'CMakePresets.json'
    }
    $script:CMakeRoot
}

$script:CMakePresetsPath = $null

<#
 .Synopsis
  Gets the path that the most recently loaded CMakePresets.json was loaded from.
#>
function GetCMakePresetsPath {
    $script:CMakePresetsPath
}

<#
 .Synopsis
  Loads the CMakePresets.json into a PowerShell representation.
#>
function GetCMakePresets {
    param(
        [switch] $Silent
    )
    $CMakeRoot = FindCMakeRoot
    if (-not $CMakeRoot) {
        if ($Silent) {
            return $null
        }
        Write-Error "Can't find CMakePresets.json"
    }
    $script:CMakePresetsPath = Join-Path -Path $CMakeRoot -ChildPath 'CMakePresets.json'
    Write-Verbose "Presets = $CMakePresetsPath"
    Get-Content $CMakePresetsPath | ConvertFrom-Json
}

<#
 .Synopsis
  Gets names of the 'buildPresets' in the specified CMakePresets.json object.
#>
function GetBuildPresetNames {
    param(
        $CMakePresetsJson
    )
    if ($CMakePresetsJson) {
        $Presets = $CMakePresetsJson.buildPresets

        # Filter presets that have '"hidden":true'
        $Presets = $Presets | Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) }

        # Filter presets that have (or their ancestors have) conditions that evaluate to $false
        $Presets = $Presets | Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.buildPresets }

        # Filter presets that have configure presets that have conditions that evaluate to $false
        $Presets = $Presets | Where-Object {
            $BuildPresetJson = $_
            $ConfigurePresetJson = $CMakePresetsJson.configurePresets |
                Where-Object { $_.name -eq $BuildPresetJson.configurePreset } |
                Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.configurePresets }
            $null -ne $ConfigurePresetJson
        }
        $Presets.name
    }
}

<#
 .Synopsis
  Gets names of the 'configurePresets' in the specified CMakePresets.json object.
#>
function GetConfigurePresetNames {
    param(
        $CMakePresetsJson
    )
    if ($CMakePresetsJson) {
        $Presets = $CMakePresetsJson.configurePresets

        # Filter presets that have '"hidden":true'
        $Presets = $Presets | Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) }

        # Filter presets that have (or their ancestors have) conditions that evaluate to $false
        $Presets = $Presets | Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.configurePresets }

        $Presets.name
    }
}

<#
 .Synopsis
  Finds the 'CMake' command.
#>
function GetCMake {
    $CMake = Get-Variable -Name 'CMake' -ValueOnly -Scope global -ErrorAction SilentlyContinue
    if (-not $CMake) {
        foreach ($CMakeCandidate in $CMakeCandidates) {
            $CMake = Get-Command $CMakeCandidate -ErrorAction SilentlyContinue
            if ($CMake) {
                $global:CMake = $CMake
                break
            }
        }
        if (-not $CMake) {
            Write-Error "Unable to find CMake."
        }
    }
    $CMake
}

function ResolvePresets {
    param(
        $CMakePresetsJson,

        [ValidateSet('buildPresets', 'testPresets')]
        $PresetType,

        $PresetName
    )
    $PresetJson = $CMakePresetsJson.$PresetType | Where-Object { $_.name -eq $PresetName }
    if (-not $PresetJson) {
        Write-Error "Unable to find $PresetType '$Preset' in $(GetCMakePresetsPath)"
    }

    $ConfigurePresetJson = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $PresetJson.configurePreset }
    if (-not $ConfigurePresetJson) {
        Write-Error "Unable to find configure preset '$($PresetJson.configurePreset)' in $(GetCMakePresetsPath)"
    }

    $PresetJson, $ConfigurePresetJson
}

function ResolvePresetProperty {
    param(
        $CMakePresetsJson,
        $ConfigurePreset,
        $PropertyName
    )

    for ($Preset = $ConfigurePreset; $Preset; ) {
        $PropertyValue = Get-MemberValue -InputObject $Preset -Name $PropertyName
        if ($PropertyValue) {
            return $PropertyValue
        }

        $BasePreset = Get-MemberValue $Preset 'inherits'
        if (-not $BasePreset) {
            break
        }

        $Preset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $BasePreset } | Select-Object -First 1
    }
}

function EvaluatePresetCondition {
    param(
        $PresetJson,
        $PresetsJson
    )

    $PresetConditionJson = Get-MemberValue $PresetJson 'condition'
    if ($PresetConditionJson) {
        if (-not (EvaluateCondition $PresetConditionJson $PresetJson)) {
            return $false
        }
    }

    $BasePresetName = Get-MemberValue $PresetJson 'inherits'
    if (-not $BasePresetName) {
        return $true
    }

    $BasePreset = $PresetsJson | Where-Object { $_.name -eq $BasePresetName } | Select-Object -First 1
    EvaluatePresetCondition $BasePreset $PresetsJson
}

function EvaluateCondition {
    param(
        $ConditionJson,
        $PresetJson
    )
    switch ($ConditionJson.type)
    {
        'equals' {
            return (MacroReplacement $ConditionJson.lhs $PresetJson) -eq (MacroReplacement $ConditionJson.rhs $PresetJson)
        }
        'notEquals' {
            return (MacroReplacement $ConditionJson.lhs $PresetJson) -ne (MacroReplacement $ConditionJson.rhs $PresetJson)
        }
        'const' {
            Write-Error "$_ is not yet implemented as a condition type."
            return
        }
        'inList' {
            $ExpandedString = MacroReplacement $ConditionJson.String $PresetJson
            foreach ($String in $ConditionJson.list) {
                if ($ExpandedString -eq (MacroReplacement $String $PresetJson)) {
                    return $true
                }
            }
            return $false
        }
        'notInList' {
            $ExpandedString = MacroReplacement $ConditionJson.String $PresetJson
            foreach ($String in $ConditionJson.list) {
                if ($ExpandedString -eq (MacroReplacement $String $PresetJson)) {
                    return $false
                }
            }
            return $true
        }
        'matches' {
            return (MacroReplacement $ConditionJson.string $PresetJson) -match $ConditionJson.matches
        }
        'notMatches' {
            return -not ((MacroReplacement $ConditionJson.string $PresetJson) -match $ConditionJson.matches)
        }
        'anyOf' {
            foreach ($NestedCondition in $ConditionJson.conditions) {
                if (EvaluateCondition $NestedCondition $PresetJson) {
                    return $true
                }
            }
            return $false
        }
        'allOf' {
            foreach ($NestedCondition in $ConditionJson.conditions) {
                if (-not (EvaluateCondition $NestedCondition $PresetJson)) {
                    return $false
                }
            }
            return $true
        }
        'not' {
            return -not (EvaluateCondition $ConditionJson.condition $PresetJson)
        }
    }
}

function GetBinaryDirectory {
    param(
        $CMakePresetsJson,
        $ConfigurePreset
    )
    $BinaryDirectory = ResolvePresetProperty $CMakePresetsJson $ConfigurePreset 'binaryDir'

    # Perform macro-replacement
    $Result = MacroReplacement $BinaryDirectory $ConfigurePreset

    # Canonicalize
    [System.IO.Path]::GetFullPath($Result)
}

function GetMacroConstants {
    $HostSystemName = if ($IsWindows) {
        'Windows'
    } elseif ($IsMacOS) {
        'Darwin'
    } elseif ($IsLinux) {
        'Linux'
    } else {
        Write-Error "Unsupported `${hostSystemName} value."
    }

    @{
        '${hostSystemName}'=$HostSystemName
        '$vendor{PSCMake}'='true'
    }
}

function MacroReplacement {
    param(
        $Value,
        $PresetJson
    )
    $Result = for (; $Value; $Value = $Right) {
        $Left, $Match, $Right = $Value -split '(\$\w*\{\w+\})', 2
        $Left
        switch -regex ($Match) {
            '\$\{sourceDir\}' {
                Split-Path -Path (GetCMakePresetsPath)
                break
            }
            '\$\{sourceParentDir\}' {
                Split-Path -Path (Split-Path -Path (GetCMakePresetsPath))
                break
            }
            '\$\{sourceDirName\}' {
                Split-Path -Leaf -Path (Split-Path -Path (GetCMakePresetsPath))
                break
            }
            '\$\{presetName\}' {
                $PresetJson.name
                break
            }
            '\$\{generator\}' {
                Write-Error "$_ is not yet implemented as a macro replacement."
                break
            }
            '\$\{hostSystemName\}' {
                (GetMacroConstants).$_
                break
            }
            '\$\{fileDir\}' {
                Write-Error "$_ is not yet implemented as a macro replacement."
                break
            }
            '\$\{dollar\}' {
                '$'
                break
            }
            '\$env\{([^\}]*)\}' {
                [System.Environment]::GetEnvironmentVariable($Matches[1])
            }
            '\$penv\{([^\}]*)\}' {
                Write-Error "$_ is not yet implemented as a macro replacement."
                break
            }
            '\$vendor\{\w+\}' {
                Get-MemberValue (GetMacroConstants) $_ -Or $_
                break
            }
            Default {
                $Match
                break
            }
        }
    }
    $Result -join ''
}

function Enable-CMakeBuildQuery {
    [CmdletBinding()]
    param(
        [string] $BinaryDirectory,

        [ValidateSet('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')]
        [string[]] $ObjectKinds = @('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')
    )
    $CMakeQueryApiDirectory = Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/query'
    $null = New-Item -ItemType Directory -Path $CMakeQueryApiDirectory -Force -ErrorAction SilentlyContinue
    $ObjectKinds |
        ForEach-Object {
            $QueryFile = Join-Path -Path $CMakeQueryApiDirectory -ChildPath $_
            $null = New-Item -Path $QueryFile -ItemType File -ErrorAction SilentlyContinue
        }
}

function Get-CMakeBuildCodeModelDirectory {
    param(
        [string] $BinaryDirectory
    )
    Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/reply'
}

function Get-CMakeBuildCodeModel {
    param(
        [string] $BinaryDirectory
    )
    Get-ChildItem -Path (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -File -Filter 'codemodel-v2-*' |
        Select-Object -First 1 |
        Get-Content |
        ConvertFrom-Json
}

function WriteDot {
    param (
        $Configuration,
        $CodeModel,
        $CodeModelDirectory
    )
    $Targets = @{}
    "digraph CodeModel {"
    ($CodeModel.configurations | Where-Object { $_.name -eq $Configuration }).targets |
        ForEach-Object {
            "  `"$($_.id)`" [label=`"$($_.name)`"]"
            $Targets[$_.id] = Get-Content (Join-Path -Path $CodeModelDirectory -ChildPath $_.jsonFile) | ConvertFrom-Json
        }
    $Targets.GetEnumerator() | ForEach-Object {
        $Source = $_.Name
        Get-MemberValue -InputObject $_.Value -Name dependencies -Or @() | ForEach-Object {
            "  `"$Source`" -> `"$($_.id)`" "
        }
    }
    "}"
}

function WriteDgml {
    param (
        $Configuration,
        $CodeModel,
        $CodeModelDirectory
    )
    $Targets = @{}
    '<?xml version="1.0" encoding="utf-8"?>'
    '<DirectedGraph>'
        '<Nodes>'
            ($CodeModel.configurations | Where-Object { $_.name -eq $Configuration }).targets |
                ForEach-Object {
                    '<Node'
                        "  Id=`"$($_.id)`""
                        "  Label=`"$($_.name)`""
                        '/>'

                    $TargetJson = Get-Content (Join-Path -Path $CodeModelDirectory -ChildPath $_.jsonFile) |
                        ConvertFrom-Json

                    Get-MemberValue -InputObject $TargetJson -Name artifacts -Or @() |
                        ForEach-Object {
                            '<Node'
                                "  Id=`"$($_.path)`""
                                '/>'
                        }

                    $Targets[$_.id] = $TargetJson
                }
        '</Nodes>'
        '<Links>'
            $Targets.GetEnumerator() |
                ForEach-Object {
                    $Source = $_.Name
                    Get-MemberValue -InputObject $_.Value -Name dependencies -Or @() |
                        ForEach-Object {
                        '<Link'
                            "  Source=`"$Source`""
                            "  Target=`"$($_.id)`""
                            '/>'
                    }

                    Get-MemberValue -InputObject $_.Value -Name artifacts -Or @() |
                        ForEach-Object {
                        '<Link'
                            "  Source=`"$Source`""
                            "  Target=`"$($_.path)`""
                            '/>'
                    }
                }
        '</Links>'
    '</DirectedGraph>'
}
