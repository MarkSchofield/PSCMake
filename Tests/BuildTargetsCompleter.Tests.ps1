#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $Properties = PrepareReferenceBuild

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking
}

Describe 'BuildTargetsCompleter' {
    It 'Returns the targets of the default preset, default configuration when neither is specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Completions = Get-CommandCompletions "Build-CMakeBuild -Targets "

            $Completions.CompletionMatches.Count | Should -Be 3
            $Completions.CompletionMatches[0].CompletionText | Should -Be 'A_Library'
            $Completions.CompletionMatches[1].CompletionText | Should -Be 'B_Library'
            $Completions.CompletionMatches[2].CompletionText | Should -Be 'C_Library'
        }
    }
}
