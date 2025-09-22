#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/Common.ps1

    $script:TestObject = [PSCustomObject]@{
        Breakfast = 'Chunky Bacon'
    }
}

Describe 'Get-MemberValue' {
    It 'Returns the member value when available' {
        Get-MemberValue -InputObject $script:TestObject -Name Breakfast -Or Cereal |
            Should -Be 'Chunky Bacon'
    }

    It 'Returns null when the member value is not available' {
        Get-MemberValue -InputObject $script:TestObject -Name Lunch |
            Should -BeNullOrEmpty
    }

    It 'Returns the -Or value when the member value is not available' {
        Get-MemberValue -InputObject $script:TestObject -Name Lunch -Or Sandwich |
            Should -Be Sandwich
    }
}
