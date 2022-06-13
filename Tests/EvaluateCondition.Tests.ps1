#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
        '${hostSystemName}'='Linux'
        '$vendor{PSCMake}'='true'
    } }
}

Describe 'EvaluateCondition' {
    It 'Can check host system name for equality with a string literal' {
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
