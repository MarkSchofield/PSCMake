#Requires -PSEdition Core

[CmdletBinding()]
param(
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WorkingDirectory = $PSScriptRoot
$RepositoryRoot = Resolve-Path -Path (& git -C $WorkingDirectory rev-parse '--show-toplevel')
$CurrentBranch = if ($env:GITHUB_HEAD_REF) {
    $env:GITHUB_HEAD_REF
} elseif ($env:GITHUB_REF) {
    ($env:GITHUB_REF -split '/',3,'SimpleMatch')[2]
} else {
    (& git -C $WorkingDirectory branch --show-current)
}
$VersionFile = Resolve-Path "$RepositoryRoot/Version"
$VersionEditHash = (& git -C $WorkingDirectory rev-list -1 HEAD $VersionFile)
$VersionCurrentHash = if ($env:GITHUB_HEAD_REF) {
    # If the script is running under as a GitHub Action during a Pull Request, then HEAD is the merge commit. The
    # version height should be calculated from the second merge parent.
    (& git -C $WorkingDirectory rev-list -n 1 'HEAD^2')
} else {
    (& git -C $WorkingDirectory rev-list -n 1 'HEAD')
}

[int] $VersionHeight = (& git -C $WorkingDirectory rev-list "$VersionEditHash..$VersionCurrentHash" --first-parent --count)
$VersionHeightPadded = '{0:D6}' -f $VersionHeight

$PrereleaseMetadata = switch -regex ($CurrentBranch) {
    '^(main|master)$'   { '' }
    '^(develop)$'       { '-beta' + $VersionHeightPadded }
    '^(release//)'      { '-release' + $VersionHeightPadded }
    '^(feature//)'      { '-alpha' + $VersionHeightPadded }
    default             { '-alpha' + $VersionHeightPadded }
}

[version] $BaseVersion = Get-Content $VersionFile

Write-Output @"
RepositoryRoot      = $RepositoryRoot
VersionEditHash     = $VersionEditHash
VersionCurrentHash  = $VersionCurrentHash
VersionHeight       = $VersionHeight
CurrentBranch       = $CurrentBranch
PrereleaseMetadata  = $PrereleaseMetadata
"@

Update-ModuleManifest -Path (Join-Path -Path $PSScriptRoot -ChildPath '../PSCMake/PSCMake.psd1') -ModuleVersion $BaseVersion -Prerelease $PrereleaseMetadata

$PSRepositoryName = Split-Path -Leaf $RepositoryRoot
$PSRepositoryPath = Join-Path -Path $RepositoryRoot -ChildPath '__packages'

$Null = Unregister-PSRepository -Name $PSRepositoryName -ErrorAction SilentlyContinue
$Null = New-Item -Path $PSRepositoryPath -ItemType Directory -Force
$Null = Remove-Item -Path "$PSRepositoryPath/PSCMake.$BaseVersion$PrereleaseMetadata.nupkg" -Force -ErrorAction SilentlyContinue
$Null = Register-PSRepository -Name $PSRepositoryName -SourceLocation $PSRepositoryPath -PublishLocation $PSRepositoryPath

$ModulePath = Resolve-Path "$RepositoryRoot/PSCMake"

Publish-Module -Repository $PSRepositoryName -Path $ModulePath -Force
