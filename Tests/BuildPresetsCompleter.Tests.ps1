#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

    $CMakePresetsJson = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath 'CMakePresets.Single.json') |
        ConvertFrom-Json
    Mock -ModuleName PSCMake GetCMakePresets { $CMakePresetsJson }
}

Describe 'BuildPresetsCompleter' {
    It 'Returns the presets from the discovered presets file, in the order that they are defined' {
        $Completions = Get-CommandCompletions "Build-CMakeBuild -Preset "
        $Completions.CompletionMatches.Count | Should -Be 2
        $Completions.CompletionMatches[0].CompletionText | Should -Be 'windows-x64'
        $Completions.CompletionMatches[1].CompletionText | Should -Be 'windows-arm'
    }

    It 'Returns the presets from the discovered presets file, filtered by the word to complete' {
        $Completions = Get-CommandCompletions "Build-CMakeBuild -Preset windows-a"
        $Completions.CompletionMatches.Count | Should -Be 1
        $Completions.CompletionMatches[0].CompletionText | Should -Be 'windows-arm'
    }
}
