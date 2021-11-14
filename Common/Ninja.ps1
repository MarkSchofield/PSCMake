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
. $PSScriptRoot/Console.ps1

<#
 .Synopsis
  Tries to parse the specified Ninja log.

 .Outputs
 The entries from the Ninja log.
#>
function TryParseNinjaLog {
    [CmdletBinding()]
    param(
        [string] $NinjaLogPath
    )
    if (Test-Path -Path $NinjaLogPath -PathType Leaf) {
        Get-Content $NinjaLogPath |
            Where-Object {$_[0] -ne '#'} |
            ForEach-Object {
                $Tokens = $_ -split "\t"
                [int]$StartTime = $Tokens[0]
                [int]$EndTime = $Tokens[1]
                [pscustomobject]@{
                    StartTime=$StartTime
                    EndTime=$EndTime
                    WriteTime=([long]$Tokens[2])
                    File=$Tokens[3]
                    CommandHash=$Tokens[4]
                    Duration=($EndTime - $StartTime)
                }
            }
    }
}

$FileTimeOffset = [long]12622770400 * [long]10000000

<#
 .Synopsis
  Converts the specified Ninja log time representation into a [datetime].

 .Notes
 This function is currently Windows-only.
#>
function ConvertFrom-NinjaTime {
    param(
        $NinjaTime
    )
    [datetime]::FromFileTime([long]$NinjaTime + $FileTimeOffset)
}

<#
 .Synopsis
  Converts the specified [datetime] into Ninja log time representation.

 .Notes
 This function is currently Windows-only.
#>
function ConvertTo-NinjaTime {
    param(
        [datetime]$Time
    )
    $Time.ToFileTime() - $FileTimeOffset;
}

function Report-NinjaBuild {
    param(
        [string] $NinjaLogPath,
        [datetime] $BuildStartTime
    )
    $BuildStartNinjaTime = ConvertTo-NinjaTime $BuildStartTime
    $Entries = (TryParseNinjaLog $NinjaLogPath) |
        Where-Object {$_.WriteTime -ge $BuildStartNinjaTime}
    $Statistics = $Entries | Measure-Object -Property Duration -Maximum
    if (-not $Statistics) {
        return
    }
    $MaximumDuration = $Statistics.Maximum
    [System.Drawing.Color]$WorstColor = "#ff0000"
    [System.Drawing.Color]$BestColor = "#00ff00"
    $Entries |
        Sort-Object -Property Duration |
        ForEach-Object {
            $Color = ColorInterpolation $BestColor $WorstColor ($_.Duration / $MaximumDuration)
            [string]$_.Duration + ' ' + (ColorToControlCode $Color) + $_.File + (ResetForegroundControlCode)
        }
}

