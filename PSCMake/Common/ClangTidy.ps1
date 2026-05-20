#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/Common.ps1

$ClangTidyCandidates = @(
    (Get-Command 'clang-tidy' -ErrorAction SilentlyContinue)
    if ($IsWindows) {
        (Join-Path -Path $env:ProgramFiles -ChildPath 'LLVM/bin/clang-tidy.exe')
    }
)

<#
    .Synopsis
    Finds the clang-tidy command.
#>
function GetClangTidy {
    param(
        [switch] $Silent
    )
    $ClangTidy = Get-Variable -Name 'ClangTidy' -ValueOnly -Scope script -ErrorAction SilentlyContinue
    if (-not $ClangTidy) {
        foreach ($Candidate in $ClangTidyCandidates) {
            $ClangTidy = Get-Command $Candidate -ErrorAction SilentlyContinue
            if ($ClangTidy) {
                $ClangTidy = $ClangTidy.Source
                $script:ClangTidy = $ClangTidy
                break
            }
        }
        if (-not $ClangTidy) {
            if (-not $Silent) {
                Write-Error "Unable to find clang-tidy."
            }
            return $null
        }
    }
    $ClangTidy
}

<#
    .Synopsis
    Returns the list of available clang-tidy checks.
#>
function GetClangTidyChecks {
    param(
        [string] $Checks = '*'
    )
    $ClangTidy = GetClangTidy -Silent
    if (-not $ClangTidy) {
        return @()
    }
    & $ClangTidy '--list-checks' "--checks=$Checks" 2>$null |
        Select-Object -Skip 1 |
        ForEach-Object { $_.Trim() }
}
