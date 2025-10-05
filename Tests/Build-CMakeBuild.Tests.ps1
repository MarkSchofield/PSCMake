#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    # Configure the reference build so that there is reference content to work with.
    $Properties = PrepareReferenceBuild
    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking

    # Mock subsequent calls to invoke CMake so that we don't actually try to build anything.
    $script:CMakeCalls = @()
    Mock -ModuleName PSCMake InvokeCMake {
        param(
            [string] $CMakePath,
            [string[]] $Arguments
        )
        $script:CMakeCalls += , $Arguments
    }
}

Describe 'Build-CMakeBuild' {
    BeforeEach {
        $script:CMakeCalls = @()
    }

    It 'Builds with no parameters' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild
        }

        $script:CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64')
    }

    It 'Builds with a single preset' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset windows-x64
        }

        $script:CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64')
    }

    It 'Builds a specified target' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset windows-x64 -Target B_Library
        }

        $script:CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'B_Library')
    }

    It 'Builds a multiple targets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset windows-x64 -Target A_Library,B_Library
        }

        $script:CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'A_Library', 'B_Library')
    }

    It 'Reruns configuration with -Configure' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset windows-x64 -Configure
        }

        $script:CMakeCalls | Should -HaveCount 2
        $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64')
        $script:CMakeCalls[1] | Should -Be @('--build', '--preset', 'windows-x64')
    }

    It 'Reruns configuration with -Fresh' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset windows-x64 -Fresh
        }

        $script:CMakeCalls | Should -HaveCount 2
        $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64', '--fresh')
        $script:CMakeCalls[1] | Should -Be @('--build', '--preset', 'windows-x64')
    }

    It 'Builds with wildcard presets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset '*-x64'
        }

        $CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64')
    }

    It 'Builds with wildcard configurations' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Build-CMakeBuild -Preset 'windows-x64' -Configuration *
        }

        $CMakeCalls | Should -HaveCount 3
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64', '--config', 'Debug')
        $script:CMakeCalls[1] | Should -Be @('--build', '--preset', 'windows-x64', '--config', 'Release')
        $script:CMakeCalls[2] | Should -Be @('--build', '--preset', 'windows-x64', '--config', 'RelWithDebInfo')
    }

    It 'Builds scoped targets' {
        Using-Location "$PSScriptRoot/ReferenceBuild/SubDirectory" {
            Build-CMakeBuild -Preset 'windows-x64'
        }

        $CMakeCalls | Should -HaveCount 1
        $script:CMakeCalls[0] | Should -Be @('--build', '--preset', 'windows-x64', '--target', 'SubDirectory_Executable', 'SubDirectory_Library')
    }
}
