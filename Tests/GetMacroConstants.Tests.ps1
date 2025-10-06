#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1
}

Describe 'GetMacroConstants' {
    It 'Returns the correct macro constants' {
        $HostSystemName = if ($IsWindows) {
            'Windows'
        } elseif ($IsMacOS) {
            'Darwin'
        } elseif ($IsLinux) {
            'Linux'
        } else {
            Write-Error "Unsupported `${hostSystemName} value."
        }

        $MacroConstants = GetMacroConstants
        $MacroConstants['${hostSystemName}'] | Should -Be $HostSystemName
        $MacroConstants['$vendor{PSCMake}'] | Should -Be 'true'
    }
}
