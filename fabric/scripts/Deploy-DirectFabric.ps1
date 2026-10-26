#Requires -Version 7
<#
.SYNOPSIS
    Deploys the standard DIRECT pipelines and their Variable Library to a Microsoft Fabric workspace.

.DESCRIPTION
    For a workspace that holds a DIRECT repository (a SQL database in Fabric with the DIRECT dacpac deployed)
    and a Fabric Warehouse with the data and the Module executables, this script:

    1. Creates (or reuses) a Fabric SQL database connection and a Warehouse connection for the signed-in
       user (OAuth2, caller identity), unless connection ids are given.
    2. Creates or updates the Variable Library 'DIRECT' with the workspace, item, connection and load window
       settings. Pipelines bind to it by name.
    3. Creates or updates the pipelines 'DIRECT Run Batch' and 'DIRECT Run Module'
       from fabric/items/*.DataPipeline/pipeline-content.json (run Build-PipelineDefinitions.ps1 first after
       changing templates or scripts).

    Workspaces connected to Git can take the fabric/items folder as their Git folder instead and only need
    the Variable Library values set for the workspace.

.PARAMETER WorkspaceId
    The Fabric workspace id.
.PARAMETER TenantId
    Entra tenant of the Fabric account, when the signed-in Az account spans several tenants or the default context is not the licensed one.
.PARAMETER RepositoryDatabaseItemId
    Item id of the SQL database in Fabric that holds the DIRECT repository.
.PARAMETER WarehouseItemId
    Item id of the Fabric Warehouse with the data and executables.
.PARAMETER WarehouseEndpoint
    SQL endpoint of the Warehouse. Looked up from the Warehouse item when omitted.
.PARAMETER RepositoryConnectionId
    Id of an existing Fabric SQL database connection. Created (or reused by name) when omitted.
.PARAMETER WarehouseConnectionId
    Id of an existing Warehouse connection. Created (or reused by name) when omitted.
.PARAMETER ConsistencyModuleTypeList
    Comma-separated Module Types that receive a consistency timestamp. Empty for none.
.PARAMETER LoadWindowAttributeName
    Attribute whose maximum in the source data object ends the load window. Default INSCRIPTION_TIMESTAMP.
.PARAMETER SourceTimestampColumn
    Timestamp column for omd.GetConsistencyTimestamp. Default LOAD_DATETIME.
.PARAMETER ModuleInstanceIdColumnName
    Module Instance Id column in the target data objects. Default MODULE_INSTANCE_ID.
.PARAMETER DefaultStartValue
    Load window start for Modules without a recorded load window. Default 1900-01-01.

.EXAMPLE
    ./Deploy-DirectFabric.ps1 -WorkspaceId <ws> -RepositoryDatabaseItemId <db> -WarehouseItemId <wh> -ConsistencyModuleTypeList 'PIT'

.NOTES
    File Name      : Deploy-DirectFabric.ps1
    Prerequisite   : PowerShell 7, Az.Accounts, Connect-AzAccount with a licensed Fabric account
    License        : LGPL-3.0 (GNU Lesser General Public License v3.0)

.LINK
    https://github.com/data-engine-thinking/DIRECT
#>
[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter(Mandatory)][string] $WorkspaceId,
  [string] $TenantId,
  [Parameter(Mandatory)][string] $RepositoryDatabaseItemId,
  [Parameter(Mandatory)][string] $WarehouseItemId,
  [string] $WarehouseEndpoint,
  [string] $RepositoryConnectionId,
  [string] $WarehouseConnectionId,
  [string] $ConsistencyModuleTypeList = '',
  [string] $LoadWindowAttributeName = 'INSCRIPTION_TIMESTAMP',
  [string] $SourceTimestampColumn = 'LOAD_DATETIME',
  [string] $ModuleInstanceIdColumnName = 'MODULE_INSTANCE_ID',
  [string] $DefaultStartValue = '1900-01-01'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path -Path $PSScriptRoot -ChildPath 'FabricApi.ps1')

$fabricRoot = Split-Path -Path $PSScriptRoot -Parent
$itemsFolder = Join-Path -Path $fabricRoot -ChildPath 'items'
$libraryName = 'DIRECT'
$pipelineNames = @('DIRECT Run Batch', 'DIRECT Run Module')

$token = Get-FabricAccessToken -TenantId $TenantId

# 1. Warehouse endpoint
if ([string]::IsNullOrWhiteSpace($WarehouseEndpoint)) {
  $warehouse = Invoke-FabricApi -Token $token -Method GET -Path "workspaces/$WorkspaceId/warehouses/$WarehouseItemId"
  $WarehouseEndpoint = $warehouse.properties.connectionString
  Write-Host "Warehouse endpoint: $WarehouseEndpoint"
}

# 2. Connections (OAuth2 with the caller's identity; a workspace identity is refused for the Fabric SQL database endpoint)
function New-OrGetConnection {
  param([string] $DisplayName, [string] $DetailType, [string] $CreationMethod)
  $existing = Get-FabricConnection -Token $token -DisplayName $DisplayName
  if ($existing) { Write-Host "Connection '$DisplayName' exists: $($existing.id)"; return $existing.id }
  if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create connection')) { return $null }
  $body = @{
    connectivityType  = 'ShareableCloud'
    displayName       = $DisplayName
    privacyLevel      = 'Organizational'
    connectionDetails = @{ type = $DetailType; creationMethod = $CreationMethod; parameters = @() }
    credentialDetails = @{
      singleSignOnType     = 'None'
      connectionEncryption = 'Encrypted'
      skipTestConnection   = $false
      credentials          = @{ credentialType = 'OAuth2'; useCallerIdentity = $true }
    }
  }
  $created = Invoke-FabricApi -Token $token -Method POST -Path 'connections' -Body $body
  Write-Host "Connection '$DisplayName' created: $($created.id)"
  return $created.id
}

if ([string]::IsNullOrWhiteSpace($RepositoryConnectionId)) {
  $RepositoryConnectionId = New-OrGetConnection -DisplayName "DIRECT repository ($WorkspaceId)" -DetailType 'FabricSql' -CreationMethod 'FabricSql.Contents'
}
if ([string]::IsNullOrWhiteSpace($WarehouseConnectionId)) {
  $WarehouseConnectionId = New-OrGetConnection -DisplayName "DIRECT warehouse ($WorkspaceId)" -DetailType 'Warehouse' -CreationMethod 'Fabric.Warehouse'
}

# 3. Variable Library
$libraryFolder = Join-Path -Path $itemsFolder -ChildPath "$libraryName.VariableLibrary"
$variables = Get-Content -Path (Join-Path -Path $libraryFolder -ChildPath 'variables.json') -Raw | ConvertFrom-Json
$values = @{
  WorkspaceId                = $WorkspaceId
  RepositoryDatabaseItemId   = $RepositoryDatabaseItemId
  RepositoryConnectionId     = $RepositoryConnectionId
  WarehouseItemId            = $WarehouseItemId
  WarehouseEndpoint          = $WarehouseEndpoint
  WarehouseConnectionId      = $WarehouseConnectionId
  ModuleInstanceIdColumnName = $ModuleInstanceIdColumnName
  DefaultStartValue          = $DefaultStartValue
  ConsistencyModuleTypeList  = $ConsistencyModuleTypeList
  SourceTimestampColumn      = $SourceTimestampColumn
  LoadWindowAttributeName    = $LoadWindowAttributeName
}
foreach ($variable in $variables.variables) {
  if ($values.ContainsKey($variable.name)) { $variable.value = [string] $values[$variable.name] }
}
$settings = Get-Content -Path (Join-Path -Path $libraryFolder -ChildPath 'settings.json') -Raw
$libraryParts = @(
  (ConvertTo-FabricDefinitionPart -Path 'variables.json' -Content ($variables | ConvertTo-Json -Depth 10)),
  (ConvertTo-FabricDefinitionPart -Path 'settings.json' -Content $settings)
)
if ($PSCmdlet.ShouldProcess($libraryName, 'Create or update Variable Library')) {
  $libraryId = Set-FabricItemDefinition -Token $token -WorkspaceId $WorkspaceId -DisplayName $libraryName -Type 'VariableLibrary' -Description 'Settings of the standard DIRECT pipelines for this workspace.' -Parts $libraryParts
  Write-Host "Variable Library '$libraryName': $libraryId"
}

# 4. Pipelines
foreach ($pipelineName in $pipelineNames) {
  $definitionFile = Join-Path -Path $itemsFolder -ChildPath "$pipelineName.DataPipeline/pipeline-content.json"
  if (-not (Test-Path -Path $definitionFile)) { throw "Pipeline definition not found: $definitionFile (run Build-PipelineDefinitions.ps1)" }
  $content = Get-Content -Path $definitionFile -Raw
  # Fabric limits an item description to 256 characters
  $description = [string] ($content | ConvertFrom-Json).properties.description
  if ($description.Length -gt 256) { $description = $description.Substring(0, 256) }
  $parts = @((ConvertTo-FabricDefinitionPart -Path 'pipeline-content.json' -Content $content))
  if ($PSCmdlet.ShouldProcess($pipelineName, 'Create or update pipeline')) {
    $pipelineId = Set-FabricItemDefinition -Token $token -WorkspaceId $WorkspaceId -DisplayName $pipelineName -Type 'DataPipeline' -Description $description -Parts $parts
    Write-Host "Pipeline '$pipelineName': $pipelineId"
  }
}

Write-Host 'Done. Run a Batch with Invoke-DirectPipeline.ps1 and schedule the trickle feed with Set-DirectSchedule.ps1.'
