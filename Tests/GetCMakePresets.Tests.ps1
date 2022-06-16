#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1
}

Describe 'GetCMakePresets' {
    It 'Loads the CMakePresets.json when running from a folder with a CMakePresets.json' {
        Mock FindCMakeRoot {
            Join-Path -Path $PSScriptRoot -ChildPath 'ReferenceBuild'
        }

        $ActualCMakePresetsJson = GetCMakePresets
        $ExpectedCMakePresetsJson = Get-Content (Join-Path -Path $PSScriptRoot -ChildPath 'ReferenceBuild/CMakePresets.json') |
            ConvertFrom-Json

        $ActualCMakePresetsJson |
            ConvertTo-Json -Depth 10 -Compress |
            Should -Be -ExpectedValue ($ExpectedCMakePresetsJson | ConvertTo-Json -Depth 10 -Compress)
    }

    It 'Reports an error when a CMakePresets.json is not found' {
        Mock FindCMakeRoot {
            $null
        }
        { GetCMakePresets } |
            Should -Throw
    }

    It 'Reports an error when a CMakePresets.json is not found, unless -Silent is passed' {
        Mock FindCMakeRoot {
            $null
        }
        GetCMakePresets -Silent |
            Should -BeNullOrEmpty
    }
}
