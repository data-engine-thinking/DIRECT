using IntegrationTests.Infrastructure;

namespace IntegrationTests.Tests.StoredProcedureTests;

/// <summary>
/// Regressions found by running DIRECT from an external orchestrator: row counts and instance ids
/// that outgrow their log conversions, automatic Module registration, the rollback statement that
/// omd.ModuleEvaluation builds, and the transaction omd.CreateBatchInstance left open.
/// </summary>
[TestClass]
public class OmdModuleLifecycleRegressionTests : BaseTestContainer
{
  [TestInitialize]
  public async Task TestInitialize()
  {
    await ContainerManager.InitializeAsync();
  }

  [TestCleanup]
  public async Task TestCleanup()
  {
    await ContainerManager.DisposeAsync();
  }

  /// <summary>
  /// Regression: the log message of the Success event converted the row count to NVARCHAR(10), so
  /// 10 billion inserted rows failed with an arithmetic overflow. Through
  /// omd.EndBatchModuleInstances this left the Batch Instance Executing, aborting the next run.
  /// </summary>
  [TestMethod]
  public async Task UpdateModuleInstance_SuccessWithTenBillionInsertedRows_RecordsTheRowCount()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await RegisterModuleAsync(conn, "m_ROW_COUNT", "N/A");
    var moduleInstanceId = await OpenModuleInstanceAsync(conn, "m_ROW_COUNT");
    await EvaluateAsync(conn, moduleInstanceId, "N");

    await conn.ExecuteAsync(
      "EXEC [omd].[UpdateModuleInstance] @ModuleInstanceId = @Id, @EventCode = N'Success', @RowCountInsert = @Rows;",
      new { Id = moduleInstanceId, Rows = 10_000_000_000L });

    var rows = await conn.ExecuteScalarAsync<long>(
      "SELECT [ROWS_INSERTED] FROM [omd].[MODULE_INSTANCE] WHERE [MODULE_INSTANCE_ID] = @Id;",
      new { Id = moduleInstanceId });

    Assert.AreEqual(10_000_000_000L, rows);
  }

  /// <summary>
  /// Regression: both evaluations converted a BIGINT instance id to NVARCHAR(10) for their log, so
  /// every evaluation failed once the ids reached 11 digits.
  /// </summary>
  [TestMethod]
  public async Task Evaluations_WithElevenDigitInstanceIds_Proceed()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.ExecuteAsync("DBCC CHECKIDENT ('omd.BATCH_INSTANCE', RESEED, 10000000000);");
    await conn.ExecuteAsync("DBCC CHECKIDENT ('omd.MODULE_INSTANCE', RESEED, 10000000000);");
    await RegisterModuleAsync(conn, "m_LARGE_ID", "N/A");

    var batchStatus = await conn.ExecuteScalarAsync<string>(
      """
      DECLARE @Id BIGINT, @Status NVARCHAR(100);
      EXEC [omd].[CreateBatchInstance] @BatchCode = N'b_LARGE_ID', @BatchInstanceId = @Id OUTPUT;
      EXEC [omd].[BatchEvaluation] @BatchInstanceId = @Id, @InternalProcessingStatusCode = @Status OUTPUT;
      SELECT @Status;
      """);
    var moduleInstanceId = await OpenModuleInstanceAsync(conn, "m_LARGE_ID");
    var (moduleStatus, _) = await EvaluateAsync(conn, moduleInstanceId, "N");

    Assert.AreEqual("Proceed", batchStatus);
    Assert.AreEqual("Proceed", moduleStatus);
  }

  /// <summary>
  /// Regression: omd.CreateModuleInstance called omd.RegisterModule without the area code that
  /// omd.MODULE requires, and took the wrong indicator of a new Module for a failure, so
  /// AUTO_REGISTER_MODULES could never register anything.
  /// </summary>
  [TestMethod]
  public async Task CreateModuleInstance_UnknownCodeWithAutoRegistration_RegistersTheModuleInTheMaintArea()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var moduleInstanceId = await OpenModuleInstanceAsync(conn, "m_AUTO_REGISTERED");

    var areaCode = await conn.ExecuteScalarAsync<string>(
      "SELECT [AREA_CODE] FROM [omd].[MODULE] WHERE [MODULE_CODE] = N'm_AUTO_REGISTERED';");

    Assert.IsTrue(moduleInstanceId > 0, "An unknown Module code must be registered and get a Module Instance.");
    Assert.AreEqual("MAINT", areaCode);
  }

  /// <summary>
  /// Regression: only the branch for an existing Module set the success indicator, so a Module that
  /// had just been registered was reported as a failure.
  /// </summary>
  [TestMethod]
  public async Task RegisterModule_NewAndExistingModule_ReportSuccess()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    const string register =
      """
      DECLARE @ModuleId INT, @SuccessIndicator CHAR(1);
      EXEC [omd].[RegisterModule]
        @ModuleCode = N'm_REGISTERED',
        @ModuleAreaCode = N'STG',
        @ModuleId = @ModuleId OUTPUT,
        @SuccessIndicator = @SuccessIndicator OUTPUT;
      SELECT @SuccessIndicator;
      """;

    var newModule = await conn.ExecuteScalarAsync<string>(register);
    var existingModule = await conn.ExecuteScalarAsync<string>(register);

    Assert.AreEqual("Y", newModule);
    Assert.AreEqual("Y", existingModule);
  }

  /// <summary>
  /// Regression: a target without brackets was quoted as one name, so dbo.Customer became
  /// [dbo.Customer] and the rollback statement named a table that does not exist.
  /// </summary>
  [TestMethod]
  [DataRow("Customer", "[Customer]")]
  [DataRow("dbo.Customer", "[dbo].[Customer]")]
  [DataRow("Sales.dbo.Customer", "[Sales].[dbo].[Customer]")]
  [DataRow("[dbo].[Customer]", "[dbo].[Customer]")]
  public async Task ModuleEvaluation_AfterAFailedInstance_QuotesEveryPartOfTheTarget(string target, string quotedTarget)
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await RegisterModuleAsync(conn, "m_ROLLBACK", target);
    var failedInstanceId = await FailAnInstanceAsync(conn, "m_ROLLBACK");

    var nextInstanceId = await OpenModuleInstanceAsync(conn, "m_ROLLBACK");
    var (status, rollbackStatement) = await EvaluateAsync(conn, nextInstanceId, "N");

    Assert.AreEqual("Proceed", status);
    Assert.AreEqual($"DELETE FROM {quotedTarget} WHERE [MODULE_INSTANCE_ID] IN ({failedInstanceId})", rollbackStatement);
  }

  /// <summary>
  /// Regression: QUOTENAME turned N/A into [N/A], which passed the check for a Module without a
  /// target. The rollback then deleted from a table that does not exist, so with rollback executed
  /// in the database every run after a failure failed. The load windows must still be removed.
  /// </summary>
  [TestMethod]
  [DataRow("Y")]
  [DataRow("N")]
  public async Task ModuleEvaluation_ModuleWithoutATarget_ProceedsAndRemovesTheLoadWindows(string executeRollback)
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await RegisterModuleAsync(conn, "m_NO_TARGET", "N/A");
    var failedInstanceId = await FailAnInstanceAsync(conn, "m_NO_TARGET");

    var nextInstanceId = await OpenModuleInstanceAsync(conn, "m_NO_TARGET");
    var (status, rollbackStatement) = await EvaluateAsync(conn, nextInstanceId, executeRollback);

    var windows = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM [omd].[SOURCE_CONTROL] WHERE [MODULE_INSTANCE_ID] = @Id;",
      new { Id = failedInstanceId });

    Assert.AreEqual("Proceed", status);
    Assert.IsNull(rollbackStatement);
    Assert.AreEqual(0, windows);
  }

  /// <summary>
  /// Regression: the failure jumps inside the transaction of omd.CreateBatchInstance left it open,
  /// so the procedure failed with error 266 instead of reporting why it failed.
  /// </summary>
  [TestMethod]
  public async Task CreateBatchInstance_UnknownCodeWithAutoRegistrationOff_ReportsTheFailureCleanly()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.ExecuteAsync(
      "UPDATE [omd_metadata].[FRAMEWORK_METADATA] SET [VALUE] = 'N' WHERE [CODE] = 'AUTO_REGISTER_BATCHES';");

    var (successIndicator, transactionCount) = await conn.QuerySingleAsync<(string, int)>(
      """
      DECLARE @SuccessIndicator CHAR(1);
      EXEC [omd].[CreateBatchInstance] @BatchCode = N'b_DOES_NOT_EXIST', @SuccessIndicator = @SuccessIndicator OUTPUT;
      SELECT @SuccessIndicator, @@TRANCOUNT;
      """);

    Assert.AreEqual("N", successIndicator);
    Assert.AreEqual(0, transactionCount);
  }

  private static Task RegisterModuleAsync(SqlConnection conn, string moduleCode, string target) =>
    conn.ExecuteAsync(
      """
      DECLARE @ModuleId INT;
      EXEC [omd].[RegisterModule]
        @ModuleCode = @ModuleCode,
        @ModuleAreaCode = N'STG',
        @ModuleTargetDataObject = @Target,
        @ModuleId = @ModuleId OUTPUT;
      """,
      new { ModuleCode = moduleCode, Target = target });

  private static Task<long> OpenModuleInstanceAsync(SqlConnection conn, string moduleCode) =>
    conn.ExecuteScalarAsync<long>(
      """
      DECLARE @Id BIGINT;
      EXEC [omd].[CreateModuleInstance] @ModuleCode = @ModuleCode, @ModuleInstanceId = @Id OUTPUT;
      SELECT @Id;
      """,
      new { ModuleCode = moduleCode });

  private static Task<(string Status, string? RollbackStatement)> EvaluateAsync(SqlConnection conn, long moduleInstanceId, string executeRollback) =>
    conn.QuerySingleAsync<(string, string?)>(
      """
      DECLARE @Status NVARCHAR(100), @RollbackStatement NVARCHAR(MAX);
      EXEC [omd].[ModuleEvaluation]
        @ModuleInstanceId = @Id,
        @ExecuteRollbackIndicator = @ExecuteRollback,
        @InternalProcessingStatusCode = @Status OUTPUT,
        @RollbackStatement = @RollbackStatement OUTPUT;
      SELECT @Status, @RollbackStatement;
      """,
      new { Id = moduleInstanceId, ExecuteRollback = executeRollback });

  /// <summary>Run an instance of the Module to a failure, with a recorded load window.</summary>
  private static async Task<long> FailAnInstanceAsync(SqlConnection conn, string moduleCode)
  {
    var moduleInstanceId = await OpenModuleInstanceAsync(conn, moduleCode);
    await EvaluateAsync(conn, moduleInstanceId, "N");
    await conn.ExecuteAsync(
      """
      EXEC [omd].[SetSourceControlValues] @ModuleInstanceId = @Id, @StartValue = N'2026-01-01', @EndValue = N'2026-02-01';
      EXEC [omd].[UpdateModuleInstance] @ModuleInstanceId = @Id, @EventCode = N'Failure';
      """,
      new { Id = moduleInstanceId });
    return moduleInstanceId;
  }
}
