#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $Properties = PrepareReferenceBuild

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking
}

Describe 'ExecutableTargetsCompleter' {
    It 'Returns the executable targets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Completions = Get-CommandCompletion "Invoke-CMakeOutput -Target "
            $Completions.CompletionMatches.CompletionText | Should -Be @(
                'SubDirectoryOther_Executable',
                'SubDirectory_Executable'
            )
        }
    }
}
