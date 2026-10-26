#Requires -Version 7
<#
    Runs the regression tests of the DIRECT Framework (Snowflake edition) with the Snowflake CLI.

    The runner creates the test database from scratch (it is DROPPED first when it exists), deploys
    Direct_Snowflake.sql into it, runs tests/00_Setup.sql and then every tests/test-*.sql file in
    name order. Each test writes its outcome (Pass, Fail or Skip) to OMD_TEST.TEST_RESULT; the runner
    prints the table and exits with code 1 when a test failed or produced no result. The database is
    dropped at the end unless -KeepDatabase is given.

    Usage:
      ./Run-DirectSnowflakeTests.ps1 -Connection <name>
      ./Run-DirectSnowflakeTests.ps1 -Connection <name> -Database DIRECT_TEST -Warehouse COMPUTE_WH -KeepDatabase
      ./Run-DirectSnowflakeTests.ps1 -Connection <name> -Test test-019

    <name> is a connection in the Snowflake CLI configuration (snow connection list) with a default
    warehouse and a role that may create and drop the test database. -Warehouse makes the queue test
    (test-023) create a warehouse Task instead of a serverless one, for roles without EXECUTE MANAGED
    TASK; the queue test is skipped when the role cannot create or resume a Task. -Test runs only the
    tests whose file name starts with the given text.
#>
param(
    [Parameter(Mandatory)][string]$Connection,
    [string]$Database = 'DIRECT_TEST',
    [string]$Warehouse = '',
    [string]$Test = '',
    [switch]$KeepDatabase
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root 'Direct_Snowflake.sql'
$testFolder = Join-Path $root 'tests'
if (-not (Test-Path $script)) { throw "$script was not found. Run Build-DirectSnowflake.ps1 first." }
if ($Database -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { throw "The database name '$Database' must be a plain identifier." }
$warehouseValue = if ($Warehouse) { $Warehouse } else { 'NONE' }

function Invoke-SqlFile([string]$File) {
    & snow sql -c $Connection -f $File -D "database=$Database" -D "warehouse=$warehouseValue" --enable-templating STANDARD
    return $LASTEXITCODE
}

$started = Get-Date
Write-Host "Creating test database $Database using connection '$Connection'..." -ForegroundColor Cyan
& snow sql -c $Connection -q "DROP DATABASE IF EXISTS $Database; CREATE DATABASE $Database;"
if ($LASTEXITCODE -ne 0) { throw "The test database $Database could not be created." }

Write-Host 'Deploying the DIRECT Framework...' -ForegroundColor Cyan
if ((Invoke-SqlFile $script) -ne 0) { throw 'The deployment failed. The first failing statement is reported above.' }

Write-Host 'Preparing the test schema...' -ForegroundColor Cyan
if ((Invoke-SqlFile (Join-Path $testFolder '00_Setup.sql')) -ne 0) { throw 'The test setup failed.' }

$tests = Get-ChildItem $testFolder -Filter 'test-*.sql' | Sort-Object Name
if ($Test) { $tests = $tests | Where-Object { $_.BaseName -like "$Test*" } }
if ($tests.Count -eq 0) { throw 'No test files were found.' }

$cliFailures = @{}
foreach ($file in $tests) {
    Write-Host "Running $($file.BaseName)..." -ForegroundColor Cyan
    if ((Invoke-SqlFile $file.FullName) -ne 0) {
        $cliFailures[$file.BaseName] = 'The script did not complete; the Snowflake CLI reported an error (see above).'
    }
}

Write-Host 'Collecting the results...' -ForegroundColor Cyan
$json = & snow sql -c $Connection -q "SELECT TEST_NAME, RESULT, OUTPUT FROM $Database.OMD_TEST.TEST_RESULT ORDER BY TEST_NAME" --format JSON
if ($LASTEXITCODE -ne 0) { throw 'The test results could not be read.' }
$rows = @(($json -join "`n") | ConvertFrom-Json)

$results = foreach ($file in $tests) {
    $row = $rows | Where-Object { $_.TEST_NAME -eq $file.BaseName } | Select-Object -Last 1
    if ($row) {
        [pscustomobject]@{ Test = $file.BaseName; Result = $row.RESULT; Output = $row.OUTPUT }
    }
    elseif ($cliFailures.ContainsKey($file.BaseName)) {
        [pscustomobject]@{ Test = $file.BaseName; Result = 'Fail'; Output = $cliFailures[$file.BaseName] }
    }
    else {
        [pscustomobject]@{ Test = $file.BaseName; Result = 'Fail'; Output = 'The test wrote no result.' }
    }
}

$results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
$passed = @($results | Where-Object Result -eq 'Pass').Count
$skipped = @($results | Where-Object Result -eq 'Skip').Count
$failed = @($results | Where-Object { $_.Result -ne 'Pass' -and $_.Result -ne 'Skip' }).Count
$elapsed = (Get-Date) - $started

if (-not $KeepDatabase) {
    Write-Host "Dropping test database $Database..." -ForegroundColor Cyan
    & snow sql -c $Connection -q "DROP DATABASE IF EXISTS $Database"
}
else {
    Write-Host "The test database $Database is kept." -ForegroundColor Yellow
}

$summary = "$passed passed, $failed failed, $skipped skipped of $($results.Count) tests in $([math]::Round($elapsed.TotalSeconds)) s."
if ($failed -gt 0) {
    Write-Host $summary -ForegroundColor Red
    exit 1
}
Write-Host $summary -ForegroundColor Green
