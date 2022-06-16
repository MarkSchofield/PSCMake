#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
        '${hostSystemName}'='Linux'
        '$vendor{PSCMake}'='true'
    } }
}

Describe 'EvaluateCondition' {
    It 'Can check host system name with "equals" against a string literal' {
        $PresetJson = @{}
        $MatchingCondition = @'
        {
            "type": "equals",
            "lhs": "${hostSystemName}",
            "rhs": "Linux"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $PresetJson | Should -Be $true

        $NonMatchingCondition = @'
        {
            "type": "equals",
            "lhs": "${hostSystemName}",
            "rhs": "Bacon"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $NonMatchingCondition $PresetJson | Should -Be $false
    }

    It 'Can check host system name with "notequals" against a string literal' {
        $PresetJson = @{}
        $MatchingCondition = @'
        {
            "type": "notequals",
            "lhs": "${hostSystemName}",
            "rhs": "Bacon"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $PresetJson | Should -Be $true

        $NonMatchingCondition = @'
        {
            "type": "notequals",
            "lhs": "${hostSystemName}",
            "rhs": "Linux"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $NonMatchingCondition $PresetJson | Should -Be $false
    }

    It 'Can evaluate "matches" conditions' {
        $MatchingCondition = @'
        {
            "type": "matches",
            "string": "${hostSystemName}",
            "matches": "(Linux|Bacon)"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $null | Should -Be $true

        $MatchingCondition = @'
        {
            "type": "matches",
            "string": "${hostSystemName}",
            "matches": "(Chunky|Bacon)"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $null | Should -Be $false
    }

    It 'Can evaluate "notmatches" conditions' {
        $MatchingCondition = @'
        {
            "type": "notmatches",
            "string": "${hostSystemName}",
            "matches": "(Chunky|Bacon)"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $null | Should -Be $true

        $MatchingCondition = @'
        {
            "type": "notmatches",
            "string": "${hostSystemName}",
            "matches": "(Linux|Bacon)"
        }
'@ | ConvertFrom-Json

        EvaluateCondition $MatchingCondition $null | Should -Be $false
    }

    It 'Can evaluate "not" conditions' {
        $PresetJson = @{}
        $NotCondition = @'
        {
            "type":"not",
            "condition":
            {
                "type": "equals",
                "lhs": "${hostSystemName}",
                "rhs": "Linux"
            }
        }
'@ | ConvertFrom-Json

        EvaluateCondition $NotCondition $PresetJson | Should -Be $false
    }
}
