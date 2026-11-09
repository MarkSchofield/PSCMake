#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    $Properties = PrepareReferenceBuild 'windows-x64'
    & $CMake @Properties

    $Properties = PrepareReferenceBuild 'windows-x64[asan]'
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking
}

Describe 'Get-CMakeTarget' {
    It 'Returns all targets from the CMake root' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Targets = Get-CMakeTarget
            $Targets.Name | Should -Be @(
                'A_Library'
                'B_Library'
                'C_Library'
                'SubDirectoryOther_Executable'
                'SubDirectoryOther_Library'
                'SubDirectory_Executable'
                'SubDirectory_Library'
            )
            $Targets | ForEach-Object { $_.PSObject.TypeNames[0] | Should -Be 'PSCMake.Target' }
            $Targets.Preset | Select-Object -Unique | Should -Be 'windows-x64'
            $Targets.Configuration | Select-Object -Unique | Should -Be 'Debug'
        }
    }

    It 'Returns scoped targets from a subdirectory' {
        Using-Location "$PSScriptRoot/ReferenceBuild/SubDirectory" {
            (Get-CMakeTarget).Name | Should -Be @(
                'SubDirectory_Executable'
                'SubDirectory_Library'
            )
        }
    }

    It 'Returns target metadata' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Target = Get-CMakeTarget -Target SubDirectory_Executable
            $Target.Type | Should -Be 'EXECUTABLE'
            $Target.NameOnDisk | Should -Be 'SubDirectory_Executable.exe'
            $Target.OutputPath | Should -Be "$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Debug\SubDirectory_Executable.exe"
            $Target.Artifacts | Should -Contain $Target.OutputPath
            $Target.SourceDirectory | Should -Be "$PSScriptRoot\ReferenceBuild\SubDirectory"
            $Target.BuildDirectory | Should -Be "$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory"
            $Target.Json.name | Should -Be 'SubDirectory_Executable'
        }
    }

    It 'Supports wildcards for targets' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            (Get-CMakeTarget -Target '*_Executable').Name | Should -Be @(
                'SubDirectoryOther_Executable'
                'SubDirectory_Executable'
            )
        }
    }

    It 'Returns targets for the specified configuration' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Target = Get-CMakeTarget -Configuration Release -Target SubDirectory_Executable
            $Target.Configuration | Should -Be 'Release'
            $Target.OutputPath | Should -Be "$PSScriptRoot\ReferenceBuild\__output\windows-x64\SubDirectory\Release\SubDirectory_Executable.exe"
        }
    }

    It 'Supports wildcards for configurations' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Targets = Get-CMakeTarget -Configuration * -Target SubDirectory_Executable
            $Targets.Configuration | Should -Contain 'Debug'
            $Targets.Configuration | Should -Contain 'Release'
        }
    }

    It 'Returns targets for a preset with [ and ]' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Target = Get-CMakeTarget -Preset 'windows-x64[asan]' -Target SubDirectory_Executable
            $Target.Preset | Should -Be 'windows-x64[asan]'
            $Target.OutputPath | Should -Be "$PSScriptRoot\ReferenceBuild\__output\windows-x64[asan]\SubDirectory\Debug\SubDirectory_Executable.exe"
        }
    }

    It 'Fails for an unknown configuration' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            { Get-CMakeTarget -Configuration Bogus } | Should -Throw "Unable to find configuration 'Bogus' for preset 'windows-x64'."
        }
    }

    It 'Completes target names' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Completions = Get-CommandCompletion "Get-CMakeTarget -Target SubDirectory_"
            $Completions.CompletionMatches.CompletionText | Should -Be @(
                'SubDirectory_Executable'
                'SubDirectory_Library'
            )
        }
    }
}
