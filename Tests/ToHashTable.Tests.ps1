#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/Common.ps1
}

Describe 'ToHashTable' {
    It 'Should return an empty hash table for an empty pipeline' {
        $HashTable = @() | ToHashTable
        $HashTable | Should -Not -Be $Null
        $HashTable.Count | Should -Be 0
    }

    It 'Should hash a named item' {
        $HashTable = @{Name = 'One'; Value = 1 } | ToHashTable
        $HashTable | Should -Not -Be $Null
        $HashTable.Count | Should -Be 1
        $HashTable['One'] | Should -Be 1
    }

    It 'Should hash multiple named items' {
        $HashTable = @(
            @{Name = 'One'; Value = 1 }
            @{Name = 'Two'; Value = 2 }
        ) | ToHashTable
        $HashTable | Should -Not -Be $Null
        $HashTable.Count | Should -Be 2
        $HashTable['One'] | Should -Be 1
        $HashTable['Two'] | Should -Be 2
    }

    It 'Should fail on unnamed items' {
        {
            @{SomeName = 'One'; Value = 1 } | ToHashTable
        } | Should -Throw
    }
}
