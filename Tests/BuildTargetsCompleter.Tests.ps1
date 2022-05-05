#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/../Common/CMake.ps1
    . $PSScriptRoot/../Common/Ninja.ps1

    # Get ninja.exe
    $NinjaCommand = Get-Command 'ninja.exe' -ErrorAction SilentlyContinue
    $NinjaPath = if ($NinjaCommand) {
        $NinjaCommand.Source
    } else {
        $BuildToolsPath = Join-Path -Path $PSScriptRoot -ChildPath 'ReferenceBuild/__tools'
        $Ninja = Download-Ninja (New-Item -Path $BuildToolsPath -ItemType Directory -Force).FullName
        $Ninja.FullName
    }

    # Find VS
    $VSWhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
    $InstallationPath = & $VSWhere -nologo -latest -property installationPath
    $MSVCDirectory = Get-ChildItem "$InstallationPath/VC/Tools/MSVC" |
        Sort-Object -Property Name -Descending |
        Select-Object -First 1

    # Write the CMake query files
    $BinaryDirectory = New-Item -Path "$PSScriptRoot/ReferenceBuild/__output/windows-x64" -ItemType Directory -Force

    Enable-CMakeBuildQuery $BinaryDirectory

    # Run CMake
    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    $BuildPath = "$PSScriptRoot/ReferenceBuild".Replace('\', '/')
    $CMAKE_CXX_COMPILER = (Join-Path -Path $MSVCDirectory -ChildPath "bin/Hostx64/x64/cl.exe").Replace('\', '/')
    $CMAKE_MAKE_PROGRAM = $NinjaPath.Replace('\', '/')
    & $CMake --preset windows-x64 `
        -S $BuildPath `
        "-DCMAKE_CXX_COMPILER=$CMAKE_CXX_COMPILER" `
        "-DCMAKE_MAKE_PROGRAM=$CMAKE_MAKE_PROGRAM"

    Import-Module -Force $PSScriptRoot/../PSCMake.psd1 -DisableNameChecking
}

Describe 'BuildTargetsCompleter' {
    It 'Returns the targets of the default preset, default configuration when neither is specified' {
        Using-Location "$PSScriptRoot/ReferenceBuild" {
            $Completions = Get-CommandCompletions "Build-CMakeBuild -Targets "

            $Completions.CompletionMatches.Count | Should -Be 3
            $Completions.CompletionMatches[0].CompletionText | Should -Be 'A_Library'
            $Completions.CompletionMatches[1].CompletionText | Should -Be 'B_Library'
            $Completions.CompletionMatches[2].CompletionText | Should -Be 'C_Library'
        }
    }
}
