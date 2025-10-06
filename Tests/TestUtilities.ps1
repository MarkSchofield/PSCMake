#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CommandCompletion([string] $InputScript) {
    [System.Management.Automation.CommandCompletion]::CompleteInput($InputScript, $InputScript.Length, $null)
}

function Zip-Object {
    $Objects = $args

    if ($Objects.Count -lt 2) {
        throw "At least two collections must be specified"
    }

    $First = $Objects[0]
    $Objects | ForEach-Object {
        if ($_.Count -ne $First.Count) {
            throw "All collections must have the same number of elements"
        }
    }
    for ($i = 0; $i -lt $First.Count; $i++) {
        [array]$Current = @()
        $Objects | ForEach-Object {
            $Current += $_[$i]
        }
        (, $Current)
    }
}
