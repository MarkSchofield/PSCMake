#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

    $CMakePresetsJson = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath 'CMakePresets.Single.json') |
        ConvertFrom-Json
    Mock -ModuleName PSCMake GetCMakePresets { $CMakePresetsJson }
}

Describe 'BuildConfigurationsCompleter' {
    It 'Returns the default configurations when no preset is specified' {
        $Completions = Get-CommandCompletions "Build-CMakeBuild -Configurations "
        $Completions.CompletionMatches.Count | Should -Be 4
        $Completions.CompletionMatches[0].CompletionText | Should -Be 'Release'
        $Completions.CompletionMatches[1].CompletionText | Should -Be 'Debug'
        $Completions.CompletionMatches[2].CompletionText | Should -Be 'RelWithDebInfo'
        $Completions.CompletionMatches[3].CompletionText | Should -Be 'MinSizeRel'
    }

    It 'Returns the default configurations when no preset is specified, filtered by the word to complete' {
        $Completions = Get-CommandCompletions "Build-CMakeBuild -Configurations D"
        $Completions.CompletionMatches.Count | Should -Be 1
        $Completions.CompletionMatches[0].CompletionText | Should -Be 'Debug'
    }
}
