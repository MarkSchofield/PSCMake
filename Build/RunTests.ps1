#Requires -PSEdition Core

[CmdletBinding()]
param(
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Pester

$WorkingDirectory = $PSScriptRoot
$RepositoryRoot = Resolve-Path -Path (& git -C $WorkingDirectory rev-parse '--show-toplevel')
$Configuration = [PesterConfiguration]@{
    Run          = @{
        Path     = $RepositoryRoot
        Passthru = $true
    }
    CodeCoverage = @{
        Enabled      = $true
        Path         = "$RepositoryRoot/PSCMake"
        OutputFormat = 'JaCoCo'
        OutputPath   = "$RepositoryRoot/__output/coverage.xml"
    }
}

Invoke-Pester -Configuration $Configuration
