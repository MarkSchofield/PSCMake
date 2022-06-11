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

$CSharpCode = @'
private const uint GENERIC_READ = 0x80000000;
private const uint GENERIC_WRITE = 0x40000000;
private const uint FILE_SHARE_READ = 0x00000001;
private const uint FILE_SHARE_WRITE = 0x00000002;
private const uint OPEN_EXISTING = 3;

[DllImport("kernel32.dll", SetLastError = true, CharSet=CharSet.Unicode, ExactSpelling = true)]
private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

[DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
public static extern uint GetConsoleMode(SafeFileHandle consoleHandle, out uint mode);

public static SafeFileHandle GetConIn()
{
    SafeFileHandle fileHandle = CreateFileW("CONIN$", GENERIC_READ, FILE_SHARE_READ, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
    if (fileHandle.IsInvalid)
    {
        throw new System.ComponentModel.Win32Exception();
    }
    return fileHandle;
}

public static SafeFileHandle GetConOut()
{
    SafeFileHandle fileHandle = CreateFileW("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
    if (fileHandle.IsInvalid)
    {
        throw new System.ComponentModel.Win32Exception();
    }
    return fileHandle;
}
'@

$script:Console = $null
$script:IsVirtualTerminalProcessingEnabled = if ($IsWindows) { $null } else { $true }

function GetConsole {
    if (-not $script:Console) {
        $script:Console = Add-Type -Language CSharp -MemberDefinition $CSharpCode -Name NativeMethods -Namespace Console -PassThru -UsingNamespace 'Microsoft.Win32.SafeHandles' -ErrorAction SilentlyContinue
        if (-not $script:Console) {
            throw "Fatal error: Unable to compile the necessary C# code."
        }
    }
    $script:Console
}

<#
 .Synopsis
  Returns whether virtual terminal processing is enabled for the current console.

 .Outputs
 `$true` if virtual terminal processing is enabled, `$false` otherwise.
#>
function IsVirtualTerminalProcessingEnabled {
    if ($null -eq $script:IsVirtualTerminalProcessingEnabled) {
        $Console = GetConsole
        $ConOut = $Console::GetConOut();
        try {
            $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x04
            $Mode = 0
            if (($Console::GetConsoleMode($ConOut, [ref] $Mode) -eq 0) -or
                (-not($Mode -band $ENABLE_VIRTUAL_TERMINAL_PROCESSING))) {
                $script:IsVirtualTerminalProcessingEnabled = $false
            } else {
                $script:IsVirtualTerminalProcessingEnabled = $true
            }
        } finally {
            $ConOut.Close()
        }
    }
    $script:IsVirtualTerminalProcessingEnabled;
}

<#
 .Synopsis
  Returns the control codes to set the foreground color to the specified value.
#>
function ColorToControlCode{
    param(
        [System.Drawing.Color]$Color
    )
    if (IsVirtualTerminalProcessingEnabled) {
        "`e" + '[38;2;' + ('{0:d3}' -f $Color.R) + ';' + ('{0:d3}' -f $Color.G) + ';' + ('{0:d3}' -f $Color.B) + 'm'
    }
}

<#
 .Synopsis
  Returns the control codes to reset foreground attributes, if virtual terminal processing is enable.
#>
function ResetForegroundControlCode{
    if (IsVirtualTerminalProcessingEnabled) {
        "`e[39m"
    }
}
