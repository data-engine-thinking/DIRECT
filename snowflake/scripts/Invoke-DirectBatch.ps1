#Requires -Version 7
<#
    Runs a Batch once, with the Snowflake CLI, and shows the result.

    Usage:
      ./Invoke-DirectBatch.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH
      ./Invoke-DirectBatch.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH -EndValue '2024-01-31 00:00:00'

    -EndValue sets the end of the load window of every Module in the Batch (default: the time of the run).
    The command fails when a Module failed and the setting THROW_ON_FAILURE is Y.
#>
param(
    [Parameter(Mandatory)][string]$Connection,
    [Parameter(Mandatory)][string]$Database,
    [Parameter(Mandatory)][string]$BatchCode,
    [string]$EndValue,
    [string]$ExecutionContext = 'Invoke-DirectBatch.ps1'
)

$ErrorActionPreference = 'Stop'
$end = if ($EndValue) { "'$($EndValue.Replace("'", "''"))'" } else { 'NULL' }
$query = "CALL $Database.OMD.RUN_BATCH('$($BatchCode.Replace("'", "''"))', 0, '$($ExecutionContext.Replace("'", "''"))', $end);"

& snow sql -c $Connection -q $query --enable-templating NONE
if ($LASTEXITCODE -ne 0) { throw "Batch $BatchCode ended with failures. See $Database.OMD_REPORTING.VW_EXECUTION_EVENT_LOG." }
