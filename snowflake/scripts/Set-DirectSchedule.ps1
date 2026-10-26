#Requires -Version 7
<#
    Starts, stops or removes the queue (the Snowflake Task) of a Batch, with the Snowflake CLI.

    Usage:
      ./Set-DirectSchedule.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH -IntervalMinutes 15
      ./Set-DirectSchedule.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH -Warehouse MY_WH
      ./Set-DirectSchedule.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH -Stop
      ./Set-DirectSchedule.ps1 -Connection <name> -Database <name> -BatchCode b_MY_BATCH -Remove

    Without -Warehouse the Task is serverless (initial size from the setting QUEUE_WAREHOUSE_SIZE).
#>
param(
    [Parameter(Mandatory)][string]$Connection,
    [Parameter(Mandatory)][string]$Database,
    [Parameter(Mandatory)][string]$BatchCode,
    [int]$IntervalMinutes = 15,
    [string]$Warehouse,
    [switch]$Stop,
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'
$code = $BatchCode.Replace("'", "''")

$query = if ($Remove) { "CALL $Database.OMD.REMOVE_QUEUE('$code');" }
elseif ($Stop) { "CALL $Database.OMD.STOP_QUEUE('$code');" }
else {
    $wh = if ($Warehouse) { "'$Warehouse'" } else { 'NULL' }
    "CALL $Database.OMD.START_QUEUE('$code', $IntervalMinutes, $wh);"
}

& snow sql -c $Connection -q $query --enable-templating NONE
if ($LASTEXITCODE -ne 0) { throw 'The schedule could not be changed.' }
