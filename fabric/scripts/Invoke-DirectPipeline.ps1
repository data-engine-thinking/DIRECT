#Requires -Version 7
<#
.SYNOPSIS
    Runs one of the standard DIRECT pipelines on demand and waits for the result.

.DESCRIPTION
    Starts a pipeline job (POST .../jobs/instances?jobType=Pipeline) with the given parameters and polls the
    job instance until it completes. Returns the job instance; exits with a non-zero code on failure.

.PARAMETER WorkspaceId
    The Fabric workspace id.
.PARAMETER TenantId
    Entra tenant of the Fabric account, when the signed-in Az account spans several tenants or the default context is not the licensed one.
.PARAMETER PipelineName
    'DIRECT Run Batch' or 'DIRECT Run Module'.
.PARAMETER BatchCode
    The Batch Code for Run Batch (the Batch runs with all its child Batches).
.PARAMETER ModuleCode
    The Module Code for Run Module.
.PARAMETER TimeoutMinutes
    How long to wait for the run. Default 120.

.EXAMPLE
    ./Invoke-DirectPipeline.ps1 -WorkspaceId <ws> -PipelineName 'DIRECT Run Batch' -BatchCode 'b_MAIN'

.NOTES
    File Name      : Invoke-DirectPipeline.ps1
    Prerequisite   : PowerShell 7, Az.Accounts, Connect-AzAccount with a licensed Fabric account
    License        : LGPL-3.0 (GNU Lesser General Public License v3.0)

.LINK
    https://github.com/data-engine-thinking/DIRECT
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $WorkspaceId,
  [string] $TenantId,
  [Parameter(Mandatory)][ValidateSet('DIRECT Run Batch', 'DIRECT Run Module')][string] $PipelineName,
  [string] $BatchCode,
  [string] $ModuleCode,
  [int] $TimeoutMinutes = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'FabricApi.ps1')

$token = Get-FabricAccessToken -TenantId $TenantId
$pipeline = Get-FabricItem -Token $token -WorkspaceId $WorkspaceId -DisplayName $PipelineName -Type 'DataPipeline'
if ($null -eq $pipeline) { throw "Pipeline '$PipelineName' was not found in workspace $WorkspaceId. Deploy it with Deploy-DirectFabric.ps1." }

$parameters = @{}
if ($PipelineName -eq 'DIRECT Run Module') {
  if ([string]::IsNullOrWhiteSpace($ModuleCode)) { throw 'ModuleCode is required for DIRECT Run Module.' }
  $parameters.ModuleCode = $ModuleCode
}
else {
  if ([string]::IsNullOrWhiteSpace($BatchCode)) { throw "BatchCode is required for $PipelineName." }
  $parameters.BatchCode = $BatchCode
}

$headers = @{ Authorization = "Bearer $token" }
$startUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/items/$($pipeline.id)/jobs/instances?jobType=Pipeline"
$body = @{ executionData = @{ parameters = $parameters } } | ConvertTo-Json -Depth 10 -Compress
$response = Invoke-WebRequest -Uri $startUri -Method POST -Headers $headers -ContentType 'application/json' -Body $body -SkipHttpErrorCheck
if ([int] $response.StatusCode -ne 202) { throw "Could not start '$PipelineName' (HTTP $([int] $response.StatusCode)): $($response.Content)" }
$location = [string] $response.Headers['Location']
Write-Host "Started '$PipelineName' with parameters $($parameters | ConvertTo-Json -Compress)."

$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Seconds 10
  $job = Invoke-RestMethod -Uri $location -Method GET -Headers $headers
  if ($job.status -in @('Completed', 'Failed', 'Cancelled', 'Deduped')) {
    Write-Host "Run $($job.id) ended with status $($job.status) (started $($job.startTimeUtc), ended $($job.endTimeUtc))."
    if ($job.status -ne 'Completed') {
      if ($job.PSObject.Properties['failureReason'] -and $job.failureReason) { Write-Host ($job.failureReason | ConvertTo-Json -Depth 5) }
      $global:LASTEXITCODE = 1
    }
    return $job
  }
  Write-Host "Status: $($job.status)"
}
throw "The run did not complete within $TimeoutMinutes minutes."
