#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1
}

Describe 'Invoke-ClangTidy' {
    BeforeAll {
        Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

        $script:ClangTidyCalls = @()

        Mock -ModuleName PSCMake InvokeExecutable {
            param([string] $Path, [string[]] $Arguments)
            $script:ClangTidyCalls += , @{ Path = $Path; Arguments = $Arguments }
        }

        Mock -ModuleName PSCMake GetClangTidy { return 'clang-tidy' }
    }

    BeforeEach {
        $script:ClangTidyCalls = @()
    }

    It 'Invokes clang-tidy once for a single source file' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:ClangTidyCalls | Should -HaveCount 1
        $script:ClangTidyCalls[0].Path | Should -Be 'clang-tidy'
    }

    It 'Passes -p pointing to a directory' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $Args = $script:ClangTidyCalls[0].Arguments
        $PIndex = [array]::IndexOf($Args, '-p')
        $PIndex | Should -Not -Be -1
        $Args[$PIndex + 1] | Should -Not -BeNullOrEmpty
    }

    It 'Includes the resolved source file path in the arguments' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $ExpectedPath = (Resolve-Path "$PSScriptRoot/ReferenceBuild/Reference.cpp").Path
        $script:ClangTidyCalls[0].Arguments | Should -Contain $ExpectedPath
    }

    It 'Formats -Checks as a single --checks= argument' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp -Checks 'modernize-*', 'bugprone-*'
        }
        $script:ClangTidyCalls[0].Arguments | Should -Contain '--checks=modernize-*,bugprone-*'
    }

    It 'Omits --checks when Checks is not specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $HasChecks = $script:ClangTidyCalls[0].Arguments | Where-Object { $_ -like '--checks=*' }
        $HasChecks | Should -BeNullOrEmpty
    }

    It 'Passes extra Arguments to clang-tidy' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-ClangTidy -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp -Arguments '--fix'
        }
        $script:ClangTidyCalls[0].Arguments | Should -Contain '--fix'
    }
}
