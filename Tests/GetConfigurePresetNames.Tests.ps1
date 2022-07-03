#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
        '${hostSystemName}'='Linux'
        '$vendor{PSCMake}'='true'
    } }
}

Describe 'GetConfigurePresetNames' {
    It 'Given CMakePresets.Complex.json it retrieves the correct configuration preset names.' {
        $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.Complex.json" | ConvertFrom-Json

        GetConfigurePresetNames $CMakePresetsJson |
            Should -Be @('linux-x64')
    }
}
