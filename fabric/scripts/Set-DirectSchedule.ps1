#Requires -Version 7
<#
.SYNOPSIS
    Creates, updates or disables the schedule of a standard DIRECT pipeline (the trickle feed).

.DESCRIPTION
    A Cron schedule runs the pipeline every N minutes under the identity of the signed-in user. The pipelines
    run with concurrency 1, so an overlapping run waits for the previous one to finish. The schedule carries
    no parameters; set the default value of the BatchCode parameter on the pipeline, or pass -BatchCode here
    to update that default.

.PARAMETER WorkspaceId
    The Fabric workspace id.
.PARAMETER TenantId
    Entra tenant of the Fabric account, when the signed-in Az account spans several tenants or the default context is not the licensed one.
.PARAMETER PipelineName
    'DIRECT Run Project' or 'DIRECT Run Batch'. Default 'DIRECT Run Project'.
.PARAMETER BatchCode
    When given, the default value of the pipeline's BatchCode parameter is set to this value first.
.PARAMETER IntervalMinutes
    Minutes between runs. Default 5.
.PARAMETER Disable
    Disables the existing schedule(s) instead of creating or enabling one.
.PARAMETER EndDateTime
    End of the schedule in UTC. Default one year from now.

.EXAMPLE
    ./Set-DirectSchedule.ps1 -WorkspaceId <ws> -BatchCode 'b_PROJECT' -IntervalMinutes 5
.EXAMPLE
    ./Set-DirectSchedule.ps1 -WorkspaceId <ws> -Disable

.NOTES
    File Name      : Set-DirectSchedule.ps1
    Prerequisite   : PowerShell 7, Az.Accounts, Connect-AzAccount with a licensed Fabric account
    License        : LGPL-3.0 (GNU Lesser General Public License v3.0)

.LINK
    https://github.com/data-engine-thinking/DIRECT
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string] $WorkspaceId,
  [string] $TenantId,
  [ValidateSet('DIRECT Run Project', 'DIRECT Run Batch')][string] $PipelineName = 'DIRECT Run Project',
  [string] $BatchCode,
  [ValidateRange(1, 1440)][int] $IntervalMinutes = 5,
  [switch] $Disable,
  [datetime] $EndDateTime = (Get-Date).ToUniversalTime().AddYears(1)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'FabricApi.ps1')

$token = Get-FabricAccessToken -TenantId $TenantId
$pipeline = Get-FabricItem -Token $token -WorkspaceId $WorkspaceId -DisplayName $PipelineName -Type 'DataPipeline'
if ($null -eq $pipeline) { throw "Pipeline '$PipelineName' was not found in workspace $WorkspaceId." }
$itemPath = "workspaces/$WorkspaceId/items/$($pipeline.id)"

if (-not [string]::IsNullOrWhiteSpace($BatchCode) -and -not $Disable) {
  # Set the default BatchCode of the pipeline, which is what a schedule run uses.
  $definition = Invoke-FabricApi -Token $token -Method POST -Path "$itemPath/getDefinition" -WaitForCompletion
  $part = $definition.definition.parts | Where-Object { $_.path -eq 'pipeline-content.json' } | Select-Object -First 1
  $content = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($part.payload)) | ConvertFrom-Json -Depth 50
  $content.properties.parameters.BatchCode.defaultValue = $BatchCode
  $parts = @((ConvertTo-FabricDefinitionPart -Path 'pipeline-content.json' -Content ($content | ConvertTo-Json -Depth 50)))
  if ($PSCmdlet.ShouldProcess($PipelineName, "Set default BatchCode to '$BatchCode'")) {
    $null = Invoke-FabricApi -Token $token -Method POST -Path "$itemPath/updateDefinition" -Body @{ definition = @{ parts = $parts } } -WaitForCompletion
    Write-Host "Default BatchCode of '$PipelineName' set to '$BatchCode'."
  }
}

$schedules = Invoke-FabricApi -Token $token -Method GET -Path "$itemPath/jobs/Pipeline/schedules"
$existing = @($schedules.value)

if ($Disable) {
  foreach ($schedule in $existing | Where-Object { $_.enabled }) {
    if ($PSCmdlet.ShouldProcess("$PipelineName schedule $($schedule.id)", 'Disable')) {
      $null = Invoke-FabricApi -Token $token -Method PATCH -Path "$itemPath/jobs/Pipeline/schedules/$($schedule.id)" -Body @{ enabled = $false; configuration = $schedule.configuration }
      Write-Host "Schedule $($schedule.id) disabled."
    }
  }
  return
}

$configuration = @{
  type            = 'Cron'
  startDateTime   = (Get-Date).ToUniversalTime().AddMinutes(1).ToString('yyyy-MM-ddTHH:mm:00')
  endDateTime     = $EndDateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:00')
  localTimeZoneId = 'UTC'
  interval        = $IntervalMinutes
}

$current = $existing | Select-Object -First 1
if ($null -ne $current) {
  if ($PSCmdlet.ShouldProcess("$PipelineName schedule $($current.id)", "Every $IntervalMinutes minutes")) {
    $null = Invoke-FabricApi -Token $token -Method PATCH -Path "$itemPath/jobs/Pipeline/schedules/$($current.id)" -Body @{ enabled = $true; configuration = $configuration }
    Write-Host "Schedule $($current.id) updated: every $IntervalMinutes minutes until $($configuration.endDateTime) UTC."
  }
}
else {
  if ($PSCmdlet.ShouldProcess($PipelineName, "Schedule every $IntervalMinutes minutes")) {
    $created = Invoke-FabricApi -Token $token -Method POST -Path "$itemPath/jobs/Pipeline/schedules" -Body @{ enabled = $true; configuration = $configuration }
    Write-Host "Schedule $($created.id) created: every $IntervalMinutes minutes until $($configuration.endDateTime) UTC."
  }
}
