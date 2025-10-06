#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

BeforeAll {
    . $PSScriptRoot/TestUtilities.ps1
    . $PSScriptRoot/XmlUtilities.ps1
    . $PSScriptRoot/ReferenceBuild.ps1

    $Properties = PrepareReferenceBuild
    $script:BuildProperties = GetReferenceBuildProperties

    $CMake = "$env:ProgramFiles/CMake/bin/cmake.exe"
    & $CMake @Properties

    Import-Module -Force $PSScriptRoot/../PSCMake/PSCMake.psd1 -DisableNameChecking
}

Describe 'Write-CMakeBuild' {
    It 'Writes the build with no parameters' {
        Using-Location $BuildProperties.SourceDirectory {
            $ExpectedDotFile = @'
digraph CodeModel {
  "A_Library::@6890427a1f51a3e7e1df" [label="A_Library"]
  "B_Library::@6890427a1f51a3e7e1df" [label="B_Library"]
  "C_Library::@6890427a1f51a3e7e1df" [label="C_Library"]
  "SubDirectoryOther_Executable::@01210d55993b56455dd6" [label="SubDirectoryOther_Executable"]
  "SubDirectoryOther_Library::@01210d55993b56455dd6" [label="SubDirectoryOther_Library"]
  "SubDirectory_Executable::@c68b9f6dab07fa391196" [label="SubDirectory_Executable"]
  "SubDirectory_Library::@c68b9f6dab07fa391196" [label="SubDirectory_Library"]
}
'@
            ((Write-CMakeBuild) -join '') |
                Should -Be ($ExpectedDotFile -replace '\r\n', '')
        }
    }
    It 'Writes the DGML when specified' {
        Using-Location $BuildProperties.SourceDirectory {
            [xml]$ExpectedDgml = Get-Content "$PSScriptRoot/Write-CMakeBuild.dgml"
            SortChildElements $ExpectedDgml.DirectedGraph.Links { $_.Target }

            [xml]$ActualDgml = Write-CMakeBuild -As Dgml
            $ActualDgml.DirectedGraph.Nodes.Node |
                Where-Object { Get-MemberValue $_ Definition } |
                ForEach-Object { $_.Definition = $_.Definition.Replace($BuildProperties.SourceDirectory, "") }
            SortChildElements $ActualDgml.DirectedGraph.Links { $_.Target }

            $ActualDgml.OuterXml |
                Should -Be $ExpectedDgml.OuterXml
        }
    }
}
