#Requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TypeAccelerators = [psobject].Assembly.GetType("System.Management.Automation.TypeAccelerators")
$TypeAccelerators::Add("xmlelement", [System.Xml.XmlElement])

function RemoveChildElements([xmlelement] $XmlElement) {
    $ChildNodes = $XmlElement.ChildNodes
    for ($Index = 0; $Index -lt $ChildNodes.Count; ) {
        $ChildXmlElement = $ChildNodes.Item($Index)
        if ($ChildXmlElement.NodeType -eq 'Element') {
            $XmlElement.RemoveChild($ChildXmlElement)
        } else {
            $Index++
        }
    }
}

function AddChildElements([xmlelement]$XmlElement, [array] $ChildElements) {
    $ChildElements |
        ForEach-Object {
            $null = $XmlElement.AppendChild($_)
        }
}

function SortChildElements([xmlelement] $LinksElement, [scriptblock] $SortExpression) {
    $LinkArray = RemoveChildElements $LinksElement
    $LinkArray = $LinkArray | Sort-Object $SortExpression
    AddChildElements $LinksElement $LinkArray
}
