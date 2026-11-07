using Microsoft.SqlServer.Dac;

namespace IntegrationTests.Infrastructure;

/// <summary>
/// Read-only diagnostic helpers used to dump server state on a failing migration test.
/// All methods swallow their own exceptions — diagnostics must never mask the original failure.
/// </summary>
public static class SqlDiagnostics
{
  public static async Task DumpAllAsync(string directConnectionString, string label)
  {
    Console.WriteLine();
    Console.WriteLine($"========== SqlDiagnostics: {label} ==========");
    await SafeAsync(() => DumpSchemaSummaryAsync(directConnectionString)).ConfigureAwait(false);
    await SafeAsync(() => DumpFrameworkVersionAsync(directConnectionString)).ConfigureAwait(false);
    await SafeAsync(() => DumpRecentEventLogAsync(directConnectionString)).ConfigureAwait(false);
    Console.WriteLine($"========== end {label} ==========");
    Console.WriteLine();
  }

  public static async Task DumpSchemaSummaryAsync(string directConnectionString)
  {
    using var conn = new SqlConnection(directConnectionString);
    await conn.OpenAsync().ConfigureAwait(false);
    var rows = await conn.QueryAsync<(string Schema, string Kind, int Cnt)>(@"
SELECT s.name AS [Schema], 'TABLE'      AS Kind, COUNT(*) AS Cnt FROM sys.tables     t JOIN sys.schemas s ON t.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'VIEW',           COUNT(*)            FROM sys.views      v JOIN sys.schemas s ON v.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'PROCEDURE',      COUNT(*)            FROM sys.procedures p JOIN sys.schemas s ON p.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'FUNCTION',       COUNT(*)            FROM sys.objects    o JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN','IF','TF') GROUP BY s.name
ORDER BY [Schema], Kind;").ConfigureAwait(false);

    Console.WriteLine("Schema summary:");
    foreach (var (schema, kind, cnt) in rows)
      Console.WriteLine($"  {schema,-20} {kind,-10} {cnt}");
  }

  public static async Task DumpFrameworkVersionAsync(string directConnectionString)
  {
    using var conn = new SqlConnection(directConnectionString);
    await conn.OpenAsync().ConfigureAwait(false);
    var hasFn = await conn.ExecuteScalarAsync<int>(@"
SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES
WHERE SPECIFIC_SCHEMA = 'omd_metadata' AND SPECIFIC_NAME = 'GetFrameworkVersion' AND ROUTINE_TYPE = 'FUNCTION';").ConfigureAwait(false);
    if (hasFn == 0)
    {
      Console.WriteLine("Framework version: <omd_metadata.GetFrameworkVersion not present>");
      return;
    }
    var v = await conn.ExecuteScalarAsync<string?>("SELECT [omd_metadata].[GetFrameworkVersion]();").ConfigureAwait(false);
    Console.WriteLine($"Framework version: {v ?? "<null>"}");
  }

  public static async Task DumpRecentEventLogAsync(string directConnectionString, int rowCount = 50)
  {
    using var conn = new SqlConnection(directConnectionString);
    await conn.OpenAsync().ConfigureAwait(false);
    var hasTable = await conn.ExecuteScalarAsync<int>(@"
SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'omd' AND TABLE_NAME = 'EVENT_LOG';").ConfigureAwait(false);
    if (hasTable == 0)
    {
      Console.WriteLine("EVENT_LOG: <omd.EVENT_LOG not present>");
      return;
    }
    var rows = await conn.QueryAsync($@"SELECT TOP ({rowCount}) * FROM omd.EVENT_LOG ORDER BY EVENT_LOG_ID DESC;").ConfigureAwait(false);
    Console.WriteLine($"EVENT_LOG (last {rowCount}):");
    foreach (var r in rows)
      Console.WriteLine("  " + r);
  }

  /// <summary>
  /// Returns object counts per schema, suitable for pre/post migration comparison.
  /// Key format: "schema.kind" e.g. "omd.TABLE".
  /// </summary>
  public static async Task<Dictionary<string, int>> BuildSchemaFingerprintAsync(string directConnectionString)
  {
    using var conn = new SqlConnection(directConnectionString);
    await conn.OpenAsync().ConfigureAwait(false);
    var rows = await conn.QueryAsync<(string Schema, string Kind, int Cnt)>(@"
SELECT s.name AS [Schema], 'TABLE'      AS Kind, COUNT(*) AS Cnt FROM sys.tables     t JOIN sys.schemas s ON t.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'VIEW',           COUNT(*)            FROM sys.views      v JOIN sys.schemas s ON v.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'PROCEDURE',      COUNT(*)            FROM sys.procedures p JOIN sys.schemas s ON p.schema_id = s.schema_id GROUP BY s.name UNION ALL
SELECT s.name,             'FUNCTION',       COUNT(*)            FROM sys.objects    o JOIN sys.schemas s ON o.schema_id = s.schema_id WHERE o.type IN ('FN','IF','TF') GROUP BY s.name;").ConfigureAwait(false);

    return rows.ToDictionary(r => $"{r.Schema}.{r.Kind}", r => r.Cnt);
  }

  /// <summary>
  /// Generates the T-SQL DacFx would emit to upgrade <paramref name="connectionString"/> with
  /// <paramref name="dacpacPath"/> and writes it to <paramref name="outPath"/>. Best-effort:
  /// errors are logged but never thrown.
  /// </summary>
  public static void TryCaptureDeployScript(string dacpacPath, string connectionString, string targetDb, string outPath)
  {
    try
    {
      using var dacpac = DacPackage.Load(dacpacPath);
      var services = new DacServices(connectionString);
      var script = services.GenerateDeployScript(dacpac, targetDb, new DacDeployOptions
      {
        BlockOnPossibleDataLoss = false,
        CreateNewDatabase = false,
        DropObjectsNotInSource = true,
        VerifyDeployment = false,
        CommandTimeout = 120,
      });
      Directory.CreateDirectory(Path.GetDirectoryName(outPath)!);
      File.WriteAllText(outPath, script);
      Console.WriteLine($"[SqlDiagnostics] deploy script captured -> {outPath}");
    }
    catch (Exception ex)
    {
      Console.WriteLine($"[SqlDiagnostics] could not capture deploy script: {ex.GetType().Name}: {ex.Message}");
    }
  }

  private static async Task SafeAsync(Func<Task> action)
  {
    try { await action().ConfigureAwait(false); }
    catch (Exception ex)
    {
      Console.WriteLine($"[SqlDiagnostics] dump failed: {ex.GetType().Name}: {ex.Message}");
    }
  }
}
