#----------------------------------------------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2025 Mark Schofield
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#----------------------------------------------------------------------------------------------------------------------
#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
    .Synopsis
    Reads the toolchains-v1 File API reply for the given binary directory.
#>
function Get-CMakeBuildToolchain {
    param(
        [string] $BinaryDirectory
    )
    Get-ChildItem -LiteralPath (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -File -Filter 'toolchains-v1-*' -ErrorAction SilentlyContinue |
        Select-Object -First 1 |
        Get-Content |
        ConvertFrom-Json
}

<#
    .Synopsis
    Resolves the compiler path, ID, and base argument list for a given source file.

    .Description
    Looks up the compile group for $SourceFilePath in the code model, determines the compiler ID (preferring
    CMAKE_<LANG>_COMPILER_FRONTEND_VARIANT when present), and builds the fragment/include/define arguments.
    Returns a PSCustomObject with CompilerId, CompilerPath, CompilerArgs, and BuildDir, or $null if the source
    file was not found in any target.
#>
function GetCompilerInvocationForSource {
    param(
        $CodeModel,
        $Toolchains,
        [string] $BinaryDirectory,
        [string] $Configuration,
        [string] $SourceFilePath
    )
    $CompileInfo = GetCompileInfoForSource $CodeModel $BinaryDirectory $Configuration $SourceFilePath
    if (-not $CompileInfo) {
        return $null
    }

    $Toolchain = $Toolchains.toolchains | Where-Object { $_.language -eq $CompileInfo.Language } | Select-Object -First 1
    if (-not $Toolchain) {
        Write-Error "No toolchain found for language '$($CompileInfo.Language)'."
    }

    # Prefer CMAKE_<LANG>_COMPILER_FRONTEND_VARIANT when set; it reflects the actual flag syntax
    # (e.g. clang-cl reports 'MSVC' here even though the compiler id is 'Clang').
    $Language = $CompileInfo.Language
    $CompilerFrontendId = GetCacheValue $BinaryDirectory "CMAKE_$($Language)_COMPILER_FRONTEND_VARIANT"
    $CompilerId = if ($CompilerFrontendId) { $CompilerFrontendId } else { Get-MemberValue $Toolchain.compiler 'id' }

    if ($CompilerId -notin @('MSVC', 'Clang', 'AppleClang')) {
        Write-Error "Compiler '$CompilerId' is not supported by PSCMake. Supported compilers: MSVC, Clang, AppleClang."
    }

    $CompilerArgs = @()
    $CompilerArgs += $CompileInfo.Fragments |
        ForEach-Object { $_.fragment -split '\s+' } |
        Where-Object { $_ }
    $CompilerArgs += if ($CompilerId -eq 'MSVC') {
        $CompileInfo.Includes | ForEach-Object { "/I"; $_.path }
    } else {
        $CompileInfo.Includes | ForEach-Object { "-I"; $_.path }
    }
    $CompilerArgs += if ($CompilerId -eq 'MSVC') {
        $CompileInfo.Defines | ForEach-Object { "/D$($_.define)" }
    } else {
        $CompileInfo.Defines | ForEach-Object { "-D$($_.define)" }
    }

    [PSCustomObject]@{
        CompilerId   = $CompilerId
        CompilerPath = $Toolchain.compiler.path
        CompilerArgs = $CompilerArgs
        BuildDir     = $CompileInfo.BuildDir
    }
}

<#
    .Synopsis
    Searches all targets in the given code model configuration for the named source file and returns its compile
    group information.

    .Outputs
    A PSCustomObject with Language, Fragments, Includes, Defines, and BuildDir properties, or $null if not found.
#>
function GetCompileInfoForSource {
    param(
        $CodeModel,
        [string] $BinaryDirectory,
        [string] $Configuration,
        [string] $SourceFilePath
    )
    $ReplyDir = Get-CMakeBuildCodeModelDirectory $BinaryDirectory
    $SourceDir = $CodeModel.paths.source

    $CodeModelConfig = if ($Configuration) {
        $CodeModel.configurations | Where-Object { $_.name -eq $Configuration }
    } else {
        $CodeModel.configurations[0]
    }

    foreach ($TargetRef in $CodeModelConfig.targets) {
        $TargetJson = Get-Content (Join-Path -Path $ReplyDir -ChildPath $TargetRef.jsonFile) | ConvertFrom-Json
        foreach ($Source in (Get-MemberValue $TargetJson 'sources' -Or @())) {
            $CompileGroupIndex = Get-MemberValue $Source 'compileGroupIndex'
            if ($null -eq $CompileGroupIndex) {
                continue
            }

            $RawSourcePath = if ([System.IO.Path]::IsPathRooted($Source.path)) {
                $Source.path
            } else {
                Join-Path -Path $SourceDir -ChildPath $Source.path
            }
            $FullSourcePath = [System.IO.Path]::GetFullPath($RawSourcePath)

            if ($FullSourcePath -ieq $SourceFilePath) {
                $CompileGroup = $TargetJson.compileGroups[$CompileGroupIndex]
                $RawBuildDir = Join-Path -Path $CodeModel.paths.build -ChildPath $TargetJson.paths.build
                return [PSCustomObject]@{
                    Language  = $CompileGroup.language
                    Fragments = Get-MemberValue $CompileGroup 'compileCommandFragments' -Or @()
                    Includes  = Get-MemberValue $CompileGroup 'includes' -Or @()
                    Defines   = Get-MemberValue $CompileGroup 'defines' -Or @()
                    BuildDir  = [System.IO.Path]::GetFullPath($RawBuildDir)
                }
            }
        }
    }
    return $null
}

<#
    .Synopsis
    Builds a single compile_commands.json entry for the given compiler invocation and source file.
#>
function NewCompileCommandsEntryForSource {
    param(
        $Invocation,
        [string] $SourceFilePath
    )
    $Tokens = @($Invocation.CompilerPath) + $Invocation.CompilerArgs + @($SourceFilePath)
    $Command = ($Tokens | ForEach-Object {
        if ($_ -match '\s') { "`"$_`"" } else { $_ }
    }) -join ' '
    [PSCustomObject]@{
        directory = $Invocation.BuildDir
        command   = $Command
        file      = $SourceFilePath
    }
}

<#
    .Synopsis
    Parses MSVC /showIncludes output lines into a flat list of include nodes with Depth and Path properties.

    MSVC format: "Note: including file: <N spaces><path>"
    where N spaces = include depth (1 = directly included).
#>
function ParseMSVCIncludes {
    param(
        [string[]] $Output
    )
    foreach ($Line in $Output) {
        if ($Line -match '^Note: including file:( +)(.+)$') {
            [PSCustomObject]@{
                PSTypeName = 'PSCMake.IncludeNode'
                Depth = $Matches[1].Length
                Path  = $Matches[2].TrimEnd()
            }
        }
    }
}

<#
    .Synopsis
    Parses Clang -H output lines into a flat list of include nodes with Depth and Path properties.

    Clang format: "<N dots> <path>" where N dots = include depth (1 = directly included).
#>
function ParseClangIncludes {
    param(
        [string[]] $Output
    )
    foreach ($Line in $Output) {
        if ($Line -match '^(\.+) (.+)$') {
            [PSCustomObject]@{
                PSTypeName = 'PSCMake.IncludeNode'
                Depth = $Matches[1].Length
                Path  = $Matches[2].TrimEnd()
            }
        }
    }
}
