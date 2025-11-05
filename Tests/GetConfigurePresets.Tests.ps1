#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
            '${hostSystemName}' = 'Linux'
            '$vendor{PSCMake}'  = 'true'
        } }
}

Describe 'GetConfigurePresets' {
    It 'Given CMakePresets.Complex.json it retrieves the correct configuration preset names.' {
        $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.Complex.json" | ConvertFrom-Json

        GetConfigurePresets $CMakePresetsJson |
            Select-Object -ExpandProperty 'name' |
            Should -Be @('linux-x64')
    }

    Context 'External strategy' {
        BeforeAll {
            Mock Get-VSEnvironment {
                $script:VSEnvironmentCalls += @{
                    Architecture      = $Architecture
                    WindowsSdkVersion = $WindowsSdkVersion
                    Toolset           = $Toolset
                    ToolsetVersion    = $ToolsetVersion
                }
                @{ MOCK_VAR = 'mock-value' }
            }
        }

        BeforeEach {
            $script:VSEnvironmentCalls = @()
        }

        It 'Calls Get-VSEnvironment with Architecture when architecture strategy is external' {
            $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.ExternalStrategy.json" | ConvertFrom-Json

            GetConfigurePresets $CMakePresetsJson | Out-Null

            $script:VSEnvironmentCalls | Where-Object { $_.Architecture -eq 'x64' } | Should -Not -BeNullOrEmpty
        }

        It 'Calls Get-VSEnvironment with WindowsSdkVersion and Toolset when both are specified' {
            $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.ExternalStrategy.json" | ConvertFrom-Json

            GetConfigurePresets $CMakePresetsJson | Out-Null

            $script:VSEnvironmentCalls |
                Where-Object {
                    $_.Architecture -eq 'x64' -and
                    $_.WindowsSdkVersion -eq '10.0.26100.0' -and
                    $_.Toolset -eq 'v143' -and
                    $_.ToolsetVersion -eq '14.40'
                } |
                Should -Not -BeNullOrEmpty
        }

        It 'Calls Get-VSEnvironment with Toolset when only toolset strategy is external' {
            $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.ExternalStrategy.json" | ConvertFrom-Json

            GetConfigurePresets $CMakePresetsJson | Out-Null

            $script:VSEnvironmentCalls |
                Where-Object { $_.Toolset -eq 'v143' -and -not $_.ToolsetVersion } |
                Should -Not -BeNullOrEmpty
        }

        It 'Attaches generatorEnvironment to presets with external strategy' {
            $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.ExternalStrategy.json" | ConvertFrom-Json

            $Presets = GetConfigurePresets $CMakePresetsJson
            $Preset = $Presets | Where-Object { $_.name -eq 'arch-only' }
            $Preset.generatorEnvironment | Should -Not -BeNullOrEmpty
        }

        It 'Does not attach generatorEnvironment to presets without external strategy' {
            $CMakePresetsJson = Get-Content "$PSScriptRoot/ReferencePresets/CMakePresets.ExternalStrategy.json" | ConvertFrom-Json

            $Presets = GetConfigurePresets $CMakePresetsJson
            $Preset = $Presets | Where-Object { $_.name -eq 'no-external-strategy' }
            Get-MemberValue $Preset 'generatorEnvironment' | Should -BeNullOrEmpty
        }
    }
}
