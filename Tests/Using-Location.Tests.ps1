#Requires -PSEdition Core

BeforeAll {
    . $PSScriptRoot/../PSCMake/Common/Common.ps1

    $OriginalLocation = Get-Location
    $TestFolder = Join-Path -Path $PSScriptRoot -ChildPath '__test'
    $null = New-Item -Path $TestFolder -ItemType Directory -Force -ErrorAction SilentlyContinue
}

AfterAll {
    Set-Location $OriginalLocation
}

Describe 'Using-Location' {
    It 'Navigates to the given location and back again afterwards.' {
        Set-Location $PSScriptRoot
        Using-Location $TestFolder {
            Get-Location |
                Should -Be $TestFolder
        }
        Get-Location |
            Should -Be $PSScriptRoot
    }
    It 'Restores the location when the scriptlet fails.' {
        Set-Location $PSScriptRoot
        {Using-Location $TestFolder { Write-Error "Oh no!" } } |
            Should -Throw
        Get-Location |
            Should -Be $PSScriptRoot
    }
}
