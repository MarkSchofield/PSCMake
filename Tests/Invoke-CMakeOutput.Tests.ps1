#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $Properties = PrepareReferenceBuild

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

    # Mock subsequent calls to invoke CMake so that we don't actually try to build anything.
    Mock -ModuleName PSCMake InvokeExecutable {
        param(
            [string] $Path,
            [string[]] $Arguments
        )
        $script:ExecutableCalls += [PSCustomObject]@{Path = $Path; Arguments = $Arguments}
    }
}

Describe 'Invoke-CMakeOutput' {
    BeforeEach {
        $script:ExecutableCalls = @()
    }

    It 'Builds then invokes a specified target' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-CMakeOutput -Target SubDirectory_Executable

            $script:ExecutableCalls | Should -HaveCount 2
            $script:ExecutableCalls[0].Arguments | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'SubDirectory_Executable')
            $script:ExecutableCalls[1].Arguments | Should -BeNullOrEmpty
            $script:ExecutableCalls[1].Path | Should -Be @("$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Debug\SubDirectory_Executable.exe")
        }
    }

    It 'Builds then invokes a specified target - configuration specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-CMakeOutput -Target SubDirectory_Executable -Configuration Release

            $script:ExecutableCalls | Should -HaveCount 2
            $script:ExecutableCalls[0].Arguments | Should -Be @('--build', '--preset', 'windows-x64', '--config', 'Release', '--target', 'SubDirectory_Executable')
            $script:ExecutableCalls[1].Arguments | Should -BeNullOrEmpty
            $script:ExecutableCalls[1].Path | Should -Be @("$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Release\SubDirectory_Executable.exe")
        }
    }

    It 'Passes extra parameters to the invocation' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Invoke-CMakeOutput -Target SubDirectory_Executable chunky bacon

            $script:ExecutableCalls | Should -HaveCount 2
            $script:ExecutableCalls[0].Arguments | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'SubDirectory_Executable')
            $script:ExecutableCalls[1].Arguments | Should -Be @('chunky', 'bacon')
            $script:ExecutableCalls[1].Path | Should -Be @("$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Debug\SubDirectory_Executable.exe")
        }
    }

    It 'Runs a single in-scope executable' {
        Using-Location "$PSScriptRoot/ReferenceBuild/SubDirectory" {
            Invoke-CMakeOutput

            $script:ExecutableCalls | Should -HaveCount 2
            $script:ExecutableCalls[0].Arguments | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'SubDirectory_Executable')
            $script:ExecutableCalls[1].Arguments | Should -BeNullOrEmpty
            $script:ExecutableCalls[1].Path | Should -Be @("$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Debug\SubDirectory_Executable.exe")
        }
    }

    It 'Fails with multiple executable targets in scope' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            { Invoke-CMakeOutput } | Should -Throw "Multiple executable scoped targets match. Specify a target explicitly: SubDirectoryOther_Executable SubDirectory_Executable"
        }
    }
}
