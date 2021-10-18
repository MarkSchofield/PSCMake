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

$script:PreviousLocation = $null

<#
 .Synopsis
  Finds a 'CMakePresets.json' file in the current folder, or an ancestral folder.
#>
function FindPresetsPath {
    $CurrentPath = (Get-Location).Path
    while ($CurrentPath.Length -ne 0) {
        $CandidatePath = Join-Path -Path $CurrentPath -ChildPath 'CMakePresets.json'
        if (Test-Path -PathType Leaf -Path $CandidatePath) {
            return $CandidatePath
        }
        $CurrentPath = Split-Path $CurrentPath
    }
}

<#
 .Synopsis
  Loads the CMakePresets.json into a PowerShell representation.
#>
function GetCMakePresets {
    param(
        [switch] $Silent
    )
    $CurrentLocation = (Get-Location).Path
    if ($CurrentLocation -ne $script:PreviousLocation) {
        Write-Verbose "PreviousLocation = $script:PreviousLocation"
        Write-Verbose "CurrentLocation = $CurrentLocation"

        $script:PreviousLocation = $CurrentLocation
        $script:CMakePresetsPath = FindPresetsPath
        if (-not $script:CMakePresetsPath) {
            if ($Silent) {
                $script:CMakePresetsJson = $null
                return $script:CMakePresetsJson
            }
            Write-Error "Can't find CMakePresets.json"
        }
        Write-Verbose "Presets = $script:CMakePresetsPath"
        $script:CMakePresetsJson = Get-Content $script:CMakePresetsPath | ConvertFrom-Json
    }
    $script:CMakePresetsJson
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
        $CMakePresetsJson.buildPresets |
            Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) } |
            ForEach-Object { $_.name }
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
        $CMakePresetsJson.configurePresets |
            Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) } |
            ForEach-Object { $_.name }
    }
}

<#
 .Synopsis
  Finds the 'CMake' command.
#>
function GetCMake {
    $CMake = Get-Variable -Name 'CMake' -ValueOnly -Scope global -ErrorAction SilentlyContinue
    if (-not $CMake) {
        $CMakeCandidates = @(
            (Get-Command 'cmake' -ErrorAction SilentlyContinue)
            if ($IsWindows) {
                (Join-Path -Path $env:ProgramFiles -ChildPath 'CMake/bin/cmake.exe')
            }
        )
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
    param (
        $CMakePresetsJson,
        $BuildPresetName
    )

    $BuildPreset = $CMakePresetsJson.buildPresets | Where-Object { $_.name -eq $BuildPresetName }
    if (-not $BuildPreset) {
        Write-Error "Unable to find build preset '$Preset' in $script:CMakePresetsPath"
    }

    $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $BuildPreset.configurePreset }
    if (-not $ConfigurePreset) {
        Write-Error "Unable to find configuration preset '$($BuildPreset.configurePreset)' in $script:CMakePresetsPath"
    }

    $BuildPreset, $ConfigurePreset
}

function ResolvePresetProperty {
    param(
        $BuildPreset,
        $PropertyName
    )

    for ($Preset = $BuildPreset; $Preset; ) {
        $PropertValue = $Preset.$PropertyName
        if ($PropertValue) {
            return $PropertValue
        }

        $BasePreset = $Preset.inherits
        if (-not $BasePreset) {
            break
        }

        $Preset = $CMakePresetsJson.buildPresets | Where-Object { $_.name -eq $BasePreset } | Select-Object -First 1
    }
}

function GetBinaryDirectory {
    param(
        $BuildPreset
    )
    $BinaryDirectory = ResolvePresetProperty $BuildPreset 'binaryDir'

    # Perform macro-replacement
    $Result = for (; $BinaryDirectory; $BinaryDirectory = $Right) {
        $Left, $Match, $Right = $BinaryDirectory -split '(\$\w*\{\w+\})', 2
        $Left
        switch -regex ($Match) {
            '\$\{sourceDir\}' { Split-Path $CMakePresetsPath }
            '\$\{presetName\}' { $BuildPreset.name }
            Default {}
        }
    }

    # Canonicalize
    [System.IO.Path]::GetFullPath($Result -join '')
}

function Enable-CMakeBuildQuery {
    [CmdletBinding()]
    param (
        [string] $BinaryDirectory,

        [ValidateSet('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')]
        [string[]] $ObjectKinds = @('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')
    )
    $CMakeQueryApiDirectory = Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/query'
    $null = mkdir $CMakeQueryApiDirectory -ErrorAction SilentlyContinue
    $ObjectKinds |
        ForEach-Object {
            $QueryFile = Join-Path -Path $CMakeQueryApiDirectory -ChildPath $_
            $null = New-Item -Path $QueryFile -ItemType File -ErrorAction SilentlyContinue
        }
}

function Get-CMakeBuildCodeModel {
    param (
        [string] $BinaryDirectory
    )
    $CMakeReplyApiDirectory = Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/reply'
    Get-ChildItem -Path $CMakeReplyApiDirectory -File -Filter 'codemodel-v2-*' |
        Select-Object -First 1 |
        Get-Content |
        ConvertFrom-Json
}
