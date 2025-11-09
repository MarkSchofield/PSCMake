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
            [string] $CMakePath,
            [string[]] $Arguments
        )
        $null = $CMakePath
        $script:CMakeCalls += , $Arguments
    }
}

Describe 'Configure-CMakeBuild' {
    BeforeEach {
        $script:CMakeCalls = @()
    }

    It 'Configures the build with no parameters' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild

            $script:CMakeCalls | Should -HaveCount 1
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64')
        }
    }

    It 'Configures with --fresh when specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild -Fresh

            $script:CMakeCalls | Should -HaveCount 1
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64', '--fresh')
        }
    }

    It 'Configures with --verbose when specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild -Fresh -Verbose

            $script:CMakeCalls | Should -HaveCount 1
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64', '--fresh', '--log-level=VERBOSE')
        }
    }

    It 'Configures with a specific preset' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild -Preset windows-arm

            $script:CMakeCalls | Should -HaveCount 1
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-arm')
        }
    }

    It 'Configures with a multiple presets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild -Preset windows-arm,windows-x64

            $script:CMakeCalls | Should -HaveCount 2
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-arm')
            $script:CMakeCalls[1] | Should -Be @('--preset', 'windows-x64')
        }
    }

    It 'Configures with a wildcard presets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            Configure-CMakeBuild -Preset windows-*

            $script:CMakeCalls | Should -HaveCount 3
            $script:CMakeCalls[0] | Should -Be @('--preset', 'windows-x64')
            $script:CMakeCalls[1] | Should -Be @('--preset', 'windows-x64[asan]')
            $script:CMakeCalls[2] | Should -Be @('--preset', 'windows-arm')
        }
    }

    It 'Reports invalid presets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            { Configure-CMakeBuild -Preset linux-x64 } |
                Should -Throw "Unable to find configuration preset 'linux-x64' in $PSScriptRoot\ReferenceBuild\CMakePresets.json"
        }
    }
}
