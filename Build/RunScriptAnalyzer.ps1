#Requires -PSEdition Core

[CmdletBinding()]
param(
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkingDirectory = $PSScriptRoot
$RepositoryRoot = Resolve-Path -Path (& git -C $WorkingDirectory rev-parse '--show-toplevel')
$SettingsFile = Join-Path -Path $RepositoryRoot -ChildPath '.vscode\PSScriptAnalyzerSettings.psd1'
& git -C $RepositoryRoot ls-files *.ps1 *.psm1 *.psd1 |
    ForEach-Object { Get-Item -Path (Join-Path -Path $RepositoryRoot -ChildPath $_) } |
    ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings $SettingsFile } |
    ForEach-Object {
        "$($_.ScriptPath):$($_.Line):$($_.Column) [$($_.RuleName)] $($_.Message)"
    }
