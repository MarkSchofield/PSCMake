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

<#
    .Synopsis
    Returns the value of the named property on an object, or a fallback value if the property does not exist.
#>
function Get-MemberValue {
    [CmdletBinding()]
    param(
        $InputObject,
        $Name,
        $Or = $null
    )
    (Select-Object -InputObject $InputObject -ExpandProperty $Name -ErrorAction SilentlyContinue) ?? $Or
}

<#
    .Synopsis
    Performs linear interpolation from the first color to the second.
#>
function ColorInterpolation {
    param(
        [System.Drawing.Color]$FromColor,
        [System.Drawing.Color]$ToColor,
        [Single]$T
    )

    $Alpha = $FromColor.A + (($ToColor.A - $FromColor.A) * $T)
    $Red = $FromColor.R + (($ToColor.R - $FromColor.R) * $T)
    $Green = $FromColor.G + (($ToColor.G - $FromColor.G) * $T)
    $Blue = $FromColor.B + (($ToColor.B - $FromColor.B) * $T)

    [System.Drawing.Color]::FromArgb($Alpha, $Red, $Green, $Blue)
}

<#
    .Synopsis
    Checks whether the given file is newer than any subsequently specified files.
#>
function IsUpToDate($Target) {
    $Dependencies = $args

    $TargetItem = Get-Item -Path $Target -ErrorAction SilentlyContinue
    if (-not $TargetItem) {
        return $false;
    }

    foreach ($Dependency in $Dependencies) {
        $DependentItem = Get-Item -Path $Dependency -ErrorAction SilentlyContinue
        if ((-not $DependentItem) -or ($DependentItem.LastWriteTime -gt $TargetItem.LastWriteTime)) {
            return $false;
        }
    }

    $true
}

<#
    .Synopsis
    Temporarily changes the current location to the given path, runs the script block, then restores the
    original location — even if the script block throws.
#>
function Using-Location($Location, $Scriptlet) {
    Push-Location -Path $Location
    try {
        Invoke-Command $Scriptlet
    } finally {
        Pop-Location
    }
}

<#
    .Synopsis
    Updates the LastWriteTime of the given file to the current time, equivalent to the Unix 'touch' command.
#>
function Touch($Item) {
    Write-Verbose "Touch: $Item"
    (Get-Item $Item).LastWriteTime = Get-Date
}

<#
    .Synopsis
    Downloads the resource at the given URL to the specified local path using WebClient.
#>
function DownloadFile([string] $Url, [string] $DownloadPath) {
    [System.Net.WebClient]::new().DownloadFile($Url, $DownloadPath)
}

<#
    .Synopsis
    Searches the given location and parent folders looking for the given file(s).

    .Outputs
    The path to the first matching file found, or $null if none found.
#>
function GetPathOfFileAbove([string]$Location, [string[]]$Files) {
    for (; $Location.Length -ne 0; $Location = Split-Path $Location) {
        foreach ($File in $Files) {
            $Candidate = Join-Path -Path $Location -ChildPath $File
            if (Test-Path -PathType Leaf -Path $Candidate) {
                $Candidate
                break
            }
        }
    }
}

<#
    .Synopsis
    Converts named items on a Pipeline into a hash table.
#>
filter ToHashTable {
    begin { $Result = @{} }
    process { $Result[$_.Name] = $_.Value }
    end { $Result }
}
