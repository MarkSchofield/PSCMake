#Requires -PSEdition Core

BeforeAll {
    $script:Presets = ConvertFrom-Json -InputObject @"
[
    {
        "name": "Preset1"
    },
    {
        "name": "Preset2",
        "inherits": "Preset1"
    },
    {
        "name": "Preset3"
    },
    {
        "name": "Preset4",
        "inherits": ["Preset2", "Preset3"]
    }
]
"@
    $script:Preset1 = $script:Presets | Where-Object { $_.name -eq 'Preset1' } | Select-Object -First 1
    $script:Preset2 = $script:Presets | Where-Object { $_.name -eq 'Preset2' } | Select-Object -First 1
    $script:Preset3 = $script:Presets | Where-Object { $_.name -eq 'Preset3' } | Select-Object -First 1
    $script:Preset4 = $script:Presets | Where-Object { $_.name -eq 'Preset4' } | Select-Object -First 1

    . $PSScriptRoot/../PSCMake/Common/CMake.ps1
}

Describe 'SearchAncestors' {
    It 'Returns $null when passed a $null preset' {
        SearchAncestors $null $Presets { } |
            Should -Be $null
    }

    It 'Searches a single preset' {
        $script:VisitedPresets = @()
        SearchAncestors $Preset1 $Presets {
            param($CurrentPreset)
            $script:VisitedPresets += $CurrentPreset.name
        } |
            Should -Be $null

        $script:VisitedPresets |
            Should -Be @('Preset1')
    }

    It 'Searches a preset and its parent' {
        $script:VisitedPresets = @()
        SearchAncestors $Preset2 $Presets {
            param($CurrentPreset)
            $script:VisitedPresets += $CurrentPreset.name
        } |
            Should -Be $null

        $script:VisitedPresets |
            Should -Be @('Preset2', 'Preset1')
    }

    It 'Returns the result of a found preset' {
        $Name = SearchAncestors $Preset2 $Presets {
            param($CurrentPreset)
            $CurrentPreset.name
        }
        $Name | Should -Be 'Preset2'
    }

    It 'Stops searching when a result is found' {
        $script:VisitedPresets = @()
        $Name = SearchAncestors $Preset2 $Presets {
            param($CurrentPreset)
            $script:VisitedPresets += $CurrentPreset.name
            $CurrentPreset.name
        }
        $Name | Should -Be 'Preset2'
        $script:VisitedPresets |
            Should -Be @('Preset2')
    }

    It 'Searches a preset and its multiple parents' {
        $script:VisitedPresets = @()
        SearchAncestors $Preset4 $Presets {
            param($CurrentPreset)
            $script:VisitedPresets += $CurrentPreset.name
        } |
            Should -Be $null

        $script:VisitedPresets |
            Should -Be @('Preset4', 'Preset2', 'Preset1', 'Preset3')
    }
}
