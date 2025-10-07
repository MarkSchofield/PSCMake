#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $Properties = PrepareReferenceBuild

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    . $PSScriptRoot/../PSCMake/Common/CMake.ps1

    $ReferenceBuildProperties = GetReferenceBuildProperties
    $CodeModel = Get-CMakeBuildCodeModel $ReferenceBuildProperties.BinaryDirectory
    $script:SourceLocation = $CodeModel.paths.source
}

Describe 'GetScopedTargets' {
    It 'Returns all targets when the ScopeLocation is the SourceLocation' {
        $ScopeLocation = $SourceLocation
        $Targets = GetScopedTargets $CodeModel $null $ScopeLocation
        $Targets.name |
            Should -Be @(
                'A_Library'
                'B_Library'
                'C_Library'
                'SubDirectoryOther_Executable'
                'SubDirectoryOther_Library'
                'SubDirectory_Executable'
                'SubDirectory_Library'
            )
    }

    It 'Returns scoped targets when the ScopeLocation is a subdirectory of the SourceLocation' {
        $ScopeLocation = Join-Path -Path $SourceLocation -ChildPath 'SubDirectoryOther'
        $Targets = GetScopedTargets $CodeModel $null $ScopeLocation
        $Targets.name |
            Should -Be @(
                'SubDirectoryOther_Executable'
                'SubDirectoryOther_Library'
            )
    }

    It 'Returns scoped targets when the ScopeLocation is a subdirectory of the SourceLocation, that is also a prefix of another subdirectory' {
        $ScopeLocation = Join-Path -Path $SourceLocation -ChildPath 'SubDirectory'
        $Targets = GetScopedTargets $CodeModel $null $ScopeLocation
        $Targets.name |
            Should -Be @(
                'SubDirectory_Executable'
                'SubDirectory_Library'
            )
    }
}
