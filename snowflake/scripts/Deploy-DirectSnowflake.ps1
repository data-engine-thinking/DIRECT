#Requires -Version 7
<#
    Deploys the DIRECT Framework (Snowflake edition) into a database, with the Snowflake CLI.

    Usage:
      ./Deploy-DirectSnowflake.ps1 -Connection <name> -Database <name>

    <name> is a connection in the Snowflake CLI configuration (snow connection list). Its role must be
    allowed to create the database (or use it when it exists), schemas, tables, procedures and tasks,
    and it needs a default warehouse. For the serverless queue Tasks the role also needs EXECUTE TASK
    and EXECUTE MANAGED TASK on the account.

    The deployment can be run again: tables and their data are kept, procedures and views are replaced.
#>
param(
    [Parameter(Mandatory)][string]$Connection,
    [Parameter(Mandatory)][string]$Database
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'Direct_Snowflake.sql'
if (-not (Test-Path $script)) { throw "$script was not found. Run Build-DirectSnowflake.ps1 first." }

Write-Host "Deploying the DIRECT Framework into database $Database using connection '$Connection'..." -ForegroundColor Cyan
& snow sql -c $Connection -f $script -D "database=$Database" --enable-templating STANDARD
if ($LASTEXITCODE -ne 0) { throw 'The deployment failed. The first failing statement is reported above.' }

Write-Host "The DIRECT Framework is deployed in $Database (schemas OMD, OMD_METADATA, OMD_PROCESSING, OMD_REPORTING)." -ForegroundColor Green
