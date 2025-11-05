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
    .Synopsis Parses a Visual Studio Generator's support platform specification described in [the CMake documentation
    for CMAKE_GENERATOR_PLATFORM](https://cmake.org/cmake/help/latest/variable/CMAKE_GENERATOR_PLATFORM.html#visual-studio-platform-selection)

    .Outputs A dictionary of key/value pairs. If a 'platform' value is specified, it will be included under the
    'platform' key.
#>
function ParseArchitectureValue($Value) {
    $Properties = @{}
    $Components = $Value -split ',', 0, 'SimpleMatch'
    if ($Components) {
        if ($Components[0] -notlike '*=*') {
            $Properties['platform'] = $Components[0]
            $null, $Components = $Components
        }

        foreach ($Component in $Components) {
            $ComponentName, $ComponentValue = $Component -split '=', 2, 'SimpleMatch'
            $Properties[$ComponentName] = $ComponentValue
        }
    }
    $Properties
}

function Get-VSEnvironment {
    param(
        $Toolset = 'v143',
        $Architecture = 'x64',
        $WindowsSdkVersion = '10.0.26100.0',
        $ToolsetVersion = $null,
        $HostArchitecture = 'x64'
    )
    $Environment = @{}
    $VSWherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $VSWherePath -PathType Leaf) {
        $VisualStudioVersion = if ($Toolset -eq 'v143') {
            '[17.0,18.0)'
        } elseif ($Toolset -eq 'v145') {
            '[18.0,19.0)'
        } else {
            '[17.0,)'
        }

        $VisualStudioInstallation = & $VSWherePath -version $VisualStudioVersion -products * -latest -Format Json |
            ConvertFrom-Json

        $VCVarsPath = Join-Path -Path $VisualStudioInstallation.installationPath -ChildPath "vc\Auxiliary\Build\vcvarsall.bat"
        if (Test-Path -LiteralPath $VCVarsPath -PathType Leaf) {
            $VCVarsArgs = "$Architecture $WindowsSdkVersion"
            if ($ToolsetVersion) { $VCVarsArgs += " -vcvars_ver=$ToolsetVersion" }
            [array] $VCVarsOutput = & $env:ComSpec /C "`"$VCVarsPath`" $VCVarsArgs && echo ------&& set"
            $Delimiter = $VCVarsOutput.IndexOf('------')
            $VCVarsOutput |
                Select-Object -Skip ($Delimiter + 1) |
                ForEach-Object {
                    $Name, $Value = $_ -split '=', 2, 'SimpleMatch'
                    $Environment[$Name] = $Value
                }
        }
    }
    $Environment
}
