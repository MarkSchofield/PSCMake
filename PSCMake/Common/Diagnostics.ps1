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

. $PSScriptRoot/Console.ps1

$script:IdeNames = @('VSCode', 'VisualStudio', 'File')

# Session-scoped options. Set them from $PROFILE to make them persistent.
$script:PSCMakeOptions = @{
    DiagnosticFormatting = $true
    Ide                  = 'VSCode'
}

# MSVC:  path(line[,col]) : warning C4100: message   (clang-cl uses the same shape, without the code)
# Clang: path:line[:col]: warning: message           (also GCC)
# 'loc' is the span that becomes the hyperlink. A leading Ninja-style '[n/m]' prefix is tolerated.
$script:DiagnosticPatterns = @{
    MSVC  = '^(?<lead>\s*(?:\[\d+/\d+\]\s*)?)(?<loc>(?<path>(?:[A-Za-z]:)?[^():]+?)\((?<line>\d+)(?:,(?<col>\d+))?\))\s*:\s*(?<sev>fatal error|warning|error|note)(?:\s+(?<code>[A-Za-z]+\d+))?\s*:\s*(?<msg>.*)$'
    Clang = '^(?<lead>\s*(?:\[\d+/\d+\]\s*)?)(?<loc>(?<path>(?:[A-Za-z]:)?[^:]+?):(?<line>\d+)(?::(?<col>\d+))?)\s*:\s*(?<sev>fatal error|warning|error|note)\s*:\s*(?<msg>.*)$'
}

# Diagnostics that name no source location, e.g. 'LINK : fatal error LNK1181: ...' or 'lld-link: error: ...'.
$script:DiagnosticNoLocationPattern = '^\s*(?:[^:()]*?:\s*)?(?<sev>fatal error|warning|error)(?:\s+(?<code>[A-Za-z]+\d+))?\s*:\s*(?<msg>.*)$'

<#
    .Synopsis
    Gets PSCMake's session options.

    .Parameter Name
    The option to return. If omitted, all options are returned as an object.

    .Example
    Get-PSCMakeOption Ide
#>
function Get-PSCMakeOption {
    [CmdletBinding()]
    param(
        [ValidateSet('DiagnosticFormatting', 'Ide')]
        [Parameter(Position = 0)]
        [string] $Name
    )
    if ($Name) {
        $script:PSCMakeOptions[$Name]
    } else {
        [pscustomobject] $script:PSCMakeOptions
    }
}

<#
    .Synopsis
    Sets PSCMake's session options. Options last for the session; set them in $PROFILE to persist them.

    .Parameter DiagnosticFormatting
    Whether compiler warnings and errors in build output are colored and turned into hyperlinks. Enabled by default.

    .Parameter Ide
    The IDE that diagnostic hyperlinks open: 'VSCode', 'VisualStudio' (requires Register-PSCMakeIde) or 'File' (the
    default file association, with no cursor position).

    .Example
    # Opt out of diagnostic formatting.
    Set-PSCMakeOption -DiagnosticFormatting $false
#>
function Set-PSCMakeOption {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [bool] $DiagnosticFormatting,

        [Parameter()]
        [ValidateSet('VSCode', 'VisualStudio', 'File')]
        [string] $Ide
    )
    foreach ($Name in $PSBoundParameters.Keys) {
        if ($script:PSCMakeOptions.ContainsKey($Name) -and $PSCmdlet.ShouldProcess($Name, 'Set')) {
            $script:PSCMakeOptions[$Name] = $PSBoundParameters[$Name]
        }
    }
}

<#
    .Synopsis
    Parses a line of compiler output.

    .Description
    Returns `$null` if the line is not a diagnostic. Otherwise returns Severity ('Error', 'Warning' or 'Note'), Path,
    Line, Column, Code and Message, plus LocationStart/LocationLength: the span of the line holding the location text.
    Path is `$null` (and LocationLength 0) for diagnostics that name no source location.

    .Parameter Style
    Which compiler format to try first, 'MSVC' or 'Clang'. Both are always tried, as clang-cl reports an MSVC frontend
    variant but toolchains mix.
#>
function ParseDiagnosticLine {
    param(
        [string] $Line,
        [ValidateSet('MSVC', 'Clang')]
        [string] $Style = 'MSVC'
    )
    $Order = if ($Style -eq 'MSVC') { 'MSVC', 'Clang' } else { 'Clang', 'MSVC' }
    foreach ($Name in $Order) {
        $Match = [regex]::Match($Line, $script:DiagnosticPatterns[$Name])
        if ($Match.Success) {
            return [pscustomobject]@{
                Severity       = SeverityName $Match.Groups['sev'].Value
                Path           = $Match.Groups['path'].Value.Trim()
                Line           = [int] $Match.Groups['line'].Value
                Column         = if ($Match.Groups['col'].Success) { [int] $Match.Groups['col'].Value } else { 1 }
                Code           = $Match.Groups['code'].Value
                Message        = $Match.Groups['msg'].Value
                LocationStart  = $Match.Groups['loc'].Index
                LocationLength = $Match.Groups['loc'].Length
            }
        }
    }

    $Match = [regex]::Match($Line, $script:DiagnosticNoLocationPattern)
    if ($Match.Success) {
        return [pscustomobject]@{
            Severity       = SeverityName $Match.Groups['sev'].Value
            Path           = $null
            Line           = 0
            Column         = 0
            Code           = $Match.Groups['code'].Value
            Message        = $Match.Groups['msg'].Value
            LocationStart  = 0
            LocationLength = 0
        }
    }
}

function SeverityName {
    param([string] $Text)
    switch ($Text) {
        'warning' { 'Warning' }
        'note' { 'Note' }
        default { 'Error' }
    }
}

<#
    .Synopsis
    Returns whether build output should be colored and hyperlinked: not for redirected output, 'NO_COLOR', plain-text
    rendering, or a console without virtual terminal processing.
#>
function DiagnosticColorEnabled {
    if ($env:NO_COLOR -or
        ($PSStyle.OutputRendering -eq 'PlainText') -or
        [Console]::IsOutputRedirected) {
        return $false
    }
    try {
        IsVirtualTerminalProcessingEnabled
    } catch {
        $false
    }
}

<#
    .Synopsis
    Returns the diagnostic format ('MSVC' or 'Clang') to try first for a build directory's C++ compiler.
#>
function GetDiagnosticStyle {
    param([string] $BinaryDirectory)
    $Variant = GetCacheValue $BinaryDirectory 'CMAKE_CXX_COMPILER_FRONTEND_VARIANT'
    $CompilerId = if ($Variant) { $Variant } else { GetCacheValue $BinaryDirectory 'CMAKE_CXX_COMPILER_ID' }
    if ($CompilerId -eq 'MSVC') { 'MSVC' } else { 'Clang' }
}

<#
    .Synopsis
    Resolves a diagnostic's path against a directory. Returns the full path if the file exists, otherwise `$null`.
#>
function ResolveDiagnosticPath {
    param(
        [string] $Path,
        [string] $BaseDirectory
    )
    try {
        $Candidate = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $BaseDirectory $Path }
        if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
            [System.IO.Path]::GetFullPath($Candidate)
        }
    } catch {
        $null
    }
}

<#
    .Synopsis
    Returns the URI that opens a file at a position in the given IDE.
#>
function GetDiagnosticUri {
    param(
        [string] $Ide,
        [string] $Path,
        [int] $Line,
        [int] $Column
    )
    switch ($Ide) {
        'VSCode' {
            # [uri] gives 'file:///C:/dir/file.cpp', with escaping; VS Code wants 'vscode://file/C:/dir/file.cpp:L:C'.
            $FileUri = ([uri] $Path).AbsoluteUri
            "vscode://file/$($FileUri.Substring('file:///'.Length)):${Line}:${Column}"
        }
        'VisualStudio' {
            "pscmake-vs://open?path=$([uri]::EscapeDataString($Path))&line=$Line&col=$Column"
        }
        default {
            ([uri] $Path).AbsoluteUri
        }
    }
}

<#
    .Synopsis
    Colors a diagnostic line by severity and, if its file exists, turns the location into an OSC 8 hyperlink.

    .Description
    The caller is expected to have checked `DiagnosticColorEnabled`.
#>
function FormatDiagnosticLine {
    param(
        [string] $Line,
        $Diagnostic,
        [string] $BaseDirectory,
        [string] $Ide
    )
    $Color = switch ($Diagnostic.Severity) {
        'Error' { [System.Drawing.Color]::FromArgb(255, 85, 85) }
        'Warning' { [System.Drawing.Color]::FromArgb(229, 192, 123) }
        default { [System.Drawing.Color]::FromArgb(128, 128, 128) }
    }

    $Start = $Diagnostic.LocationStart
    $Length = $Diagnostic.LocationLength
    $Location = $Line.Substring($Start, $Length)
    if ($Diagnostic.Path) {
        $FullPath = ResolveDiagnosticPath $Diagnostic.Path $BaseDirectory
        if ($FullPath) {
            $Uri = GetDiagnosticUri -Ide $Ide -Path $FullPath -Line $Diagnostic.Line -Column $Diagnostic.Column
            $Location = "`e]8;;$Uri`e\$Location`e]8;;`e\"
        }
    }

    (ColorToControlCode $Color) +
        $Line.Substring(0, $Start) + $Location + $Line.Substring($Start + $Length) +
        (ResetForegroundControlCode)
}

<#
    .Synopsis
    Pipeline filter: writes each build output line, colored and hyperlinked if it is a compiler diagnostic.

    .Description
    Lines already containing escape sequences (e.g. clang's own `-fcolor-diagnostics`) pass through untouched.
#>
function WriteAugmentedOutput {
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject,

        [string] $BaseDirectory,
        [string] $Ide,
        [string] $Style = 'MSVC'
    )
    process {
        $Line = [string] $InputObject
        if ($Line -and -not $Line.Contains("`e")) {
            $Diagnostic = ParseDiagnosticLine $Line -Style $Style
            if ($Diagnostic) {
                return FormatDiagnosticLine -Line $Line -Diagnostic $Diagnostic -BaseDirectory $BaseDirectory -Ide $Ide
            }
        }
        $Line
    }
}

<#
    .Synopsis
    Registers the URI scheme that lets diagnostic hyperlinks open Visual Studio at a line and column.

    .Description
    VS Code and file links work without setup. Visual Studio has no URI scheme that navigates to a position, so this
    registers 'pscmake-vs://' under HKCU (no elevation) to run 'Tools/Open-InVisualStudio.ps1', which drives a running
    Visual Studio through its DTE automation object.

    .Parameter Ide
    The IDE to register. Only 'VisualStudio' needs registering.

    .Parameter Remove
    Removes the registration.
#>
function Register-PSCMakeIde {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('VisualStudio')]
        [Parameter(Position = 0)]
        [string] $Ide = 'VisualStudio',

        [Parameter()]
        [switch] $Remove
    )
    $null = $Ide # Only 'VisualStudio' needs registering today; the parameter reserves room for others.
    $SchemeKey = 'HKCU:\Software\Classes\pscmake-vs'
    if ($Remove) {
        if ((Test-Path -LiteralPath $SchemeKey) -and $PSCmdlet.ShouldProcess($SchemeKey, 'Remove')) {
            Remove-Item -LiteralPath $SchemeKey -Recurse
        }
        return
    }

    $Script = Join-Path (Split-Path $PSScriptRoot -Parent) 'Tools/Open-InVisualStudio.ps1'
    $Pwsh = (Get-Process -Id $PID).Path
    $Command = "`"$Pwsh`" -NoProfile -NonInteractive -WindowStyle Hidden -File `"$Script`" `"%1`""
    if ($PSCmdlet.ShouldProcess($SchemeKey, "Register '$Command'")) {
        $null = New-Item -Path "$SchemeKey\shell\open\command" -Force
        Set-ItemProperty -LiteralPath $SchemeKey -Name '(default)' -Value 'URL:PSCMake Visual Studio'
        Set-ItemProperty -LiteralPath $SchemeKey -Name 'URL Protocol' -Value ''
        Set-ItemProperty -LiteralPath "$SchemeKey\shell\open\command" -Name '(default)' -Value $Command
    }
}
