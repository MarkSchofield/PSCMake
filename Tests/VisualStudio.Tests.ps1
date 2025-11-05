#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/VisualStudio.ps1
}

Describe 'ParseArchitectureValue' {
    It 'Parses a bare platform name' {
        $Result = ParseArchitectureValue 'x64'
        $Result['platform'] | Should -Be 'x64'
        $Result.Keys | Should -HaveCount 1
    }

    It 'Parses a platform with a version key' {
        $Result = ParseArchitectureValue 'x64,version=10.0.26100.0'
        $Result['platform'] | Should -Be 'x64'
        $Result['version'] | Should -Be '10.0.26100.0'
    }

    It 'Parses a toolset name' {
        $Result = ParseArchitectureValue 'v143'
        $Result['platform'] | Should -Be 'v143'
        $Result.Keys | Should -HaveCount 1
    }

    It 'Parses a toolset name with a version key' {
        $Result = ParseArchitectureValue 'v143,version=14.40'
        $Result['platform'] | Should -Be 'v143'
        $Result['version'] | Should -Be '14.40'
    }

    It 'Parses multiple key=value pairs with no leading platform' {
        $Result = ParseArchitectureValue 'cuda=11.0,version=14.40'
        $Result['cuda'] | Should -Be '11.0'
        $Result['version'] | Should -Be '14.40'
        $Result.ContainsKey('platform') | Should -Be $false
    }
}
