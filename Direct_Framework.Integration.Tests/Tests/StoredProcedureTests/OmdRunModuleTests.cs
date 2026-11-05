using IntegrationTests.Infrastructure;

namespace IntegrationTests.Tests.StoredProcedureTests;

[TestClass]
public class OmdRunModuleTests : BaseTestContainer
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
  /// Regression: running a module code that does not exist (with auto-registration off) failed
  /// without leaving any trace in the log tables - no module instance exists for it, and the only
  /// event log write sat in the CATCH block, which a soft failure never reaches. The failure must
  /// be visible in omd.EVENT_LOG, naming the module code.
  /// </summary>
  [TestMethod]
  public async Task RunModule_UnknownModuleCode_WritesAnEventLogEntry()
  {
    using var conn = new SqlConnection(ContainerManager.DirectConnectionString);

    // The default is auto-registration, which would create the module instead of failing.
    await conn.ExecuteAsync(
      "UPDATE [omd_metadata].[FRAMEWORK_METADATA] SET [VALUE] = 'N' WHERE [CODE] = 'AUTO_REGISTER_MODULES';");

    var parameters = new DynamicParameters();
    parameters.Add("@ModuleCode", "m_DOES_NOT_EXIST");
    parameters.Add("@Debug", "N");
    parameters.Add("@SuccessIndicator", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: 1);
    parameters.Add("@MessageLog", dbType: System.Data.DbType.String, direction: System.Data.ParameterDirection.Output, size: -1);

    await conn.ExecuteAsync(
      "EXEC [omd].[RunModule] @ModuleCode = @ModuleCode, @Debug = @Debug, @SuccessIndicator = @SuccessIndicator OUTPUT, @MessageLog = @MessageLog OUTPUT",
      parameters);

    var successIndicator = parameters.Get<string>("@SuccessIndicator");
    Assert.AreEqual("N", successIndicator);

    var eventCount = await conn.ExecuteScalarAsync<int>(
      "SELECT COUNT(*) FROM [omd].[EVENT_LOG] WHERE [EVENT_DETAIL] LIKE '%m_DOES_NOT_EXIST%';");

    Assert.IsTrue(eventCount > 0, "A failed run of an unknown module code must appear in omd.EVENT_LOG.");
  }
}
