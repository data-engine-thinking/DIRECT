#Requires -Version 7
<#
.SYNOPSIS
    Helper functions for the Microsoft Fabric REST API, shared by the DIRECT Fabric scripts.

.DESCRIPTION
    Dot-source this file. It provides a token from the signed-in Azure context (Az.Accounts), a request
    wrapper that follows long-running operations, and lookups for workspace items and connections.

.NOTES
    File Name      : FabricApi.ps1
    Prerequisite   : PowerShell 7, Az.Accounts (Connect-AzAccount with an account that has access to the workspace)
    License        : LGPL-3.0 (GNU Lesser General Public License v3.0)

.LINK
    https://github.com/data-engine-thinking/DIRECT
#>

Set-StrictMode -Version Latest

$script:FabricApiBaseUri = 'https://api.fabric.microsoft.com/v1'

function Get-FabricAccessToken {
  <#
  .SYNOPSIS
      Returns a bearer token for the Fabric REST API from the current Az context.
  .PARAMETER TenantId
      Entra tenant to get the token for, when the signed-in account has several (the default context may be
      an account without a Fabric license, which Fabric rejects with UserNotLicensed).
  #>
  [CmdletBinding()]
  param([string] $TenantId)
  if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw 'The Az.Accounts module is required (Install-Module Az.Accounts) and you must be signed in with Connect-AzAccount.'
  }
  Import-Module Az.Accounts -ErrorAction Stop
  $tokenArguments = @{ ResourceUrl = 'https://api.fabric.microsoft.com'; ErrorAction = 'Stop' }
  if (-not [string]::IsNullOrWhiteSpace($TenantId)) { $tokenArguments.TenantId = $TenantId }
  $tokenResult = Get-AzAccessToken @tokenArguments
  $token = $tokenResult.Token
  if ($token -is [System.Security.SecureString]) { $token = ConvertFrom-SecureString -SecureString $token -AsPlainText }
  return $token
}

function Invoke-FabricApi {
  <#
  .SYNOPSIS
      Calls the Fabric REST API and follows a long-running operation to its result.
  .PARAMETER Path
      Path relative to https://api.fabric.microsoft.com/v1, for example 'workspaces/<id>/items'.
  .PARAMETER Body
      Object that is serialized to JSON (depth 20) as the request body.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Token,
    [Parameter(Mandatory)][ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string] $Method,
    [Parameter(Mandatory)][string] $Path,
    [object] $Body,
    [switch] $WaitForCompletion
  )
  $uri = if ($Path -like 'https://*') { $Path } else { "$script:FabricApiBaseUri/$Path" }
  $headers = @{ Authorization = "Bearer $Token" }
  $arguments = @{ Uri = $uri; Method = $Method; Headers = $headers; ContentType = 'application/json'; SkipHttpErrorCheck = $true }
  if ($null -ne $Body) { $arguments.Body = ($Body | ConvertTo-Json -Depth 20 -Compress) }

  $response = Invoke-WebRequest @arguments
  $status = [int] $response.StatusCode

  if ($status -eq 202 -and $WaitForCompletion) {
    $location = [string] $response.Headers['Location']
    $retryAfter = 2
    if ($response.Headers['Retry-After']) { $retryAfter = [int] ([string] $response.Headers['Retry-After']) }
    while ($true) {
      Start-Sleep -Seconds ([Math]::Max(1, $retryAfter))
      $poll = Invoke-WebRequest -Uri $location -Method GET -Headers $headers -SkipHttpErrorCheck
      $operation = $null
      if ($poll.Content) { $operation = $poll.Content | ConvertFrom-Json }
      if ($null -ne $operation -and $operation.PSObject.Properties['status']) {
        if ($operation.status -eq 'Succeeded') {
          $resultUri = "$location/result"
          $result = Invoke-WebRequest -Uri $resultUri -Method GET -Headers $headers -SkipHttpErrorCheck
          if ([int] $result.StatusCode -ge 200 -and [int] $result.StatusCode -lt 300 -and $result.Content) { return ($result.Content | ConvertFrom-Json) }
          return $operation
        }
        if ($operation.status -eq 'Failed') { throw "Fabric operation failed: $($poll.Content)" }
      }
      elseif ([int] $poll.StatusCode -ge 200 -and [int] $poll.StatusCode -lt 300) {
        # Job instance polling returns the job itself
        if ($null -ne $operation -and $operation.PSObject.Properties['status'] -and $operation.status -in @('Completed', 'Failed', 'Cancelled', 'Deduped')) { return $operation }
        if ($null -eq $operation) { return $null }
      }
      else { throw "Fabric operation polling failed with HTTP $([int] $poll.StatusCode): $($poll.Content)" }
    }
  }

  if ($status -ge 200 -and $status -lt 300) {
    if ($response.Content) { return ($response.Content | ConvertFrom-Json) }
    return [pscustomobject]@{ StatusCode = $status; Headers = $response.Headers }
  }
  throw "Fabric API $Method $uri failed with HTTP ${status}: $($response.Content)"
}

function Get-FabricItem {
  <#
  .SYNOPSIS
      Finds an item in a workspace by display name and type; returns $null when it does not exist.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Token,
    [Parameter(Mandatory)][string] $WorkspaceId,
    [Parameter(Mandatory)][string] $DisplayName,
    [Parameter(Mandatory)][string] $Type
  )
  $result = Invoke-FabricApi -Token $Token -Method GET -Path "workspaces/$WorkspaceId/items?type=$Type"
  return $result.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
}

function Get-FabricConnection {
  <#
  .SYNOPSIS
      Finds a connection by display name; returns $null when it does not exist.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Token,
    [Parameter(Mandatory)][string] $DisplayName
  )
  $path = 'connections'
  while ($path) {
    $page = Invoke-FabricApi -Token $Token -Method GET -Path $path
    $match = $page.value | Where-Object { $_.displayName -eq $DisplayName } | Select-Object -First 1
    if ($match) { return $match }
    $path = if ($page.PSObject.Properties['continuationUri'] -and $page.continuationUri) { $page.continuationUri } else { $null }
  }
  return $null
}

function ConvertTo-FabricDefinitionPart {
  <#
  .SYNOPSIS
      Returns an inline base64 definition part for an item definition.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Path,
    [Parameter(Mandatory)][string] $Content
  )
  return @{
    path        = $Path
    payload     = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
    payloadType = 'InlineBase64'
  }
}

function Set-FabricItemDefinition {
  <#
  .SYNOPSIS
      Creates an item with a definition, or updates the definition of the existing item with the same name.
  .OUTPUTS
      The item id.
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string] $Token,
    [Parameter(Mandatory)][string] $WorkspaceId,
    [Parameter(Mandatory)][string] $DisplayName,
    [Parameter(Mandatory)][string] $Type,
    [string] $Description,
    [Parameter(Mandatory)][object[]] $Parts
  )
  $existing = Get-FabricItem -Token $Token -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Type $Type
  if ($null -eq $existing) {
    $body = @{ displayName = $DisplayName; type = $Type; definition = @{ parts = $Parts } }
    if ($Description) { $body.description = $Description }
    $created = Invoke-FabricApi -Token $Token -Method POST -Path "workspaces/$WorkspaceId/items" -Body $body -WaitForCompletion
    if ($null -ne $created -and $created.PSObject.Properties['id']) { return $created.id }
    $existing = Get-FabricItem -Token $Token -WorkspaceId $WorkspaceId -DisplayName $DisplayName -Type $Type
    return $existing.id
  }
  $null = Invoke-FabricApi -Token $Token -Method POST -Path "workspaces/$WorkspaceId/items/$($existing.id)/updateDefinition" -Body @{ definition = @{ parts = $Parts } } -WaitForCompletion
  return $existing.id
}
