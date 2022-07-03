#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1
}

Describe 'ResolvePresetProperty' {
    It 'Given a CMakePresets.json with a single configurationPreset, it retrieves a property from that preset' {
        $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.Single.json" | ConvertFrom-Json
        $ConfigurePreset = $CMakePresetsJson.configurePresets[0]

        $BinaryDirectory = ResolvePresetProperty $CMakePresetsJson $ConfigurePreset 'binaryDir'
        $BinaryDirectory | Should -Be '${sourceDir}/__output/${presetName}'
    }

    It 'Given a CMakePresets.json with an inherited configurationPreset, it retrieves a property from the base preset' {
        $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.Inherited.json" | ConvertFrom-Json
        $ConfigurePreset = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq 'windows-x64' } | Select-Object -First 1

        $BinaryDirectory = ResolvePresetProperty $CMakePresetsJson $ConfigurePreset 'binaryDir'
        $BinaryDirectory | Should -Be '${sourceDir}/__output/${presetName}'
    }
}
