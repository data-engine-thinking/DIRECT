namespace IntegrationTests.Tests.StoredProcedureTests;

/// <summary>
/// Integration tests for the external orchestration procedures
/// [omd].[CreateBatchModuleInstances] and [omd].[EndBatchModuleInstances], and the view
/// [omd_processing].[vw_BATCH_HIERARCHY].
/// </summary>
[TestClass]
public class OmdBatchModuleInstancesTests : BaseTestContainer
{
  private const string BatchCode = "b_INGESTION_EXAMPLE";
  private const string FirstModuleCode = "M_INGESTION_EXAMPLE";
  private const string SecondModuleCode = "M_INGESTION_EXAMPLE_2";
  private const string ChildBatchCode = "b_INGESTION_EXAMPLE_CHILD";
  private const string ChildModuleCode = "M_INGESTION_EXAMPLE_CHILD";
  private const string GrandchildBatchCode = "b_INGESTION_EXAMPLE_GRANDCHILD";
  private const string GrandchildModuleCode = "M_INGESTION_EXAMPLE_GRANDCHILD";

  [TestInitialize]
  public async Task TestInitialize()
  {
    await ContainerManager.InitializeAsync();
    await ContainerManager.PopulateDatabaseAsync();
    await ArrangeBatchWithTwoModulesAsync();
  }

  [TestCleanup]
  public async Task TestCleanup()
  {
    await ContainerManager.DisposeAsync();
  }

  /// <summary>
  /// Adds a second Module and links both Modules to the example Batch, the second one first by sequence.
  /// Also adds a child Batch with one Module under the example Batch, and a grandchild Batch with one Module under the child.
  /// </summary>
  private async Task ArrangeBatchWithTwoModulesAsync()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    await conn.ExecuteAsync(@"
      INSERT INTO omd.MODULE (MODULE_CODE, MODULE_TYPE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, AREA_CODE, FREQUENCY_CODE, MODULE_DESCRIPTION, ACTIVE_INDICATOR, EXECUTABLE)
      VALUES (@SecondModuleCode, N'Ingestion', N'SourceObject2', N'TargetObject2', N'STG', N'On-demand', N'Second example module', 'Y', N'SELECT 2');

      INSERT INTO omd.BATCH_MODULE (BATCH_ID, MODULE_ID, [SEQUENCE], ACTIVE_INDICATOR)
      SELECT b.BATCH_ID, m.MODULE_ID, CASE WHEN m.MODULE_CODE = @FirstModuleCode THEN 20 ELSE 10 END, 'Y'
      FROM omd.BATCH b CROSS JOIN omd.MODULE m
      WHERE b.BATCH_CODE = @BatchCode AND m.MODULE_CODE IN (@FirstModuleCode, @SecondModuleCode);

      INSERT INTO omd.BATCH (BATCH_CODE, BATCH_TYPE, FREQUENCY_CODE, ACTIVE_INDICATOR, BATCH_DESCRIPTION)
      VALUES (@ChildBatchCode, N'Ingestion', N'On-demand', 'Y', N'Child batch');

      INSERT INTO omd.BATCH_HIERARCHY (PARENT_BATCH_ID, BATCH_ID, [SEQUENCE], ACTIVE_INDICATOR)
      SELECT p.BATCH_ID, c.BATCH_ID, 1, 'Y'
      FROM omd.BATCH p JOIN omd.BATCH c ON c.BATCH_CODE = @ChildBatchCode
      WHERE p.BATCH_CODE = @BatchCode;

      INSERT INTO omd.MODULE (MODULE_CODE, MODULE_TYPE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, AREA_CODE, FREQUENCY_CODE, MODULE_DESCRIPTION, ACTIVE_INDICATOR, EXECUTABLE)
      VALUES (@ChildModuleCode, N'Ingestion', N'SourceObject3', N'TargetObject3', N'STG', N'On-demand', N'Child batch module', 'Y', N'SELECT 3'),
             (@GrandchildModuleCode, N'Ingestion', N'SourceObject4', N'TargetObject4', N'STG', N'On-demand', N'Grandchild batch module', 'Y', N'SELECT 4');

      INSERT INTO omd.BATCH_MODULE (BATCH_ID, MODULE_ID, [SEQUENCE], ACTIVE_INDICATOR)
      SELECT b.BATCH_ID, m.MODULE_ID, 10, 'Y'
      FROM omd.BATCH b JOIN omd.MODULE m ON m.MODULE_CODE = @ChildModuleCode
      WHERE b.BATCH_CODE = @ChildBatchCode;

      INSERT INTO omd.BATCH (BATCH_CODE, BATCH_TYPE, FREQUENCY_CODE, ACTIVE_INDICATOR, BATCH_DESCRIPTION)
      VALUES (@GrandchildBatchCode, N'Ingestion', N'On-demand', 'Y', N'Grandchild batch');

      INSERT INTO omd.BATCH_HIERARCHY (PARENT_BATCH_ID, BATCH_ID, [SEQUENCE], ACTIVE_INDICATOR)
      SELECT p.BATCH_ID, c.BATCH_ID, 1, 'Y'
      FROM omd.BATCH p JOIN omd.BATCH c ON c.BATCH_CODE = @GrandchildBatchCode
      WHERE p.BATCH_CODE = @ChildBatchCode;

      INSERT INTO omd.BATCH_MODULE (BATCH_ID, MODULE_ID, [SEQUENCE], ACTIVE_INDICATOR)
      SELECT b.BATCH_ID, m.MODULE_ID, 10, 'Y'
      FROM omd.BATCH b JOIN omd.MODULE m ON m.MODULE_CODE = @GrandchildModuleCode
      WHERE b.BATCH_CODE = @GrandchildBatchCode;",
      new { BatchCode, FirstModuleCode, SecondModuleCode, ChildBatchCode, ChildModuleCode, GrandchildBatchCode, GrandchildModuleCode });
  }

  private static DynamicParameters CreateParameters(string? batchCode, string? consistencyModuleTypeList = null)
  {
    var parameters = new DynamicParameters();
    parameters.Add("@BatchCode", batchCode, dbType: System.Data.DbType.String, size: 500);
    parameters.Add("@ExecutionContext", "integration test", dbType: System.Data.DbType.String, size: 4000);
    parameters.Add("@ConsistencyModuleTypeList", consistencyModuleTypeList, dbType: System.Data.DbType.String, size: 4000);
    parameters.Add("@Debug", "N");
    parameters.Add("@BatchInstanceId", dbType: System.Data.DbType.Int64, direction: System.Data.ParameterDirection.Output);
    parameters.Add("@InternalProcessingStatusCode", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: 100);
    parameters.Add("@SuccessIndicator", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: 1);
    parameters.Add("@MessageLog", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: -1);
    parameters.Add("@ReturnCode", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.ReturnValue);
    return parameters;
  }

  private static DynamicParameters EndParameters(long batchInstanceId, string? moduleResults, string? batchEventCode = null)
  {
    var parameters = new DynamicParameters();
    parameters.Add("@BatchInstanceId", batchInstanceId);
    parameters.Add("@ModuleResults", moduleResults, dbType: System.Data.DbType.String, size: -1);
    parameters.Add("@BatchEventCode", batchEventCode, dbType: System.Data.DbType.String, size: 100);
    parameters.Add("@Debug", "N");
    parameters.Add("@ReportedCount", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.Output);
    parameters.Add("@FailedCount", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.Output);
    parameters.Add("@ExecutionStatusCode", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: 100);
    parameters.Add("@SuccessIndicator", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: 1);
    parameters.Add("@MessageLog", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: -1);
    parameters.Add("@ReturnCode", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.ReturnValue);
    return parameters;
  }

  private async Task<(List<dynamic> Rows, DynamicParameters Parameters)> CreateWithChildrenAsync(SqlConnection conn, string? batchCode)
  {
    var parameters = CreateParameters(batchCode);
    parameters.Add("@IncludeChildBatches", "Y");
    parameters.Add("@BatchInstancesJson", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: -1);
    var rows = (await conn.QueryAsync("[omd].[CreateBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure)).ToList();
    return (rows, parameters);
  }

  private static DynamicParameters EndWithChildrenParameters(long batchInstanceId, string? moduleResults)
  {
    var parameters = EndParameters(batchInstanceId, moduleResults);
    parameters.Add("@IncludeChildBatches", "Y");
    parameters.Add("@FailedBatchCount", dbType: System.Data.DbType.Int32, direction: System.Data.ParameterDirection.Output);
    return parameters;
  }

  private static string SuccessResults(IEnumerable<dynamic> rows) =>
    "[" + string.Join(",", rows.Select(r => $@"{{ ""ModuleInstanceId"": {(long)r.MODULE_INSTANCE_ID}, ""EventCode"": ""Success"", ""StartValue"": ""{(string)r.PREVIOUS_END_VALUE}"", ""EndValue"": ""2026-10-26 10:00:00.0000000"" }}")) + "]";

  private async Task<(List<dynamic> Rows, DynamicParameters Parameters)> CreateAsync(SqlConnection conn, string? batchCode, string? consistencyModuleTypeList = null)
  {
    var parameters = CreateParameters(batchCode, consistencyModuleTypeList);
    var rows = (await conn.QueryAsync("[omd].[CreateBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure)).ToList();
    return (rows, parameters);
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_OpensBatchAndModulesInSequence_OnSuccess()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var (rows, parameters) = await CreateAsync(conn, BatchCode);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"Return code should be 0. MessageLog: {messageLog}");
    Assert.AreEqual("Y", parameters.Get<string?>("@SuccessIndicator"), $"SuccessIndicator should be Y. MessageLog: {messageLog}");
    Assert.AreEqual("Proceed", parameters.Get<string?>("@InternalProcessingStatusCode"));
    var batchInstanceId = parameters.Get<long?>("@BatchInstanceId");
    Assert.IsNotNull(batchInstanceId);

    Assert.HasCount(2, rows, "One row per Module in the Batch is expected.");
    Assert.AreEqual(SecondModuleCode, (string)rows[0].MODULE_CODE, "Modules are returned in SEQUENCE order.");
    Assert.AreEqual(FirstModuleCode, (string)rows[1].MODULE_CODE);
    Assert.AreEqual("Proceed", (string)rows[0].INTERNAL_PROCESSING_STATUS_CODE);
    Assert.AreEqual("1900-01-01", (string)rows[0].PREVIOUS_END_VALUE, "A Module without a load window gets the default start value.");
    Assert.IsNull(rows[0].ROLLBACK_STATEMENT);
    Assert.IsNull(rows[0].CONSISTENCY_DATETIME);
    Assert.AreEqual(batchInstanceId.Value, (long)rows[0].BATCH_INSTANCE_ID);

    var executing = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM omd.MODULE_INSTANCE WHERE BATCH_INSTANCE_ID = @Id AND EXECUTION_STATUS_CODE = 'Executing'", new { Id = batchInstanceId });
    Assert.AreEqual(2, executing, "Both Module Instances are executing until the orchestrator reports.");

    var batchStatus = await conn.ExecuteScalarAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = @Id", new { Id = batchInstanceId });
    Assert.AreEqual("Executing", batchStatus);
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_ReturnsEmptyResultSet_WhenBatchIsAborted()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    // A first instance is left executing, so the second one aborts
    var (firstRows, first) = await CreateAsync(conn, BatchCode);
    Assert.HasCount(2, firstRows);
    Assert.AreEqual("Y", first.Get<string?>("@SuccessIndicator"));

    var (rows, parameters) = await CreateAsync(conn, BatchCode);

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"MessageLog: {parameters.Get<string?>("@MessageLog")}");
    Assert.AreEqual("Abort", parameters.Get<string?>("@InternalProcessingStatusCode"));
    Assert.IsEmpty(rows, "No Module Instances are created for an aborted Batch Instance.");
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_ReturnsMinus1_WhenBatchCodeIsMissing()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var (rows, parameters) = await CreateAsync(conn, null);

    Assert.AreEqual(-1, parameters.Get<int>("@ReturnCode"));
    Assert.AreEqual("N", parameters.Get<string?>("@SuccessIndicator"));
    Assert.IsEmpty(rows);
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_ClosesModulesAndBatch_OnSuccess()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (rows, create) = await CreateAsync(conn, BatchCode);
    var batchInstanceId = create.Get<long>("@BatchInstanceId");
    long firstInstance = rows[0].MODULE_INSTANCE_ID;
    long secondInstance = rows[1].MODULE_INSTANCE_ID;

    var results = $@"[
      {{ ""ModuleInstanceId"": {firstInstance}, ""EventCode"": ""Success"", ""StartValue"": ""1900-01-01"", ""EndValue"": ""2026-01-01 00:00:00"", ""RowCountInsert"": 17 }},
      {{ ""moduleInstanceId"": {secondInstance}, ""eventCode"": ""Success"", ""startValue"": ""1900-01-01"", ""endValue"": ""2026-01-01 00:00:00"", ""rowCountInsert"": 3 }}
    ]";

    var parameters = EndParameters(batchInstanceId, results);
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"Return code should be 0. MessageLog: {messageLog}");
    Assert.AreEqual("Y", parameters.Get<string?>("@SuccessIndicator"), $"MessageLog: {messageLog}");
    Assert.AreEqual(2, parameters.Get<int?>("@ReportedCount"));
    Assert.AreEqual(0, parameters.Get<int?>("@FailedCount"));
    Assert.AreEqual("Succeeded", parameters.Get<string?>("@ExecutionStatusCode"));

    var instances = (await conn.QueryAsync(
      "SELECT MODULE_INSTANCE_ID, EXECUTION_STATUS_CODE, ROWS_INSERTED FROM omd.MODULE_INSTANCE WHERE BATCH_INSTANCE_ID = @Id ORDER BY MODULE_INSTANCE_ID",
      new { Id = batchInstanceId })).ToList();
    Assert.HasCount(2, instances);
    Assert.IsTrue(instances.All(i => (string)i.EXECUTION_STATUS_CODE == "Succeeded"), "Both Module Instances succeeded.");
    Assert.AreEqual(17L, (long)instances.Single(i => (long)i.MODULE_INSTANCE_ID == firstInstance).ROWS_INSERTED);

    var sourceControl = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM omd.SOURCE_CONTROL WHERE MODULE_INSTANCE_ID IN (@First, @Second) AND START_VALUE = '1900-01-01' AND END_VALUE = '2026-01-01 00:00:00'",
      new { First = firstInstance, Second = secondInstance });
    Assert.AreEqual(2, sourceControl, "A load window is recorded per reported Module Instance.");

    var batchStatus = await conn.ExecuteScalarAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = @Id", new { Id = batchInstanceId });
    Assert.AreEqual("Succeeded", batchStatus);

    // The next run starts where the previous load window ended
    var (nextRows, _) = await CreateAsync(conn, BatchCode);
    Assert.AreEqual("2026-01-01 00:00:00", (string)nextRows[0].PREVIOUS_END_VALUE);
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_FailsBatchAndUnreportedModules_OnFailure()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (rows, create) = await CreateAsync(conn, BatchCode);
    var batchInstanceId = create.Get<long>("@BatchInstanceId");
    long reportedInstance = rows[0].MODULE_INSTANCE_ID;
    long unreportedInstance = rows[1].MODULE_INSTANCE_ID;

    var results = $@"[ {{ ""ModuleInstanceId"": {reportedInstance}, ""EventCode"": ""Failure"", ""EventDetail"": ""Division by zero"" }} ]";

    var parameters = EndParameters(batchInstanceId, results);
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"The bookkeeping itself succeeds. MessageLog: {messageLog}");
    Assert.AreEqual(1, parameters.Get<int?>("@ReportedCount"));
    Assert.AreEqual(2, parameters.Get<int?>("@FailedCount"), "The reported failure and the unreported instance are both failed.");
    Assert.AreEqual("Failed", parameters.Get<string?>("@ExecutionStatusCode"));

    var statuses = (await conn.QueryAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID IN (@A, @B)", new { A = reportedInstance, B = unreportedInstance })).ToList();
    Assert.IsTrue(statuses.All(s => s == "Failed"));

    var eventCount = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM omd.EVENT_LOG WHERE MODULE_INSTANCE_ID = @Id AND EVENT_DETAIL LIKE '%Division by zero%'", new { Id = reportedInstance });
    Assert.AreEqual(1, eventCount, "The failure detail is written to the event log.");

    // A failed instance is rolled back by the next evaluation; the rollback statement is returned, not executed
    var (nextRows, next) = await CreateAsync(conn, BatchCode);
    Assert.AreEqual("Proceed", next.Get<string?>("@InternalProcessingStatusCode"), next.Get<string?>("@MessageLog"));
    Assert.IsTrue(nextRows.Any(r => r.ROLLBACK_STATEMENT != null), "A rollback statement is returned for the failed Module.");
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_ReturnsMinus1_WhenJsonIsInvalid()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (_, create) = await CreateAsync(conn, BatchCode);
    var batchInstanceId = create.Get<long>("@BatchInstanceId");

    var parameters = EndParameters(batchInstanceId, "not json");
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);

    Assert.AreEqual(-1, parameters.Get<int>("@ReturnCode"));
    Assert.AreEqual("N", parameters.Get<string?>("@SuccessIndicator"));

    var batchStatus = await conn.ExecuteScalarAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = @Id", new { Id = batchInstanceId });
    Assert.AreEqual("Executing", batchStatus, "Nothing is changed when the input is rejected.");
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_ReturnsMinus1_WhenBatchInstanceIsNotExecuting()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (_, create) = await CreateAsync(conn, BatchCode);
    var batchInstanceId = create.Get<long>("@BatchInstanceId");

    var first = EndParameters(batchInstanceId, null, "Failure");
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", first, commandType: System.Data.CommandType.StoredProcedure);
    Assert.AreEqual(0, first.Get<int>("@ReturnCode"), first.Get<string?>("@MessageLog"));
    Assert.AreEqual("Failed", first.Get<string?>("@ExecutionStatusCode"));

    var second = EndParameters(batchInstanceId, null);
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", second, commandType: System.Data.CommandType.StoredProcedure);
    Assert.AreEqual(-1, second.Get<int>("@ReturnCode"), "A Batch Instance cannot be closed twice.");
  }

  [TestMethod]
  public async Task BatchHierarchyView_ReturnsChildBatches()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var children = (await conn.QueryAsync(
      "SELECT BATCH_CODE, [SEQUENCE], RELATIONSHIP_ACTIVE_INDICATOR, BATCH_ACTIVE_INDICATOR FROM omd_processing.vw_BATCH_HIERARCHY WHERE PARENT_BATCH_CODE = @Parent ORDER BY [SEQUENCE]",
      new { Parent = BatchCode })).ToList();

    Assert.HasCount(1, children);
    Assert.AreEqual(ChildBatchCode, (string)children[0].BATCH_CODE);
    Assert.AreEqual(1, (int)children[0].SEQUENCE);
    Assert.AreEqual("Y", (string)children[0].RELATIONSHIP_ACTIVE_INDICATOR);
    Assert.AreEqual("Y", (string)children[0].BATCH_ACTIVE_INDICATOR);

    // A child Batch Instance carries the parent Batch Instance Id
    var (_, parent) = await CreateAsync(conn, BatchCode);
    var parentId = parent.Get<long>("@BatchInstanceId");
    var childParameters = CreateParameters(ChildBatchCode);
    childParameters.Add("@ParentBatchInstanceId", parentId);
    var childRows = (await conn.QueryAsync("[omd].[CreateBatchModuleInstances]", childParameters, commandType: System.Data.CommandType.StoredProcedure)).ToList();
    Assert.IsEmpty(childRows, "The child Batch has no Modules.");
    Assert.AreEqual("Proceed", childParameters.Get<string?>("@InternalProcessingStatusCode"), childParameters.Get<string?>("@MessageLog"));

    var storedParent = await conn.ExecuteScalarAsync<long>(
      "SELECT PARENT_BATCH_INSTANCE_ID FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = @Id", new { Id = childParameters.Get<long>("@BatchInstanceId") });
    Assert.AreEqual(parentId, storedParent);
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_ReturnsRowsAsJson_WhenResultSetIsSuppressed()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var parameters = CreateParameters(BatchCode);
    parameters.Add("@ReturnResultSet", "N");
    parameters.Add("@ResultJson", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: -1);

    var rows = (await conn.QueryAsync("[omd].[CreateBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure)).ToList();
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"MessageLog: {messageLog}");
    Assert.AreEqual("Proceed", parameters.Get<string?>("@InternalProcessingStatusCode"));
    Assert.IsEmpty(rows, "No result set is returned when it is suppressed.");

    var json = parameters.Get<string?>("@ResultJson");
    Assert.IsNotNull(json);
    var parsed = System.Text.Json.JsonDocument.Parse(json).RootElement;
    Assert.AreEqual(System.Text.Json.JsonValueKind.Array, parsed.ValueKind);
    Assert.AreEqual(2, parsed.GetArrayLength(), "One JSON object per Module in the Batch is expected.");
    Assert.AreEqual(SecondModuleCode, parsed[0].GetProperty("MODULE_CODE").GetString(), "Rows are in SEQUENCE order.");
    Assert.AreEqual("Proceed", parsed[0].GetProperty("INTERNAL_PROCESSING_STATUS_CODE").GetString());
    Assert.AreEqual(parameters.Get<long>("@BatchInstanceId"), parsed[0].GetProperty("BATCH_INSTANCE_ID").GetInt64());
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_Proceeds_AfterTwoFailedBatchInstances()
  {
    // Two failed Batch Instances in a row make omd.GetFailedBatchIdList return a list of two ids;
    // the partial rollback in omd.BatchEvaluation must build a valid IN list from it.
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    for (var attempt = 1; attempt <= 2; attempt++)
    {
      var (rows, create) = await CreateAsync(conn, BatchCode);
      Assert.AreEqual("Proceed", create.Get<string?>("@InternalProcessingStatusCode"), $"Attempt {attempt}: {create.Get<string?>("@MessageLog")}");
      long firstInstance = rows[0].MODULE_INSTANCE_ID;
      long secondInstance = rows[1].MODULE_INSTANCE_ID;
      var results = $@"[ {{ ""ModuleInstanceId"": {firstInstance}, ""EventCode"": ""Success"" }}, {{ ""ModuleInstanceId"": {secondInstance}, ""EventCode"": ""Failure"", ""EventDetail"": ""Attempt {attempt} failed"" }} ]";
      var end = EndParameters(create.Get<long>("@BatchInstanceId"), results);
      await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", end, commandType: System.Data.CommandType.StoredProcedure);
      Assert.AreEqual("Failed", end.Get<string?>("@ExecutionStatusCode"), end.Get<string?>("@MessageLog"));
    }

    var (thirdRows, third) = await CreateAsync(conn, BatchCode);

    Assert.AreEqual(0, third.Get<int>("@ReturnCode"), third.Get<string?>("@MessageLog"));
    Assert.AreEqual("Proceed", third.Get<string?>("@InternalProcessingStatusCode"), third.Get<string?>("@MessageLog"));
    Assert.HasCount(2, thirdRows);
    Assert.IsTrue(thirdRows.Any(r => r.ROLLBACK_STATEMENT != null && !((string)r.ROLLBACK_STATEMENT).Contains("((")),
      "The rollback statement for the failed Module has a single pair of parentheses around the id list.");
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_OpensChildBatchesInRunOrder_WhenIncluded()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    var (rows, parameters) = await CreateWithChildrenAsync(conn, BatchCode);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"MessageLog: {messageLog}");
    Assert.AreEqual("Proceed", parameters.Get<string?>("@InternalProcessingStatusCode"));
    var rootInstanceId = parameters.Get<long>("@BatchInstanceId");

    // The Modules of the Batch first, then those of the child, then those of the grandchild
    Assert.HasCount(4, rows, "Two root Modules, one child Module and one grandchild Module are expected.");
    Assert.AreEqual(SecondModuleCode, (string)rows[0].MODULE_CODE);
    Assert.AreEqual(FirstModuleCode, (string)rows[1].MODULE_CODE);
    Assert.AreEqual(ChildModuleCode, (string)rows[2].MODULE_CODE);
    Assert.AreEqual(GrandchildModuleCode, (string)rows[3].MODULE_CODE);
    Assert.AreEqual(BatchCode, (string)rows[0].BATCH_CODE);
    Assert.AreEqual(ChildBatchCode, (string)rows[2].BATCH_CODE);
    Assert.AreEqual(GrandchildBatchCode, (string)rows[3].BATCH_CODE);
    Assert.IsTrue(rows.All(r => (string)r.INTERNAL_PROCESSING_STATUS_CODE == "Proceed"));

    var batches = System.Text.Json.JsonDocument.Parse(parameters.Get<string>("@BatchInstancesJson")).RootElement;
    Assert.AreEqual(3, batches.GetArrayLength(), "One Batch Instance per Batch in the hierarchy.");
    Assert.AreEqual(BatchCode, batches[0].GetProperty("BATCH_CODE").GetString());
    Assert.AreEqual(0, batches[0].GetProperty("LEVEL").GetInt32());
    Assert.AreEqual(2, batches[0].GetProperty("MODULE_COUNT").GetInt32());
    Assert.AreEqual(ChildBatchCode, batches[1].GetProperty("BATCH_CODE").GetString());
    Assert.AreEqual(1, batches[1].GetProperty("LEVEL").GetInt32());
    Assert.AreEqual(rootInstanceId, batches[1].GetProperty("PARENT_BATCH_INSTANCE_ID").GetInt64());
    Assert.AreEqual(GrandchildBatchCode, batches[2].GetProperty("BATCH_CODE").GetString());
    Assert.AreEqual(2, batches[2].GetProperty("LEVEL").GetInt32());
    Assert.AreEqual(batches[1].GetProperty("BATCH_INSTANCE_ID").GetInt64(), batches[2].GetProperty("PARENT_BATCH_INSTANCE_ID").GetInt64());
    Assert.AreEqual((long)rows[2].BATCH_INSTANCE_ID, batches[1].GetProperty("BATCH_INSTANCE_ID").GetInt64());

    var executingBatches = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM omd.BATCH_INSTANCE WHERE EXECUTION_STATUS_CODE = 'Executing' AND BATCH_INSTANCE_ID IN (@A, @B, @C)",
      new { A = rootInstanceId, B = batches[1].GetProperty("BATCH_INSTANCE_ID").GetInt64(), C = batches[2].GetProperty("BATCH_INSTANCE_ID").GetInt64() });
    Assert.AreEqual(3, executingBatches, "All Batch Instances stay executing until the orchestrator reports.");
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_ClosesChildBatches_OnSuccess()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (rows, create) = await CreateWithChildrenAsync(conn, BatchCode);
    var rootInstanceId = create.Get<long>("@BatchInstanceId");

    var parameters = EndWithChildrenParameters(rootInstanceId, SuccessResults(rows));
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"MessageLog: {messageLog}");
    Assert.AreEqual(4, parameters.Get<int?>("@ReportedCount"));
    Assert.AreEqual(0, parameters.Get<int?>("@FailedCount"));
    Assert.AreEqual(0, parameters.Get<int?>("@FailedBatchCount"));
    Assert.AreEqual("Succeeded", parameters.Get<string?>("@ExecutionStatusCode"));

    var batchStatuses = (await conn.QueryAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID IN (SELECT DISTINCT BATCH_INSTANCE_ID FROM omd.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID IN (@A, @B))",
      new { A = (long)rows[2].MODULE_INSTANCE_ID, B = (long)rows[3].MODULE_INSTANCE_ID })).ToList();
    Assert.HasCount(2, batchStatuses);
    Assert.IsTrue(batchStatuses.All(s => s == "Succeeded"), "The child and grandchild Batch Instances are closed as well.");

    // The next run starts from the recorded load windows, in the child Batches too
    var (nextRows, next) = await CreateWithChildrenAsync(conn, BatchCode);
    Assert.AreEqual("Proceed", next.Get<string?>("@InternalProcessingStatusCode"), next.Get<string?>("@MessageLog"));
    Assert.HasCount(4, nextRows);
    Assert.IsTrue(nextRows.All(r => (string)r.PREVIOUS_END_VALUE == "2026-10-26 10:00:00.0000000"), "The previous end value comes from the recorded load window.");
  }

  [TestMethod]
  public async Task EndBatchModuleInstances_FailsParentBatches_WhenGrandchildModuleFails()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);
    var (rows, create) = await CreateWithChildrenAsync(conn, BatchCode);
    var rootInstanceId = create.Get<long>("@BatchInstanceId");

    var results = SuccessResults(rows.Take(3)).TrimEnd(']')
      + $@", {{ ""ModuleInstanceId"": {(long)rows[3].MODULE_INSTANCE_ID}, ""EventCode"": ""Failure"", ""EventDetail"": ""Grandchild failed"" }} ]";

    var parameters = EndWithChildrenParameters(rootInstanceId, results);
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);
    var messageLog = parameters.Get<string?>("@MessageLog");

    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), $"The bookkeeping itself succeeds. MessageLog: {messageLog}");
    Assert.AreEqual(1, parameters.Get<int?>("@FailedCount"));
    Assert.AreEqual(2, parameters.Get<int?>("@FailedBatchCount"), "The grandchild and the child Batch Instances fail.");
    Assert.AreEqual("Failed", parameters.Get<string?>("@ExecutionStatusCode"), "The failure travels up to the Batch Instance itself.");

    var rootModuleStatuses = (await conn.QueryAsync<string>(
      "SELECT EXECUTION_STATUS_CODE FROM omd.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID IN (@A, @B)", new { A = (long)rows[0].MODULE_INSTANCE_ID, B = (long)rows[1].MODULE_INSTANCE_ID })).ToList();
    Assert.IsTrue(rootModuleStatuses.All(s => s == "Succeeded"), "The Modules that succeeded keep their outcome.");
  }

  [TestMethod]
  public async Task CreateBatchModuleInstances_SkipsAbortedChildBatch_AndParentSucceeds()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    // A child Batch Instance that is still executing makes the child abort when it is opened as part of the parent
    var (_, childAlone) = await CreateAsync(conn, ChildBatchCode);
    Assert.AreEqual("Proceed", childAlone.Get<string?>("@InternalProcessingStatusCode"));

    var (rows, create) = await CreateWithChildrenAsync(conn, BatchCode);
    Assert.AreEqual(0, create.Get<int>("@ReturnCode"), create.Get<string?>("@MessageLog"));
    Assert.AreEqual("Proceed", create.Get<string?>("@InternalProcessingStatusCode"));
    Assert.HasCount(2, rows, "Only the Modules of the Batch itself are opened; the aborted child and its grandchild are skipped.");

    var batches = System.Text.Json.JsonDocument.Parse(create.Get<string>("@BatchInstancesJson")).RootElement;
    Assert.AreEqual(2, batches.GetArrayLength(), "The Batch and the aborted child Batch Instance; the grandchild is not opened.");
    Assert.AreEqual("Abort", batches[1].GetProperty("INTERNAL_PROCESSING_STATUS_CODE").GetString());
    Assert.AreEqual(0, batches[1].GetProperty("MODULE_COUNT").GetInt32());

    var parameters = EndWithChildrenParameters(create.Get<long>("@BatchInstanceId"), SuccessResults(rows));
    await conn.ExecuteAsync("[omd].[EndBatchModuleInstances]", parameters, commandType: System.Data.CommandType.StoredProcedure);
    Assert.AreEqual(0, parameters.Get<int>("@ReturnCode"), parameters.Get<string?>("@MessageLog"));
    Assert.AreEqual("Succeeded", parameters.Get<string?>("@ExecutionStatusCode"), "An aborted child does not fail the parent, as in omd.RunBatch.");
    Assert.AreEqual(0, parameters.Get<int?>("@FailedBatchCount"));
  }
}

// See references for test to code for assistants
// See: Direct_Framework\Stored Procedures\omd.CreateBatchModuleInstances.sql
// See: Direct_Framework\Stored Procedures\omd.EndBatchModuleInstances.sql
// See: Direct_Framework\Views\omd_processing.vw_BATCH_HIERARCHY.sql
