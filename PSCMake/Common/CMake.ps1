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

. $PSScriptRoot/Common.ps1
. $PSScriptRoot/VisualStudio.ps1

$PEnv = Get-ChildItem env: | ToHashTable

$CMakeCandidates = @(
    (Get-Command 'cmake' -ErrorAction SilentlyContinue)
    if ($IsWindows) {
        (Join-Path -Path $env:ProgramFiles -ChildPath 'CMake/bin/cmake.exe')
    }
)

<#
    .Synopsis
    Finds the path of the CMakePresets file in the current or ancestral folder. This may be a 'CMakePresets.json' file
    or a 'CMakeUserPresets.json' file.
#>
function FindCMakePresets {
    $CurrentLocation = (Get-Location).Path
    GetPathOfFileAbove $CurrentLocation 'CMakeUserPresets.json', 'CMakePresets.json'
}

<#
    .Synopsis
    Finds the root of the CMake build - the current or ancestral folder containing CMake presets.
#>
function FindCMakeRoot {
    $CMakePresetsPath = FindCMakePresets
    [System.IO.Path]::GetDirectoryName($CMakePresetsPath)
}

$script:CMakePresetsPath = $null

<#
    .Synopsis
    Gets the path that the most recently loaded 'CMakePresets.json' or 'CMakeUserPresets.json' was loaded from.
#>
function GetCMakePresetsPath {
    $script:CMakePresetsPath
}

<#
    .Synopsis
    Loads the CMakePresets.json into a PowerShell representation.
#>
function GetCMakePresets {
    param(
        [switch] $Silent
    )
    $script:CMakePresetsPath = FindCMakePresets
    if (-not $script:CMakePresetsPath) {
        if ($Silent) {
            return $null
        }
        Write-Error "Can't find 'CMakePresets.json' or 'CMakeUserPresets.json' in the current or any parent folder."
    }

    $CMakeRoot = [System.IO.Path]::GetDirectoryName($CMakePresetsPath)
    $CMakePresetsJson = $null

    Write-Verbose "Presets = $CMakeRoot"

    # If files were included, load them now and merge them in. Keep track of files that were included to avoid cycles.
    $IncludedFiles = [System.Collections.Generic.HashSet[string]]::new()
    [array] $IncludePaths = @(
        $CMakePresetsPath
        if ([System.IO.Path]::GetFileName($CMakePresetsPath) -ieq 'CMakeUserPresets.json') {
            Join-Path -Path $CMakeRoot -ChildPath 'CMakePresets.json'
        }
    )

    for (; ; ) {
        $IncludePath, $IncludePaths = $IncludePaths
        if (-not $IncludePath) {
            break
        }

        Write-Verbose "Processing CMakePresets: $IncludePath"

        $IncludeJson = Get-Content $IncludePath | ConvertFrom-Json
        if (-not $CMakePresetsJson) {
            $CMakePresetsJson = $IncludeJson
        } else {
            $CMakePresetsJson.buildPresets += Get-MemberValue -InputObject $IncludeJson -Name 'buildPresets' -Or @()
            $CMakePresetsJson.configurePresets += Get-MemberValue -InputObject $IncludeJson -Name 'configurePresets' -Or @()
        }

        $NestedIncludePaths = Get-MemberValue -InputObject $IncludeJson -Name 'include' -Or @()
        $IncludeRoot = [System.IO.Path]::GetDirectoryName($IncludePath)
        foreach ($NestedIncludePath in $NestedIncludePaths) {
            # Macro substiution for include paths
            $NestedIncludePath = MacroReplacement $NestedIncludePath $null

            if (-not [System.IO.Path]::IsPathFullyQualified($NestedIncludePath)) {
                $NestedIncludePath = Join-Path -Path $IncludeRoot -ChildPath $NestedIncludePath
            }

            if (-not (Test-Path -Path $NestedIncludePath -PathType Leaf)) {
                Write-Error "Included CMake presets file '$NestedIncludePath' not found."
            }

            if ($IncludedFiles.Contains($NestedIncludePath)) {
                Write-Error "Cyclic include detected for included CMake presets file '$NestedIncludePath'."
            }

            $IncludedFiles.Add($NestedIncludePath) | Out-Null
            $IncludePaths = $NestedIncludePath
        }
    }

    $CMakePresetsJson
}

<#
    .Synopsis
    Gets 'buildPresets' in the specified CMakePresets.json object.
#>
function GetBuildPresets {
    param(
        $CMakePresetsJson
    )
    if ($CMakePresetsJson) {
        $Presets = $CMakePresetsJson.buildPresets

        # Filter presets that have '"hidden":true'
        $Presets = $Presets | Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) }

        # Filter presets that have (or their ancestors have) conditions that evaluate to $false
        $Presets = $Presets | Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.buildPresets }

        # Filter presets that have configure presets that have conditions that evaluate to $false
        $Presets = $Presets | Where-Object {
            $BuildPresetJson = $_
            $ConfigurePresetJson = $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $BuildPresetJson.configurePreset } | Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.configurePresets }

            $null -ne $ConfigurePresetJson
        }

        $Presets
    }
}

<#
    .Synopsis
    Gets the build presets matching the given name(s). If no name is given, returns the first available preset.
    Writes an error if a named preset cannot be found.
#>
function GetMatchingBuildPresets {
    param(
        $CMakePresetsJson,
        $Preset
    )
    $BuildPresets = GetBuildPresets $CMakePresetsJson
    if (-not $Preset) {
        if (-not $BuildPresets) {
            Write-Error "No Presets values specified, and one could not be inferred."
        }
        $BuildPresets | Select-Object -First 1
    } else {
        foreach ($CandidatePresetName in $Preset) {
            $MatchingPresets = $BuildPresets |
                Where-Object { ($_.name -like $CandidatePresetName) -or ($_.name -eq $CandidatePresetName) }
            if (-not $MatchingPresets) {
                Write-Error "Unable to find build preset '$CandidatePresetName' in $script:CMakePresetsPath"
            }
            $MatchingPresets
        }
    }
}

<#
    .Synopsis
    Gets the 'configurePresets' in the specified CMakePresets.json object.
#>
function GetConfigurePresets {
    param(
        $CMakePresetsJson
    )
    if ($CMakePresetsJson) {
        $Presets = $CMakePresetsJson.configurePresets

        # For each configurePreset identify if an external 'generator environment' can be identified.
        foreach ($Preset in $Presets) {
            $Architecture = Get-MemberValue $Preset 'architecture'
            $Toolset      = Get-MemberValue $Preset 'toolset'

            $ArchitectureStrategy = Get-MemberValue $Architecture 'strategy'
            $ToolsetStrategy      = Get-MemberValue $Toolset      'strategy'

            if (($ArchitectureStrategy -ne 'external') -and ($ToolsetStrategy -ne 'external')) {
                continue
            }

            $ArchitectureValue      = Get-MemberValue $Architecture 'value'
            $ArchitectureProperties = if ($ArchitectureValue) { ParseArchitectureValue $ArchitectureValue } else { @{} }

            $ToolsetValue      = Get-MemberValue $Toolset 'value'
            $ToolsetProperties = if ($ToolsetValue) { ParseArchitectureValue $ToolsetValue } else { @{} }

            $VSEnvironmentArgs = @{}
            $ArchPlatform = $ArchitectureProperties['platform']
            $ArchVersion  = $ArchitectureProperties['version']
            $ToolsetName  = $ToolsetProperties['platform']
            $ToolsetVer   = $ToolsetProperties['version']

            if ($ArchPlatform) { $VSEnvironmentArgs['Architecture']      = $ArchPlatform }
            if ($ArchVersion)  { $VSEnvironmentArgs['WindowsSdkVersion'] = $ArchVersion }
            if ($ToolsetName)  { $VSEnvironmentArgs['Toolset']           = $ToolsetName }
            if ($ToolsetVer)   { $VSEnvironmentArgs['ToolsetVersion']    = $ToolsetVer }

            $Preset | Add-Member -NotePropertyName 'generatorEnvironment' -NotePropertyValue (Get-VSEnvironment @VSEnvironmentArgs) -Force
        }

        # Filter presets that have '"hidden":true'
        $Presets = $Presets |
            Where-Object { -not (Get-MemberValue -InputObject $_ -Name 'hidden' -Or $false) }

        # Filter presets that have (or their ancestors have) conditions that evaluate to $false
        $Presets = $Presets |
            Where-Object { EvaluatePresetCondition $_ $CMakePresetsJson.configurePresets }

        $Presets
    }
}

<#
    .Synopsis
    Finds the 'CMake' command.
#>
function GetCMake {
    $CMake = Get-Variable -Name 'CMake' -ValueOnly -Scope script -ErrorAction SilentlyContinue
    if (-not $CMake) {
        foreach ($CMakeCandidate in $CMakeCandidates) {
            $CMake = Get-Command $CMakeCandidate -ErrorAction SilentlyContinue
            if ($CMake) {
                $script:CMake = $CMake
                break
            }
        }
        if (-not $CMake) {
            Write-Error "Unable to find CMake."
        }
    }
    $CMake
}

<#
    .Synopsis
    Returns the configure preset referenced by the given build preset's 'configurePreset' field.
#>
function GetConfigurePresetFor {
    param(
        $CMakePresetsJson,
        $Preset
    )
    $CMakePresetsJson.configurePresets | Where-Object { $_.name -eq $Preset.configurePreset }
}

<#
    .Synopsis
    Searches the specified preset and its ancestors, invoking the specified action for each preset.

    .Parameter Preset
    The preset to start searching from.

    .Parameter Presets
    The collection of presets to search for 'inherit' references.

    .Parameter Action
    A script block invoked for each preset in breadth-first order. Return $null to continue the walk; return
    any non-$null value to stop and return that value to the caller.

    .Description
    The action should return $null to continue searching, or a non-$null value to stop searching and return that value.

    When searching multiple preset 'inherit' values, the presets will be search in order.
#>
function SearchAncestors {
    param(
        $Preset,
        $Presets,
        [scriptblock] $Action
    )
    if ($null -eq $Preset) {
        return $null
    }
    [array] $PendingPresets = @($Preset)
    for (; ($null -ne $PendingPresets) -and ($PendingPresets.Count -gt 0); ) {
        $Preset, $PendingPresets = $PendingPresets
        $Result = & $Action $Preset
        if ($null -ne $Result) {
            return $Result
        }
        [array] $BasePresets = Get-MemberValue $Preset 'inherits' -Or @() |
            ForEach-Object {
                $BaseParentName = $_
                $Presets | Where-Object { $_.name -eq $BaseParentName } | Select-Object -First 1
            }
        $PendingPresets = $BasePresets + $PendingPresets
    }
}

<#
    .Synopsis
    Walks the preset inheritance chain to find the first ancestor that defines the given property, and returns its value.
#>
function ResolvePresetProperty {
    param(
        $Preset,
        $Presets,
        $PropertyName
    )
    SearchAncestors -Preset $Preset -Presets $Presets {
        param($CurrentPreset)
        Get-MemberValue -InputObject $CurrentPreset -Name $PropertyName
    }
}

<#
    .Synopsis
    Walks the preset inheritance chain to find the first ancestor that defines a 'condition' property, evaluates it, and returns the result. If no condition is found, returns $true.
#>
function EvaluatePresetCondition {
    param(
        $Preset,
        $Presets
    )
    $Scope = @{ Result = $null }
    SearchAncestors -Preset $Preset -Presets $Presets {
        param($CurrentPreset)
        $ConditionJson = Get-MemberValue $CurrentPreset 'condition'
        if ($ConditionJson) {
            if ($null -eq $Scope.Result) {
                $Scope.Result = EvaluateCondition $ConditionJson $CurrentPreset
            } else {
                Write-Verbose "Preset '$($Preset.name)': condition on '$($CurrentPreset.name)' ignored (not the first condition in the inheritance chain)."
            }
        }
    }
    if ($null -eq $Scope.Result) {
        return $true
    }
    $Scope.Result
}

<#
    .Synopsis
    Evaluates a single CMake preset condition JSON object against the given preset's macro context.
    Supports: equals, notEquals, inList, notInList, matches, notMatches, anyOf, allOf, not.
#>
function EvaluateCondition {
    param(
        $ConditionJson,
        $PresetJson
    )
    switch ($ConditionJson.type) {
        'equals' {
            return (MacroReplacement $ConditionJson.lhs $PresetJson) -eq (MacroReplacement $ConditionJson.rhs $PresetJson)
        }
        'notEquals' {
            return (MacroReplacement $ConditionJson.lhs $PresetJson) -ne (MacroReplacement $ConditionJson.rhs $PresetJson)
        }
        'const' {
            Write-Error "$_ is not yet implemented as a condition type."
            return
        }
        'inList' {
            $ExpandedString = MacroReplacement $ConditionJson.String $PresetJson
            foreach ($String in $ConditionJson.list) {
                if ($ExpandedString -eq (MacroReplacement $String $PresetJson)) {
                    return $true
                }
            }
            return $false
        }
        'notInList' {
            $ExpandedString = MacroReplacement $ConditionJson.String $PresetJson
            foreach ($String in $ConditionJson.list) {
                if ($ExpandedString -eq (MacroReplacement $String $PresetJson)) {
                    return $false
                }
            }
            return $true
        }
        'matches' {
            return (MacroReplacement $ConditionJson.string $PresetJson) -match $ConditionJson.matches
        }
        'notMatches' {
            return -not ((MacroReplacement $ConditionJson.string $PresetJson) -match $ConditionJson.matches)
        }
        'anyOf' {
            foreach ($NestedCondition in $ConditionJson.conditions) {
                if (EvaluateCondition $NestedCondition $PresetJson) {
                    return $true
                }
            }
            return $false
        }
        'allOf' {
            foreach ($NestedCondition in $ConditionJson.conditions) {
                if (-not (EvaluateCondition $NestedCondition $PresetJson)) {
                    return $false
                }
            }
            return $true
        }
        'not' {
            return -not (EvaluateCondition $ConditionJson.condition $PresetJson)
        }
    }
}

<#
    .Synopsis
    Resolves and returns the fully-qualified binary directory for the given configure preset, after performing
    CMake macro substitution on the preset's 'binaryDir' value.
#>
function GetBinaryDirectory {
    param(
        $CMakePresetsJson,
        $ConfigurePreset
    )
    $BinaryDirectory = ResolvePresetProperty -Preset $ConfigurePreset -Presets $CMakePresetsJson.configurePresets -PropertyName 'binaryDir'

    # Perform macro-replacement
    $Result = MacroReplacement $BinaryDirectory $ConfigurePreset

    # Canonicalize
    [System.IO.Path]::GetFullPath($Result)
}

<#
    .Synopsis
    Returns the table of fixed CMake macro values that do not depend on a specific preset (e.g. ${hostSystemName}).
#>
function GetMacroConstants {
    $HostSystemName = if ($IsWindows) {
        'Windows'
    } elseif ($IsMacOS) {
        'Darwin'
    } elseif ($IsLinux) {
        'Linux'
    } else {
        Write-Error "Unsupported `${hostSystemName} value."
    }

    @{
        '${hostSystemName}' = $HostSystemName
        '$vendor{PSCMake}'  = 'true'
    }
}

<#
    .Synopsis
    Performs CMake preset macro substitution on the given string, expanding tokens such as ${sourceDir},
    ${presetName}, ${hostSystemName}, $env{VAR}, $penv{VAR}, and $vendor{...}.
#>
function MacroReplacement {
    param(
        $Value,
        $PresetJson
    )
    $Result = for (; $Value; $Value = $Right) {
        $Left, $Match, $Right = $Value -split '(\$\w*\{\w+\})', 2
        $Left
        switch -regex ($Match) {
            '\$\{sourceDir\}' {
                Split-Path -Path (GetCMakePresetsPath)
                break
            }
            '\$\{sourceParentDir\}' {
                Split-Path -Path (Split-Path -Path (GetCMakePresetsPath))
                break
            }
            '\$\{sourceDirName\}' {
                Split-Path -Leaf -Path (Split-Path -Path (GetCMakePresetsPath))
                break
            }
            '\$\{presetName\}' {
                if ($PresetJson) {
                    $PresetJson.name
                }
                break
            }
            '\$\{generator\}' {
                Write-Error "$_ is not yet implemented as a macro replacement."
                break
            }
            '\$\{hostSystemName\}' {
                (GetMacroConstants).$_
                break
            }
            '\$\{fileDir\}' {
                Write-Error "$_ is not yet implemented as a macro replacement."
                break
            }
            '\$\{dollar\}' {
                '$'
                break
            }
            '\$env\{([^\}]*)\}' {
                $VarName = $Matches[1]
                $GenEnv = Get-MemberValue $PresetJson 'generatorEnvironment' -Or @{}
                $GenEnv[$VarName] ?? [System.Environment]::GetEnvironmentVariable($VarName)
            }
            '\$penv\{([^\}]*)\}' {
                $PEnv[$Matches[1]]
            }
            '\$vendor\{\w+\}' {
                Get-MemberValue (GetMacroConstants) $_ -Or $_
                break
            }
            Default {
                $Match
                break
            }
        }
    }
    $Result -join ''
}

<#
    .Synopsis
    Creates the CMake File API query files in the binary directory so that the next cmake configure writes
    code-model, cache, cmakeFiles, and toolchain reply JSON into '.cmake/api/v1/reply/'.
#>
function Enable-CMakeBuildQuery {
    [CmdletBinding()]
    param(
        [string] $BinaryDirectory,

        [ValidateSet('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')]
        [string[]] $ObjectKinds = @('codemodel-v2', 'cache-v2', 'cmakeFiles-v1', 'toolchains-v1')
    )
    $CMakeQueryApiDirectory = Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/query'
    $null = New-Item -ItemType Directory -Path $CMakeQueryApiDirectory -Force -ErrorAction SilentlyContinue
    $ObjectKinds |
        ForEach-Object {
            $QueryFile = Join-Path -Path $CMakeQueryApiDirectory -ChildPath $_
            $null = New-Item -Path $QueryFile -ItemType File -ErrorAction SilentlyContinue
        }
}

# For the 'code model' JSON that was found, load the full 'target' JSON to be able to find 'EXECUTABLE' targets.
#
function FilterExecutableTargets {
    param (
        $CodeModelDirectory,
        $TargetTuplesCodeModel
    )
    $TargetJsons = $TargetTuplesCodeModel |
        ForEach-Object {
            $JsonPath = Join-Path -Path $CodeModelDirectory -ChildPath $_.jsonFile
            Get-Item -LiteralPath $JsonPath |
                Get-Content |
                ConvertFrom-Json
            }

    $TargetJsons |
        Where-Object {
            $_.type -eq 'EXECUTABLE'
        }
}

<#
    .Synopsis
    Returns the path to the CMake File API reply directory ('.cmake/api/v1/reply') inside the binary directory.
#>
function Get-CMakeBuildCodeModelDirectory {
    param(
        [string] $BinaryDirectory
    )
    Join-Path -Path $BinaryDirectory -ChildPath '.cmake/api/v1/reply'
}

<#
    .Synopsis
    Gets PowerShell representation of the CodeModel JSON for the given binary directory.

    .Outputs
    The PowerShell representation of the CodeModel JSON for the given binary directory, or `$null` if it can't be found.
#>
function Get-CMakeBuildCodeModel {
    param(
        [string] $BinaryDirectory
    )

    # Since BinaryDirectory may contain characters that are valid for the file-system, but are used by PowerShell's
    # wildcard syntax (i.e. '[' and ']'), specify it as the LiteralPath to Get-ChildItem
    Get-ChildItem -LiteralPath (Get-CMakeBuildCodeModelDirectory $BinaryDirectory) -File -Filter 'codemodel-v2-*' -ErrorAction SilentlyContinue |
        Select-Object -First 1 |
        Get-Content |
        ConvertFrom-Json
}

<#
    .Synopsis
    Gets the target with the given name, for the given configuration from the specified code model.

    .Outputs
    The PowerShell representation of the target from the CodeModel JSON.
#>
function GetNamedTarget {
    param(
        $CodeModel,
        $Configuration,
        $Name
    )
    $CodeModelConfiguration = if ($Configuration) {
        $CodeModel.configurations | Where-Object { $_.name -eq $Configuration }
    } else {
        $CodeModel.configurations[0]
    }
    $CodeModelConfiguration.targets |
        Where-Object {
            $_.name -eq $Name
        }
}

<#
    .Synopsis
    Gets all targets within the given folder scope, for the given configuration from the specified code model.

    .Outputs
    The PowerShell representation of the target(s) from the CodeModel JSON.
#>
function GetScopedTargets {
    param(
        $CodeModel,
        $Configuration,
        $ScopeLocation
    )
    function CanonicalizeDirectoryPath($Path) {
        Resolve-Path -Path (Join-Path -Path $Path -ChildPath '/')
    }
    $ScopeLocation = CanonicalizeDirectoryPath $ScopeLocation
    $CodeModelConfiguration = if ($Configuration) {
        $CodeModel.configurations | Where-Object { $_.name -eq $Configuration }
    } else {
        $CodeModel.configurations[0]
    }
    $SourceDir = $CodeModel.paths.source
    $CodeModelConfiguration.targets |
        Where-Object {
            $Folder = $CodeModelConfiguration.directories[$_.directoryIndex].source
            $Folder = if ($Folder -eq '.') {
                $SourceDir
            } else {
                Join-Path -Path $SourceDir -ChildPath $Folder
            }
            $Folder = CanonicalizeDirectoryPath $Folder
            $Folder.Path.StartsWith($ScopeLocation.Path)
        }
}

<#
    .Synopsis
    Gets the value of a CMake cache entry.
#>
function GetCacheValue {
    param(
        [string] $BinaryDirectory,
        [string] $CacheEntryName
    )
    $CMakeCacheFile = Join-Path -Path $BinaryDirectory -ChildPath 'CMakeCache.txt'
    if (Test-Path -LiteralPath $CMakeCacheFile) {
        Get-Content -LiteralPath $CMakeCacheFile |
            Select-String "^$($CacheEntryName):.*=" |
            ForEach-Object {
                $_.ToString().Split('=', 2) | Select-Object -Last 1
        }
    }
}

<#
    .Synopsis
    Writes the CMake target dependency graph in Graphviz DOT format to the pipeline.
#>
function WriteDot {
    param (
        $Configuration,
        $CodeModel,
        $CodeModelDirectory
    )
    $Targets = @{}
    "digraph CodeModel {"
    ($CodeModel.configurations | Where-Object { $_.name -eq $Configuration }).targets |
        ForEach-Object {
            "  `"$($_.id)`" [label=`"$($_.name)`"]"
            $Targets[$_.id] = Get-Content (Join-Path -Path $CodeModelDirectory -ChildPath $_.jsonFile) | ConvertFrom-Json
        }
    $Targets.GetEnumerator() | ForEach-Object {
        $Source = $_.Name
        Get-MemberValue -InputObject $_.Value -Name dependencies -Or @() | ForEach-Object {
            "  `"$Source`" -> `"$($_.id)`" "
        }
    }
    "}"
}

<#
    .Synopsis
    Writes the CMake target dependency graph in Visual Studio DGML format to the pipeline.
#>
function WriteDgml {
    param (
        $Configuration,
        $CodeModel,
        $CodeModelDirectory
    )
    $Targets = @{}
    '<?xml version="1.0" encoding="utf-8"?>'
    '<DirectedGraph xmlns="http://schemas.microsoft.com/vs/2009/dgml">'
        '<Properties>'
            '<Property Id="Definition" Label="Definition" DataType="System.String" IsReference="True" />'
            '<Property Id="Type" DataType="System.String" />'
        '</Properties>'
        '<Styles>'
            '<Style TargetType="Node" GroupLabel="Executable" ValueLabel="Executable">'
                '<Condition Expression="Type=''EXECUTABLE''" />'
                '<Setter Property="Background" Value="#FF0000" />'
            '</Style>'
        '</Styles>'
        $SourcePath = $CodeModel.paths.source
        '<Nodes>'
            ($CodeModel.configurations | Where-Object { $_.name -eq $Configuration }).targets |
                ForEach-Object {
                    $TargetJson = Get-Content (Join-Path -Path $CodeModelDirectory -ChildPath $_.jsonFile) |
                        ConvertFrom-Json

                    $ReferenceFileIndex = $TargetJson.backtraceGraph.nodes[0].file
                    $Definition = Join-Path -Path $SourcePath -ChildPath $TargetJson.backtraceGraph.files[$ReferenceFileIndex]

                    '<Node'
                        "  Id=`"$($_.id)`""
                        "  Label=`"$($_.name)`""
                        "  Type=`"$($TargetJson.type)`""
                        "  Definition=`"$($Definition)`""
                        '/>'

                    Get-MemberValue -InputObject $TargetJson -Name artifacts -Or @() |
                        ForEach-Object {
                            '<Node'
                                "  Id=`"$($_.path)`""
                                '/>'
                        }

                    $Targets[$_.id] = $TargetJson
                }
        '</Nodes>'
        '<Links>'
            $Targets.GetEnumerator() |
                ForEach-Object {
                    $Source = $_.Name
                    Get-MemberValue -InputObject $_.Value -Name dependencies -Or @() |
                        ForEach-Object {
                        '<Link'
                            "  Source=`"$Source`""
                            "  Target=`"$($_.id)`""
                            '/>'
                    }

                    Get-MemberValue -InputObject $_.Value -Name artifacts -Or @() |
                        ForEach-Object {
                        '<Link'
                            "  Source=`"$Source`""
                            "  Target=`"$($_.path)`""
                            '/>'
                    }
                }
        '</Links>'
    '</DirectedGraph>'
}
