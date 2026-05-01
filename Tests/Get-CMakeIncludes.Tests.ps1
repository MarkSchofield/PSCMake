#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1
    . $PSScriptRoot/../PSCMake/Common/Includes.ps1

    $script:Props = GetReferenceBuildProperties
}

Describe 'ParseMSVCIncludes' {
    It 'Parses a single depth-1 include' {
        $Result = ParseMSVCIncludes @('Note: including file: C:\Windows\include\windows.h')
        $Result | Should -HaveCount 1
        $Result[0].Depth | Should -Be 1
        $Result[0].Path | Should -Be 'C:\Windows\include\windows.h'
    }

    It 'Parses nested includes at increasing depths' {
        $Output = @(
            'Note: including file: C:\include\a.h'
            'Note: including file:  C:\include\b.h'
            'Note: including file:   C:\include\c.h'
            'Note: including file:  C:\include\d.h'
        )
        $Result = ParseMSVCIncludes $Output
        $Result | Should -HaveCount 4
        $Result[0].Depth | Should -Be 1
        $Result[1].Depth | Should -Be 2
        $Result[2].Depth | Should -Be 3
        $Result[3].Depth | Should -Be 2
    }

    It 'Ignores non-include lines' {
        $Output = @(
            'Reference.cpp'
            'Note: including file: C:\include\a.h'
            'cl: warning D9025: ...'
        )
        $Result = ParseMSVCIncludes $Output
        $Result | Should -HaveCount 1
        $Result[0].Path | Should -Be 'C:\include\a.h'
    }

    It 'Returns nothing for empty output' {
        $Result = ParseMSVCIncludes @()
        $Result | Should -BeNullOrEmpty
    }

    It 'Returns nothing when no include lines are present' {
        $Result = ParseMSVCIncludes @('Reference.cpp', 'Build succeeded.')
        $Result | Should -BeNullOrEmpty
    }
}

Describe 'ParseClangIncludes' {
    It 'Parses a single depth-1 include' {
        $Result = ParseClangIncludes @('. /usr/include/stdio.h')
        $Result | Should -HaveCount 1
        $Result[0].Depth | Should -Be 1
        $Result[0].Path | Should -Be '/usr/include/stdio.h'
    }

    It 'Parses nested includes at increasing depths' {
        $Output = @(
            '. /usr/include/a.h'
            '.. /usr/include/b.h'
            '... /usr/include/c.h'
            '.. /usr/include/d.h'
        )
        $Result = ParseClangIncludes $Output
        $Result | Should -HaveCount 4
        $Result[0].Depth | Should -Be 1
        $Result[1].Depth | Should -Be 2
        $Result[2].Depth | Should -Be 3
        $Result[3].Depth | Should -Be 2
    }

    It 'Ignores non-include lines' {
        $Output = @(
            'In file included from /path/to/file.cpp:1:'
            '. /usr/include/a.h'
            'clang: warning: unused variable'
        )
        $Result = ParseClangIncludes $Output
        $Result | Should -HaveCount 1
        $Result[0].Path | Should -Be '/usr/include/a.h'
    }

    It 'Returns nothing for empty output' {
        $Result = ParseClangIncludes @()
        $Result | Should -BeNullOrEmpty
    }
}

Describe 'Get-CMakeBuildToolchains' {
    It 'Returns toolchain data from the reference build' {
        $Toolchains = Get-CMakeBuildToolchains $script:Props.BinaryDirectory
        $Toolchains | Should -Not -BeNullOrEmpty
        $Toolchains.toolchains | Should -Not -BeNullOrEmpty
    }

    It 'Exposes a CXX toolchain with MSVC compiler' {
        $Toolchains = Get-CMakeBuildToolchains $script:Props.BinaryDirectory
        $CxxToolchain = $Toolchains.toolchains | Where-Object { $_.language -eq 'CXX' }
        $CxxToolchain | Should -Not -BeNullOrEmpty
        $CxxToolchain.compiler.id | Should -Be 'MSVC'
        $CxxToolchain.compiler.path | Should -Not -BeNullOrEmpty
    }
}

Describe 'GetCompileInfoForSource' {
    It 'Returns compile info for a source file present in a target' {
        $SourcePath = Join-Path -Path $script:Props.SourceDirectory -ChildPath 'Reference.cpp'
        $Result = GetCompileInfoForSource $script:Props.CodeModelFile $script:Props.BinaryDirectory $null $SourcePath
        $Result | Should -Not -BeNullOrEmpty
        $Result.Language | Should -Be 'CXX'
        $Result.Fragments | Should -Not -BeNullOrEmpty
        $Result.BuildDir | Should -Not -BeNullOrEmpty
    }

    It 'Returns null for a source file not in any target' {
        $SourcePath = Join-Path -Path $script:Props.SourceDirectory -ChildPath 'DoesNotExist.cpp'
        $Result = GetCompileInfoForSource $script:Props.CodeModelFile $script:Props.BinaryDirectory $null $SourcePath
        $Result | Should -BeNullOrEmpty
    }

    It 'Resolves the build directory to an absolute path' {
        $SourcePath = Join-Path -Path $script:Props.SourceDirectory -ChildPath 'Reference.cpp'
        $Result = GetCompileInfoForSource $script:Props.CodeModelFile $script:Props.BinaryDirectory $null $SourcePath
        [System.IO.Path]::IsPathRooted($Result.BuildDir) | Should -BeTrue
    }
}

Describe 'Get-CMakeIncludes' {
    BeforeAll {
        Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

        $script:CompilerCalls = @()
        Mock -ModuleName PSCMake InvokeExecutable {
            param([string] $Path, [string[]] $Arguments)
            $script:CompilerCalls += , @{ Path = $Path; Arguments = $Arguments }
            @(
                'Reference.cpp'
                'Note: including file: C:\Windows\Kits\10\include\10.0.26100.0\ucrt\stdio.h'
                'Note: including file:  C:\Windows\Kits\10\include\10.0.26100.0\ucrt\corecrt.h'
            )
        }
    }

    BeforeEach {
        $script:CompilerCalls = @()
    }

    It 'Returns include nodes for a source file' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Result = Get-CMakeIncludes -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
            $Result | Should -HaveCount 2
            $Result[0].Depth | Should -Be 1
            $Result[1].Depth | Should -Be 2
        }
    }

    It 'Returns nodes typed as PSCMake.IncludeNode' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Result = Get-CMakeIncludes -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
            $Result[0].PSObject.TypeNames | Should -Contain 'PSCMake.IncludeNode'
        }
    }

    It 'Passes /showIncludes and /nologo to the MSVC compiler' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $null = Get-CMakeIncludes -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:CompilerCalls | Should -HaveCount 1
        $script:CompilerCalls[0].Arguments | Should -Contain '/showIncludes'
        $script:CompilerCalls[0].Arguments | Should -Contain '/nologo'
        $script:CompilerCalls[0].Arguments | Should -Contain '/c'
    }

    It 'Invokes the compiler path from the toolchain' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $null = Get-CMakeIncludes -Preset windows-x64 -Configuration Debug -SourceFile Reference.cpp
        }
        $script:CompilerCalls[0].Path | Should -Match 'cl\.exe$'
    }
}
