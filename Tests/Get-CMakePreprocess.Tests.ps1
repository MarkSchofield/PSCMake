#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1
    . $PSScriptRoot/../PSCMake/Common/Includes.ps1

    $script:Props = GetReferenceBuildProperties
}

Describe 'Get-CMakePreprocess' {
    BeforeAll {
        Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

        $script:CompilerCalls = @()
        Mock -ModuleName PSCMake InvokeExecutable {
            param([string] $Path, [string[]] $Arguments)
            $script:CompilerCalls += , @{ Path = $Path; Arguments = $Arguments }
            @(
                '# 1 "Reference.cpp"'
                '#include <stdio.h>'
                'int main() { return 0; }'
            )
        }
    }

    BeforeEach {
        $script:CompilerCalls = @()
    }

    It 'Returns preprocessed output lines for a source file' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Result = Get-CMakePreprocess -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
            $Result | Should -HaveCount 3
        }
    }

    It 'Passes /E and /nologo to the MSVC compiler' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $null = Get-CMakePreprocess -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:CompilerCalls | Should -HaveCount 1
        $script:CompilerCalls[0].Arguments | Should -Contain '/E'
        $script:CompilerCalls[0].Arguments | Should -Contain '/nologo'
    }

    It 'Does not pass /c, /Zs, or /showIncludes to the MSVC compiler' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $null = Get-CMakePreprocess -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:CompilerCalls[0].Arguments | Should -Not -Contain '/c'
        $script:CompilerCalls[0].Arguments | Should -Not -Contain '/Zs'
        $script:CompilerCalls[0].Arguments | Should -Not -Contain '/showIncludes'
    }

    It 'Invokes the compiler path from the toolchain' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $null = Get-CMakePreprocess -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:CompilerCalls[0].Path | Should -Match 'cl\.exe$'
    }
}
