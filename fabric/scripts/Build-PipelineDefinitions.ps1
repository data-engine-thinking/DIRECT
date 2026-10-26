#Requires -Version 7
<#
.SYNOPSIS
    Builds the Fabric pipeline definitions of the standard DIRECT pipelines.

.DESCRIPTION
    Reads the pipeline templates in fabric/templates, replaces every "{{sql:<file>}}" token with the
    JSON-encoded text of fabric/sql/<file>, and writes the result as pipeline-content.json into the
    matching fabric/items/<name>.DataPipeline folder (the Fabric Git integration item layout).

    Run this after changing a template or an activity script, and commit the generated files.

.NOTES
    File Name      : Build-PipelineDefinitions.ps1
    Prerequisite   : PowerShell 7
    License        : LGPL-3.0 (GNU Lesser General Public License v3.0)

.LINK
    https://github.com/data-engine-thinking/DIRECT
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fabricRoot = Split-Path -Path $PSScriptRoot -Parent
$templateFolder = Join-Path -Path $fabricRoot -ChildPath 'templates'
$sqlFolder = Join-Path -Path $fabricRoot -ChildPath 'sql'
$itemsFolder = Join-Path -Path $fabricRoot -ChildPath 'items'

function ConvertTo-JsonStringLiteral {
  param([Parameter(Mandatory)][string] $Text)
  # Same escaping as a minimal JSON encoder: backslash, double quote and the control characters that occur in text.
  $escaped = $Text.Replace('\', '\\').Replace('"', '\"').Replace("`r", '\r').Replace("`n", '\n').Replace("`t", '\t')
  return '"' + $escaped + '"'
}

Get-ChildItem -Path $templateFolder -Filter '*.template.json' | ForEach-Object {
  $template = $_
  $pipelineName = $template.Name -replace '\.template\.json$', ''
  $content = Get-Content -Path $template.FullName -Raw

  $tokens = [regex]::Matches($content, '"\{\{sql:([^}]+)\}\}"')
  foreach ($token in $tokens) {
    $sqlFile = Join-Path -Path $sqlFolder -ChildPath $token.Groups[1].Value
    if (-not (Test-Path -Path $sqlFile)) { throw "Activity script not found: $sqlFile" }
    $sqlText = (Get-Content -Path $sqlFile -Raw).Replace("`r`n", "`n").TrimEnd("`n")
    $content = $content.Replace($token.Value, (ConvertTo-JsonStringLiteral -Text $sqlText))
  }

  $itemFolder = Join-Path -Path $itemsFolder -ChildPath ($pipelineName + '.DataPipeline')
  if (-not (Test-Path -Path $itemFolder)) { New-Item -Path $itemFolder -ItemType Directory | Out-Null }
  $target = Join-Path -Path $itemFolder -ChildPath 'pipeline-content.json'
  [System.IO.File]::WriteAllText($target, $content.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
  Write-Host "Built $target"
}
