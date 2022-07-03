#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CommandCompletions([string] $InputScript) {
    [System.Management.Automation.CommandCompletion]::CompleteInput($InputScript, $InputScript.Length, $null)
}
