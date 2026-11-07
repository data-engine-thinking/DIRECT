using System.Diagnostics;

using IntegrationTests.Infrastructure;

using Microsoft.SqlServer.Dac;

namespace IntegrationTests.Tests.MigrationTests;

/// <summary>
/// Exercises the upgrade path from the most recent published DIRECT release to the locally-built
/// "next" dacpac. The "current" baseline is resolved via <see cref="ReleaseAssetResolver"/> (downloads
/// + caches release assets from GitHub) so no manual staging of the previous release is required.
///
/// A local override is honoured: if <c>Releases.Direct_Framework/current/db/Direct_Framework.dacpac</c>
/// exists, it wins (offline / power-user scenario).
/// </summary>
[TestClass]
public class MigrationTests : BaseTestContainer
{
  public TestContext TestContext { get; set; } = null!;

  [TestInitialize]
  public async Task TestInitialize()
  {
    await ContainerManager.InitializeAsync(version: "current");
  }

  [TestCleanup]
  public async Task TestCleanup()
  {
    await ContainerManager.DisposeAsync();
  }

  [TestMethod]
  public async Task Can_Migrate_From_Current_To_Next()
  {
    var ctx = await RunMigrationAsync();

    AssertFrameworkVersionAdvanced(ctx);
    await AssertAreaCodeRewrittenAsync(ctx);
    await AssertDescriptionColumnsRenamedAsync();
    await AssertSeededRowsPreservedAsync(ctx);
    AssertSchemaFingerprintNotRegressed(ctx);
    AssertExpectedSchemasPresent(ctx);
  }

  [TestMethod]
  public async Task Migration_Is_Idempotent()
  {
    var ctx = await RunMigrationAsync();
    var projectDir = GetProjectDir();
    var nextPreDeploy = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db",
      "DeploymentScripts", "1-PreDacpacDeployment", "PreDacpacDeployment.sql");

    // Re-run the pre-dacpac script on the already-migrated database. It should detect the
    // database is already at the current version and no-op without error.
    ContainerManager.RunSqlCmdScript(nextPreDeploy, ContainerManager.DirectConnectionString);

    // Sanity: framework version is still at the expected target.
    var v = await GetFrameworkVersionAsync();
    Assert.AreEqual(ctx.ExpectedTargetVersion, v,
      $"idempotent re-run of PreDacpacDeployment.sql should leave version at {ctx.ExpectedTargetVersion}");
  }

  // ------------------------------------------------------------
  // Migration pipeline
  // ------------------------------------------------------------

  private sealed class MigrationContext
  {
    public ResolvedRelease Baseline { get; init; } = null!;
    public string ExpectedTargetVersion { get; init; } = "";
    public string? PreMigrationVersion { get; set; }
    public string? PostMigrationVersion { get; set; }
    public Dictionary<string, int> PreFingerprint { get; set; } = new();
    public Dictionary<string, int> PostFingerprint { get; set; } = new();
    public long SeededBatchRowCount { get; set; }
    public long SeededModuleRowCount { get; set; }
    public long MigrationSeedModuleId { get; set; }
    public const string DescriptionSentinel = "migration-test-sentinel";
    public const string MaintAreaCode = "Maintenance";
  }

  private async Task<MigrationContext> RunMigrationAsync()
  {
    var projectDir = GetProjectDir();
    var expectedVersion = (await File.ReadAllTextAsync(Path.Combine(projectDir, ".direct-version"))).Trim();

    // The baseline was already deployed by TestInitialize. Grab the resolved info so we know
    // where the current release's DeploymentScripts live (if present).
    var baseline = ContainerManager.ResolvedBaseline
      ?? throw new InvalidOperationException(
        "No ResolvedBaseline set after TestInitialize — expected a 'current' deploy from the resolver or local override.");

    var ctx = new MigrationContext
    {
      Baseline = baseline,
      ExpectedTargetVersion = expectedVersion,
    };

    await Step(1, "drop+redeploy current dacpac (clean baseline)", async () =>
    {
      await DropDatabaseAsync();
      var currentDacpacPath = Path.Combine(baseline.RootDir, "Direct_Framework.dacpac");
      using var dacpac = DacPackage.Load(currentDacpacPath);
      var services = new DacServices(ContainerManager.MasterConnectionString);
      services.Deploy(dacpac, "Direct_Framework", upgradeExisting: true, SqlServerContainerManager.DefaultDeployOptions());
    });

    await Step(2, "run CURRENT PostDacpacDeployment.sql (if shipped)", () =>
    {
      if (!baseline.HasDeploymentScripts)
      {
        Console.WriteLine($"WARNING: release {baseline.Tag} has no DeploymentScripts asset; " +
                          "skipping postdeploy step (test still validates migration chain).");
        return Task.CompletedTask;
      }
      var postDeploy = Path.Combine(baseline.RootDir,
        "DeploymentScripts", "4-PostDacpacDeployment", "PostDacpacDeployment.sql");
      if (!File.Exists(postDeploy))
      {
        Console.WriteLine($"WARNING: baseline {baseline.Tag} ships DeploymentScripts/ but no " +
                          "4-PostDacpacDeployment/PostDacpacDeployment.sql — skipping.");
        return Task.CompletedTask;
      }
      ContainerManager.RunSqlCmdScript(postDeploy, ContainerManager.DirectConnectionString);
      return Task.CompletedTask;
    });

    await Step(3, "seed representative data for migration", async () =>
    {
      await ContainerManager.PopulateDatabaseAsync();
      await SeedForMigrationAsync(ctx);
    });

    await Step(4, "capture pre-migration fingerprint", async () =>
    {
      ctx.PreFingerprint = await SqlDiagnostics.BuildSchemaFingerprintAsync(ContainerManager.DirectConnectionString);
      ctx.PreMigrationVersion = await GetFrameworkVersionAsync();
      ctx.SeededBatchRowCount = await CountAsync("SELECT COUNT_BIG(*) FROM omd.BATCH");
      ctx.SeededModuleRowCount = await CountAsync("SELECT COUNT_BIG(*) FROM omd.MODULE");
      Console.WriteLine($"  pre : version={ctx.PreMigrationVersion} batches={ctx.SeededBatchRowCount} modules={ctx.SeededModuleRowCount}");
    });

    await Step(5, "run NEXT PreDacpacDeployment.sql (migration under test)", () =>
    {
      var preDeploy = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db",
        "DeploymentScripts", "1-PreDacpacDeployment", "PreDacpacDeployment.sql");
      try
      {
        ContainerManager.RunSqlCmdScript(preDeploy, ContainerManager.DirectConnectionString);
      }
      catch
      {
        // Capture what SqlPackage WOULD do as supplementary diagnostics
        var nextDacpacPath = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db", "Direct_Framework.dacpac");
        var outPath = Path.Combine(TestContext.TestRunResultsDirectory ?? Path.GetTempPath(),
          $"deploy-script-{TestContext.TestName}.sql");
        SqlDiagnostics.TryCaptureDeployScript(nextDacpacPath, ContainerManager.MasterConnectionString, "Direct_Framework", outPath);
        throw;
      }
      return Task.CompletedTask;
    });

    await Step(6, "deploy NEXT dacpac", () =>
    {
      var nextDacpacPath = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db", "Direct_Framework.dacpac");
      using var dacpac = DacPackage.Load(nextDacpacPath);
      var services = new DacServices(ContainerManager.MasterConnectionString);
      var options = SqlServerContainerManager.DefaultDeployOptions();
      options.CreateNewDatabase = false; // we want an in-place upgrade, not a rebuild
      services.Deploy(dacpac, "Direct_Framework", upgradeExisting: true, options);
      return Task.CompletedTask;
    });

    await Step(7, "run NEXT PostDacpacDeployment.sql", () =>
    {
      var postDeploy = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db",
        "DeploymentScripts", "4-PostDacpacDeployment", "PostDacpacDeployment.sql");
      if (File.Exists(postDeploy))
      {
        ContainerManager.RunSqlCmdScript(postDeploy, ContainerManager.DirectConnectionString);
      }
      return Task.CompletedTask;
    });

    await Step(8, "capture post-migration fingerprint", async () =>
    {
      ctx.PostFingerprint = await SqlDiagnostics.BuildSchemaFingerprintAsync(ContainerManager.DirectConnectionString);
      ctx.PostMigrationVersion = await GetFrameworkVersionAsync();
      Console.WriteLine($"  post: version={ctx.PostMigrationVersion}");
    });

    return ctx;
  }

  // ------------------------------------------------------------
  // Seeding helpers (migration-specific)
  // ------------------------------------------------------------

  private async Task SeedForMigrationAsync(MigrationContext ctx)
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.OpenAsync();

    // A MODULE row with AREA_CODE='Maintenance' so we can assert the v2.1 rewrite to 'MAINT'.
    // Ensure the referenced AREA row exists first.
    ctx.MigrationSeedModuleId = await conn.ExecuteScalarAsync<long>(@"
IF NOT EXISTS (SELECT 1 FROM [omd_metadata].[AREA] WHERE [AREA_CODE] = 'Maintenance')
  INSERT INTO [omd_metadata].[AREA] ([AREA_CODE]) VALUES ('Maintenance');

INSERT INTO [omd].[MODULE] (MODULE_CODE, MODULE_TYPE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET,
                             AREA_CODE, FREQUENCY_CODE, MODULE_DESCRIPTION, ACTIVE_INDICATOR, EXECUTABLE)
VALUES ('M_MIGRATION_AREA_TEST', 'Maintenance', 'src', 'tgt',
        'Maintenance', 'On-demand', 'area-code migration sentinel', 'Y', 'SELECT 1');

SELECT CAST(SCOPE_IDENTITY() AS BIGINT);");

    // Sentinel values in description columns that are renamed by Migration-2.1.0.0.sql
    await conn.ExecuteAsync($@"
IF COL_LENGTH('omd_metadata.INTERNAL_PROCESSING_STATUS', 'INTERNAL_PROCESSING_STATUS_CODE_DESCRIPTION') IS NOT NULL
  UPDATE TOP (1) [omd_metadata].[INTERNAL_PROCESSING_STATUS]
  SET [INTERNAL_PROCESSING_STATUS_CODE_DESCRIPTION] = '{MigrationContext.DescriptionSentinel}';

IF COL_LENGTH('omd_metadata.EVENT_TYPE', 'EVENT_TYPE_CODE_DESCRIPTION') IS NOT NULL
  UPDATE TOP (1) [omd_metadata].[EVENT_TYPE]
  SET [EVENT_TYPE_CODE_DESCRIPTION] = '{MigrationContext.DescriptionSentinel}';

IF COL_LENGTH('omd_metadata.NEXT_RUN_STATUS', 'NEXT_RUN_DESCRIPTION') IS NOT NULL
  UPDATE TOP (1) [omd_metadata].[NEXT_RUN_STATUS]
  SET [NEXT_RUN_DESCRIPTION] = '{MigrationContext.DescriptionSentinel}';");
  }

  // ------------------------------------------------------------
  // Assertions
  // ------------------------------------------------------------

  private void AssertFrameworkVersionAdvanced(MigrationContext ctx)
  {
    Assert.IsFalse(string.IsNullOrWhiteSpace(ctx.PostMigrationVersion),
      "omd_metadata.GetFrameworkVersion() returned null/empty after migration");

    // .direct-version is semver (2.1.0); framework stores dotnet-style 2.1.0.0 — compare prefix.
    var expectedPrefix = ctx.ExpectedTargetVersion;
    Assert.IsTrue(ctx.PostMigrationVersion!.StartsWith(expectedPrefix, StringComparison.Ordinal),
      $"post-migration version '{ctx.PostMigrationVersion}' does not match .direct-version '{expectedPrefix}'");
  }

  private async Task AssertAreaCodeRewrittenAsync(MigrationContext ctx)
  {
    var areaCode = await ReadScalarAsync<string>(
      $"SELECT AREA_CODE FROM omd.MODULE WHERE MODULE_ID = {ctx.MigrationSeedModuleId}");
    Assert.AreEqual("MAINT", areaCode,
      "Migration-2.1.0.0.sql should rewrite MODULE.AREA_CODE 'Maintenance' -> 'MAINT'");

    var areaMeta = await ReadScalarAsync<string>(
      "SELECT AREA_CODE FROM omd_metadata.AREA WHERE AREA_CODE IN ('Maintenance', 'MAINT')");
    Assert.AreEqual("MAINT", areaMeta,
      "Migration should also rewrite omd_metadata.AREA 'Maintenance' -> 'MAINT'");
  }

  private async Task AssertDescriptionColumnsRenamedAsync()
  {
    await AssertRenamedColumnAsync("omd_metadata", "INTERNAL_PROCESSING_STATUS",
      "INTERNAL_PROCESSING_STATUS_CODE_DESCRIPTION", "INTERNAL_PROCESSING_STATUS_DESCRIPTION");
    await AssertRenamedColumnAsync("omd_metadata", "EVENT_TYPE",
      "EVENT_TYPE_CODE_DESCRIPTION", "EVENT_TYPE_DESCRIPTION");
    await AssertRenamedColumnAsync("omd_metadata", "NEXT_RUN_STATUS",
      "NEXT_RUN_DESCRIPTION", "NEXT_RUN_STATUS_DESCRIPTION");
  }

  private async Task AssertRenamedColumnAsync(string schema, string table, string oldCol, string newCol)
  {
    var oldGone = await ReadScalarAsync<int>(
      $"SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='{schema}' AND TABLE_NAME='{table}' AND COLUMN_NAME='{oldCol}'") == 0;
    var newExists = await ReadScalarAsync<int>(
      $"SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='{schema}' AND TABLE_NAME='{table}' AND COLUMN_NAME='{newCol}'") == 1;
    Assert.IsTrue(oldGone, $"{schema}.{table}.{oldCol} should be dropped after migration");
    Assert.IsTrue(newExists, $"{schema}.{table}.{newCol} should exist after migration");

    var sentinelCount = await ReadScalarAsync<int>(
      $"SELECT COUNT(*) FROM [{schema}].[{table}] WHERE [{newCol}] = '{MigrationContext.DescriptionSentinel}'");
    Assert.IsTrue(sentinelCount >= 1,
      $"sentinel seeded into {oldCol} was not copied to renamed column {newCol}");
  }

  private async Task AssertSeededRowsPreservedAsync(MigrationContext ctx)
  {
    var postBatch = await ReadScalarAsync<long>("SELECT COUNT_BIG(*) FROM omd.BATCH");
    var postModule = await ReadScalarAsync<long>("SELECT COUNT_BIG(*) FROM omd.MODULE");
    Assert.AreEqual(ctx.SeededBatchRowCount, postBatch, "omd.BATCH row count changed during migration");
    Assert.AreEqual(ctx.SeededModuleRowCount, postModule, "omd.MODULE row count changed during migration");
  }

  private void AssertSchemaFingerprintNotRegressed(MigrationContext ctx)
  {
    // Allowed: new objects added in the migration. Disallowed: object count going DOWN without an
    // equivalent explicit deprecation in the migration script. Right now we just check that no
    // schema.kind count dropped to zero unexpectedly.
    foreach (var (key, preCount) in ctx.PreFingerprint)
    {
      if (preCount == 0) continue;
      ctx.PostFingerprint.TryGetValue(key, out var postCount);
      Assert.IsTrue(postCount > 0,
        $"schema fingerprint regression: {key} had {preCount} objects before migration, {postCount} after");
    }
  }

  private void AssertExpectedSchemasPresent(MigrationContext ctx)
  {
    foreach (var expected in new[] { "omd", "omd_metadata" })
    {
      ctx.PostFingerprint.TryGetValue($"{expected}.TABLE", out var tables);
      Assert.IsTrue(tables > 0, $"expected schema '{expected}' has no tables post-migration");
    }
  }

  // ------------------------------------------------------------
  // small helpers
  // ------------------------------------------------------------

  private async Task<T?> ReadScalarAsync<T>(string sql)
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.OpenAsync();
    return await conn.ExecuteScalarAsync<T?>(sql);
  }

  private Task<long> CountAsync(string sql) => ReadScalarAsync<long>(sql)!;

  private async Task<string?> GetFrameworkVersionAsync()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.OpenAsync();
    var hasFn = await conn.ExecuteScalarAsync<int>(@"
SELECT COUNT(*) FROM INFORMATION_SCHEMA.ROUTINES
WHERE SPECIFIC_SCHEMA='omd_metadata' AND SPECIFIC_NAME='GetFrameworkVersion' AND ROUTINE_TYPE='FUNCTION';");
    if (hasFn == 0) return null;
    return await conn.ExecuteScalarAsync<string?>("SELECT [omd_metadata].[GetFrameworkVersion]();");
  }

  private async Task DropDatabaseAsync()
  {
    await using var conn = new SqlConnection(ContainerManager.MasterConnectionString);
    await conn.OpenAsync();
    await using var cmd = new SqlCommand(@"
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'Direct_Framework')
BEGIN
  ALTER DATABASE [Direct_Framework] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [Direct_Framework];
END", conn);
    await cmd.ExecuteNonQueryAsync();
  }

  private static string GetProjectDir()
  {
    var outputDir = AppContext.BaseDirectory;
    return Directory.GetParent(outputDir)!.Parent!.Parent!.Parent!.Parent!.FullName;
  }

  private async Task Step(int n, string label, Func<Task> body)
  {
    Console.WriteLine($">>> step {n}: {label}");
    var sw = Stopwatch.StartNew();
    try
    {
      await body();
      Console.WriteLine($"<<< step {n}: {label} ({sw.ElapsedMilliseconds} ms)");
    }
    catch (Exception ex)
    {
      Console.WriteLine($"!!! step {n} FAILED: {label} after {sw.ElapsedMilliseconds} ms: {ex.GetType().Name}: {ex.Message}");
      try
      {
        await SqlDiagnostics.DumpAllAsync(ContainerManager.DirectConnectionString, $"step {n} failure");
      }
      catch { /* best-effort diagnostic, never mask the original */ }
      throw;
    }
  }
}
