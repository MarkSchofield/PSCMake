#Requires -PSEdition Core

BeforeAll {
    $script:Presets = ConvertFrom-Json -InputObject @'
[
    { "name": "TrueBase",  "hidden": true, "condition": { "type": "equals", "lhs": "${hostSystemName}", "rhs": "Linux" } },
    { "name": "FalseBase", "hidden": true, "condition": { "type": "equals", "lhs": "${hostSystemName}", "rhs": "Windows" } },
    { "name": "InheritsTrueFirst",  "inherits": [ "TrueBase", "FalseBase" ] },
    { "name": "InheritsFalseFirst", "inherits": [ "FalseBase", "TrueBase" ] },
    { "name": "InheritsTrueOnly",   "inherits": "TrueBase" },
    { "name": "InheritsFalseOnly",  "inherits": "FalseBase" },
    { "name": "OwnTrue",  "condition": { "type": "equals", "lhs": "${hostSystemName}", "rhs": "Linux" } },
    { "name": "OwnFalse", "condition": { "type": "equals", "lhs": "${hostSystemName}", "rhs": "Windows" } },
    { "name": "NoCondition" }
]
'@

    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    Mock GetMacroConstants { @{
            '${hostSystemName}' = 'Linux'
        } }
}

Describe 'EvaluatePresetCondition' {
    It 'Returns $true for a preset with no condition and no inherits' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'NoCondition' } | Select-Object -First 1) $script:Presets |
            Should -Be $true
    }

    It 'Returns $true for a preset whose own condition evaluates to $true' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'OwnTrue' } | Select-Object -First 1) $script:Presets |
            Should -Be $true
    }

    It 'Returns $false for a preset whose own condition evaluates to $false' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'OwnFalse' } | Select-Object -First 1) $script:Presets |
            Should -Be $false
    }

    It 'Returns $true when the only inherited condition evaluates to $true' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'InheritsTrueOnly' } | Select-Object -First 1) $script:Presets |
            Should -Be $true
    }

    It 'Returns $false when the only inherited condition evaluates to $false' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'InheritsFalseOnly' } | Select-Object -First 1) $script:Presets |
            Should -Be $false
    }

    It 'Returns $true when the first inherited condition is $true even if a later inherited condition is $false' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'InheritsTrueFirst' } | Select-Object -First 1) $script:Presets |
            Should -Be $true
    }

    It 'Returns $false when the first inherited condition is $false even if a later inherited condition is $true' {
        EvaluatePresetCondition ($script:Presets | Where-Object { $_.name -eq 'InheritsFalseFirst' } | Select-Object -First 1) $script:Presets |
            Should -Be $false
    }
}
