#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/../PSCMake/Common/CMake.ps1
. $PSScriptRoot/../PSCMake/Common/Ninja.ps1

# Get ninja.exe
function PrepareReferenceBuild() {
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
    $BuildPath = "$PSScriptRoot/ReferenceBuild".Replace('\', '/')
    $CMAKE_CXX_COMPILER = (Join-Path -Path $MSVCDirectory -ChildPath "bin/Hostx64/x64/cl.exe").Replace('\', '/')
    $CMAKE_MAKE_PROGRAM = $NinjaPath.Replace('\', '/')

    @(
        "--preset", "windows-x64",
        "-S", $BuildPath
        "-DCMAKE_CXX_COMPILER=$CMAKE_CXX_COMPILER"
        "-DCMAKE_MAKE_PROGRAM=$CMAKE_MAKE_PROGRAM"
    )
}
