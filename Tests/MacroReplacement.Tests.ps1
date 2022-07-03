#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
        '${hostSystemName}'='Linux'
        '$vendor{PSCMake}'='true'
    } }

    Mock GetCMakePresetsPath {
        'C:\chunky\bacon\CMakePresets.json'
    }

    $PresetJson = ConvertFrom-Json -InputObject @'
    {
        "name": "windows-x64",
        "configurePreset": "windows-x64"
    }
'@
}

Describe 'MacroReplacement' {
    It 'Expands ${sourceDir}' {
        MacroReplacement '${sourceDir}' $PresetJson |
            Should -Be 'C:\chunky\bacon'
    }

    It 'Expands ${sourceParentDir}' {
        MacroReplacement '${sourceParentDir}' $PresetJson |
            Should -Be 'C:\chunky'
    }

    It 'Expands ${sourceDirName}' {
        MacroReplacement '${sourceDirName}' $PresetJson |
            Should -Be 'bacon'
    }

    It 'Expands ${presetName}' {
        MacroReplacement '${presetName}' $PresetJson |
            Should -Be 'windows-x64'
    }

    It 'Expands ${hostSystemName}' {
        MacroReplacement '${hostSystemName}' $PresetJson |
            Should -Be 'Linux'
    }

    It 'Expands ${dollar}' {
        MacroReplacement '${dollar}' $PresetJson |
            Should -Be '$'
    }

    It 'Expands $vendor{PSCMake}' {
        MacroReplacement '$vendor{PSCMake}' $PresetJson |
            Should -Be 'true'
    }

    It 'Does not expand unknown vendor strings' {
        MacroReplacement '$vendor{Bacon}' $PresetJson |
            Should -Be '$vendor{Bacon}'
    }
}
