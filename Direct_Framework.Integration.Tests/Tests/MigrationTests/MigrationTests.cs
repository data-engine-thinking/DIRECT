using System.Diagnostics;

using IntegrationTests.Infrastructure;

using Microsoft.SqlServer.Dac;

namespace IntegrationTests.Tests.MigrationTests;

[TestClass]
public class MigrationTests : BaseTestContainer
{
  [TestInitialize]
  public async Task TestInitialize()
  {
    // todo: consider a variant that doesn't auto-deploy a dacpac on init?
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
    var outputDir = AppContext.BaseDirectory;

    // Traverse up to the project folder
    var projectDir = Directory.GetParent(outputDir)!.Parent!.Parent!.Parent!.Parent!.FullName;

    // 1. Deploy current version DACPAC
    // A dacpac has already been deployed by the init, so make sure this drops and redeploys a clean current
    var currentDacpacPath = Path.Combine(projectDir, "Releases.Direct_Framework", "current", "db", "Direct_Framework.dacpac");
    var dacServices = new DacServices(ContainerManager.MasterConnectionString);
    var currentDacpac = DacPackage.Load(currentDacpacPath);

    // drop database if it exists, else we might try to downgrade here...
    try
    {
      await using var dconn = new SqlConnection(ContainerManager.MasterConnectionString);
      await dconn.OpenAsync();
      await using var dcmd = new SqlCommand(@"
IF EXISTS (SELECT * FROM sys.databases WHERE name = 'Direct_Framework')
BEGIN
  ALTER DATABASE [Direct_Framework] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
  DROP DATABASE [Direct_Framework];
END
", dconn);

      await dcmd.ExecuteNonQueryAsync();
    }
    catch (Exception ex)
    {
      Assert.Fail($"Failed to drop existing database: {ex.Message}");
    }

    try
    {
      dacServices.Deploy(currentDacpac, "Direct_Framework", true);
    }
    catch (Exception ex)
    {
      Assert.Fail($"Failed to deploy **CURRENT** version DACPAC:\n{ex.Message}");
    }

    // 2. Run post-deploy script for current version if needed
    // TODO: change to call sqlcmd instead
    var postDeployFilePath = Path.Combine(
      projectDir, "Releases.Direct_Framework", "current", "db", "DeploymentScripts",
      "4-PostDacpacDeployment", "PostDacpacDeployment.sql");
    var postDeployScript = File.ReadAllText(postDeployFilePath);
    using (var conn = new SqlConnection(ContainerManager.DirectConnectionString))
    {
      await conn.OpenAsync();
      using var cmd = new SqlCommand(postDeployScript, conn);
      await cmd.ExecuteNonQueryAsync();
    }

    // n. TODO: Add sample data population here,
    // to ensure database has a representative state
    // before migrating to the next version.

    // 3. Run pre-deploy script for next version to prepare for the new dacpac
    // uses sqlcmd, as the called script then calls the version migrations using sqlcmd syntax
    // this mimics a full cd pipeline process
    var preDeployFilePath = Path.Combine(
      projectDir, "Releases.Direct_Framework", "next", "db", "DeploymentScripts",
      "1-PreDacpacDeployment", "PreDacpacDeployment.sql");

    ContainerManager.RunSqlCmdScript(preDeployFilePath, ContainerManager.DirectConnectionString);

    var preDeployScript = File.ReadAllText(postDeployFilePath);
    using (var conn = new SqlConnection(ContainerManager.DirectConnectionString))
    {
      await conn.OpenAsync();
      using var cmd = new SqlCommand(preDeployScript, conn);
      await cmd.ExecuteNonQueryAsync();
    }
    var predeployPath = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db", "DeploymentScripts", "1-PreDacpacDeployment", "PreDacpacDeployment.sql");

    ContainerManager.RunSqlCmdScript(predeployPath, ContainerManager.MasterConnectionString);

    // 3. Populate with sample/test data
    //var sampleDataScript = File.ReadAllText(Path.Combine("Migrations", "MigrationTestData", "SampleData_v1.sql"));
    //using (var conn = new SqlConnection(ConnectionString))
    //{
    //  await conn.OpenAsync();
    //  using var cmd = new SqlCommand(sampleDataScript, conn);
    //  await cmd.ExecuteNonQueryAsync();
    //}

    // 4. Deploy next version DACPAC (built from the database project)
    var nextDacpacPath = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db", "Direct_Framework.dacpac");
    var nextDacpac = DacPackage.Load(nextDacpacPath);
    try
    {
      dacServices.Deploy(nextDacpac, "Direct_Framework", true);
    }
    catch (Exception ex)
    {
      Assert.Fail($"Failed to deploy **NEXT** version DACPAC:\n{ex.Message}");
    }

    // n. Run post deploy script for the next version if needed


    //// n. Run more comprehensive asserts on migration success (check schema, data, etc.)
    //using var conn = new SqlConnection(ConnectionString);
    //await conn.OpenAsync();
    //using var cmd = new SqlCommand("SELECT COUNT(*) FROM sys.schemas WHERE name = 'omd'", conn);
    //var res = await cmd.ExecuteScalarAsync();
    //var count = Convert.ToInt32(res);
    //Assert.IsTrue(count > 0, "Schema 'omd' should exist after migration.");
  }
}
