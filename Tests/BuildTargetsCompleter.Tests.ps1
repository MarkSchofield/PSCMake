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
            $Completions = Get-CommandCompletion "Build-CMakeBuild -Targets "

            $Completions.CompletionMatches.Count | Should -Be 10
            $Completions.CompletionMatches.CompletionText | Should -Be @(
                'A_Library'
                'B_Library'
                'C_Library'
                'SubDirectoryOther_Executable'
                'SubDirectoryOther_Library'
                'SubDirectory_Executable'
                'SubDirectory_Library'
                'all'
                'clean'
                'install'
            )
        }
    }
}
