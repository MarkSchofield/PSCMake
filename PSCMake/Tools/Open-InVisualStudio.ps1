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

<#
    .Synopsis
    Opens a file at a line and column in a running Visual Studio, via its DTE automation object.

    .Description
    The handler for 'pscmake-vs://open?path=<escaped path>&line=<n>&col=<n>' URIs, as registered by
    Register-PSCMakeIde. Picks the Visual Studio whose solution contains the file, else the most recently started one.
    Falls back to 'devenv /Edit' (no cursor position) if none is reachable - e.g. if Visual Studio is elevated and
    this process is not.

    .Parameter Uri
    The 'pscmake-vs://' URI.

    .Parameter Path
    .Parameter Line
    .Parameter Column
    Alternative to -Uri.
#>
[CmdletBinding(DefaultParameterSetName = 'Uri')]
param(
    [Parameter(ParameterSetName = 'Uri', Position = 0, Mandatory)]
    [string] $Uri,

    [Parameter(ParameterSetName = 'Position', Mandatory)]
    [string] $Path,

    [Parameter(ParameterSetName = 'Position')]
    [int] $Line = 1,

    [Parameter(ParameterSetName = 'Position')]
    [int] $Column = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Uri') {
    $Query = @{}
    foreach ($Pair in ([uri] $Uri).Query.TrimStart('?').Split('&', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $Name, $Value = $Pair.Split('=', 2)
        $Query[$Name] = [uri]::UnescapeDataString($Value)
    }
    $Path = $Query['path']
    $Line = [int] ($Query['line'] ?? 1)
    $Column = [int] ($Query['col'] ?? 1)
}

if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: '$Path'"
}

Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class PSCMakeVs
{
    [DllImport("ole32.dll")]
    private static extern int GetRunningObjectTable(int reserved, out IRunningObjectTable rot);

    [DllImport("ole32.dll")]
    private static extern int CreateBindCtx(int reserved, out IBindCtx ctx);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hwnd);

    // Returns every 'VisualStudio.DTE' object in the Running Object Table, keyed by its moniker display name.
    public static Dictionary<string, object> GetVisualStudios()
    {
        var result = new Dictionary<string, object>();
        IRunningObjectTable rot;
        Marshal.ThrowExceptionForHR(GetRunningObjectTable(0, out rot));
        IBindCtx ctx;
        Marshal.ThrowExceptionForHR(CreateBindCtx(0, out ctx));
        IEnumMoniker monikers;
        rot.EnumRunning(out monikers);
        var current = new IMoniker[1];
        while (monikers.Next(1, current, IntPtr.Zero) == 0)
        {
            string name;
            current[0].GetDisplayName(ctx, null, out name);
            if (name.StartsWith("!VisualStudio.DTE."))
            {
                object instance;
                rot.GetObject(current[0], out instance);
                result[name] = instance;
            }
        }
        return result;
    }
}
'@

# Visual Studio rejects automation calls while it is busy (RPC_E_CALL_REJECTED / RPC_E_SERVERCALL_RETRYLATER).
function InvokeWithRetry {
    param([scriptblock] $Action)
    for ($Attempt = 1; ; $Attempt++) {
        try {
            return & $Action
        } catch [System.Runtime.InteropServices.COMException] {
            $Busy = $_.Exception.HResult -in @(-2147418111, -2147417846)
            if ((-not $Busy) -or ($Attempt -ge 20)) {
                throw
            }
            Start-Sleep -Milliseconds 250
        }
    }
}

function SelectVisualStudio {
    param($Instances, [string] $FilePath)
    $Candidates = foreach ($Entry in $Instances.GetEnumerator()) {
        $ProcessId = [int] ($Entry.Key -split ':' | Select-Object -Last 1)
        $Started = (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)?.StartTime ?? [datetime]::MinValue
        $Solution = try { InvokeWithRetry { $Entry.Value.Solution.FullName } } catch { '' }
        $SolutionDirectory = if ($Solution) { Split-Path $Solution -Parent } else { $null }
        [pscustomobject]@{
            Dte      = $Entry.Value
            Started  = $Started
            Contains = [bool] ($SolutionDirectory -and $FilePath.StartsWith($SolutionDirectory, [System.StringComparison]::OrdinalIgnoreCase))
        }
    }
    $Candidates | Sort-Object -Property @{ Expression = 'Contains'; Descending = $true }, @{ Expression = 'Started'; Descending = $true } |
        Select-Object -First 1 -ExpandProperty Dte
}

function OpenWithDevenv {
    param([string] $FilePath)
    $VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $Devenv = if (Test-Path -LiteralPath $VsWhere) { & $VsWhere -latest -property productPath } else { $null }
    if (-not $Devenv) {
        throw 'No running Visual Studio could be driven, and devenv.exe could not be found.'
    }
    & $Devenv /Edit $FilePath
}

$FullPath = [System.IO.Path]::GetFullPath($Path)
try {
    $Dte = SelectVisualStudio (InvokeWithRetry { [PSCMakeVs]::GetVisualStudios() }) $FullPath
    if (-not $Dte) {
        throw 'No running Visual Studio.'
    }
    InvokeWithRetry {
        $null = $Dte.ItemOperations.OpenFile($FullPath)
        $Dte.ActiveDocument.Selection.MoveToLineAndOffset($Line, $Column)
        $Dte.MainWindow.Activate()
        $null = [PSCMakeVs]::SetForegroundWindow([intptr] $Dte.MainWindow.HWnd)
    }
} catch {
    Write-Warning "Visual Studio automation failed ($($_.Exception.Message)); falling back to devenv /Edit."
    OpenWithDevenv $FullPath
}
