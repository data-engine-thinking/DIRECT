using System.Diagnostics;

using DotNet.Testcontainers.Builders;
using DotNet.Testcontainers.Configurations;

using Microsoft.SqlServer.Dac;
using Microsoft.SqlServer.Dac.Model;

using Testcontainers.MsSql;

namespace IntegrationTests.Infrastructure;

/// <summary>
/// Manages the lifecycle of a test-class scoped SQL Server container for integration tests
/// Uses Podman (as default) with Microsoft SQL Server Linux images through the `Testcontainers`
/// and the `DotNet.Testcontainers` libraries.
/// </summary>
public class SqlServerContainerManager
{
  //private string? _directVersion;
  private MsSqlContainer? _container;
  private string? _directConnectionString;
  private string? _masterConnectionString;

  /// <summary>
  /// Gets the master database connection string for the SQL Server container
  /// </summary>
  public string MasterConnectionString
  {
    get
    {
      if (_masterConnectionString is null)
        throw new InvalidOperationException("Container not initialized. Call InitializeAsync first.");
      return _masterConnectionString!;
    }
  }

  /// <summary>
  /// Gets the master database connection string for the SQL Server container
  /// </summary>
  public string DirectConnectionString
  {
    get
    {
      if (_directConnectionString is null)
        throw new InvalidOperationException("Container not initialized. Call InitializeAsync first.");
      return _directConnectionString!;
    }
  }

  /// <summary>
  /// Initializes the SQL Server container and deploys the database schema.
  /// <paramref name="version"/> can be:
  ///   "next"     - the locally-built dacpac under Releases.Direct_Framework/next/
  ///   "current"  - the most-recent published GitHub release (downloaded + cached on first use)
  ///   "vX.Y"     - a specific published release tag
  /// </summary>
  public async Task InitializeAsync(string? version = "next")
  {
    version = string.IsNullOrWhiteSpace(version) ? "next" : version;

    // Create the container for Linux SQL Server
    _container = new MsSqlBuilder()
        .WithImage("mcr.microsoft.com/mssql/server:2022-latest")
        .WithPassword("P@ssword123!")
        .WithEnvironment("ACCEPT_EULA", "Y")
        .WithEnvironment("MSSQL_SA_PASSWORD", "P@ssword123!")
        .WithPortBinding(0, 1433) // Random host port
        .WithCleanUp(true)
        .Build();

    // Start the container
    Console.WriteLine($"Starting SQL Server Linux container with Podman");
    Console.WriteLine($"Image: {_container.Image}");

    await _container.StartAsync();
    _masterConnectionString = _container.GetConnectionString();

    var hostPort = _container.GetMappedPublicPort(1433);
    Console.WriteLine($"SQL Server container started on host port: {hostPort}");
    Console.WriteLine($"Container ID: {_container.Id}");
    Console.WriteLine($"Initial connection string: {_masterConnectionString}");

    // Wait for SQL Server to be fully ready for connections
    await WaitForSqlServerReadyAsync();

    // Deploy the database schema
    Console.WriteLine($"Deploying DIRECT DACPAC version: '{version}'");
    await DeployDacpacAsync(version);

    // also add connection string to point to Direct_Framework database
    _directConnectionString = _masterConnectionString.Replace("Database=master", "Database=Direct_Framework");
    Console.WriteLine($"_directConnectionString : {_directConnectionString}");
  }

  /// <summary>
  /// Disposes the SQL Server container
  /// </summary>
  public async Task DisposeAsync()
  {
    if (_container is not null)
    {
      await _container.DisposeAsync();
      _container = null;
      _masterConnectionString = null;
      _directConnectionString = null;
      Console.WriteLine("SQL Server container disposed.");
    }
  }

  /// <summary>
  /// Resets the database to a cleaner state by deleting data and
  /// resetting all tables and identities. This will restore state
  /// to clean as long as nothing else, like the metadata tables, has changed.
  /// For a full reset, drop and redeploy the dacpac
  /// </summary>
  public async Task ResetDatabaseAsync()
  {
    if (_container is null)
      throw new InvalidOperationException("Container not initialized.");

    // Reset the database data
    // delete in fk dependency order to avoid constraint violations
    using var connection = new SqlConnection(_directConnectionString);
    await connection.OpenAsync();
    using var command = new SqlCommand(
@"
DELETE FROM omd.BATCH_HIERARCHY;
DELETE FROM omd.SOURCE_CONTROL;
DELETE FROM omd.EVENT_LOG;
DELETE FROM omd.BATCH_MODULE;
DELETE FROM omd.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID <> 0;
DELETE FROM omd.MODULE WHERE MODULE_ID <> 0;
DELETE FROM omd.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID <> 0;
DELETE FROM omd.BATCH WHERE BATCH_ID <> 0;
", connection);

    Console.WriteLine("Database data reset completed. (1/2)");

    // reset identity seeds for all tables with sequence identifiers
    using var resetCommand = new SqlCommand(
@"
DBCC CHECKIDENT('omd.BATCH', RESEED, 1);
DBCC CHECKIDENT('omd.BATCH_INSTANCE', RESEED, 1);
DBCC CHECKIDENT('omd.EVENT_LOG', RESEED, 1);
DBCC CHECKIDENT('omd.MODULE', RESEED, 1);
DBCC CHECKIDENT('omd.MODULE_INSTANCE', RESEED, 1);
DBCC CHECKIDENT('omd.SOURCE_CONTROL', RESEED, 1);
", connection);
    await resetCommand.ExecuteNonQueryAsync();

    await connection.CloseAsync();

    Console.WriteLine("Database identity reseeding completed. (2/2)");
  }

  /// <summary>
  /// Populate the DIRECT database with sample data for testing purposes.
  /// Population can be done in 2 main ways, by table row insertion, and
  /// by running the corresponding stored procedure.
  /// as we might be testing changes in stored procedures, this process uses
  /// direct inserts instead. This might show some additional scenarios with
  /// improvement potential
  /// </summary>
  /// <exception cref="InvalidOperationException"></exception>
  public async Task PopulateDatabaseAsync()
  {
    // add some initial data to the database
    if (_container is null)
      throw new InvalidOperationException("Container not initialized.");

    int moduleId;
    int batchId;
    int moduleInstanceId;
    //int batchInstanceId;

    var batch = new
    {
      BatchCode = "b_INGESTION_EXAMPLE",
      BatchType = "Ingestion",
      FrequencyCode = "On-demand",
      ActiveIndicator = "Y",
      BatchDescription = "Example batch for ingestion",
    };
    // insert the batch into the database
    using var connection = new SqlConnection(_directConnectionString);
    await connection.OpenAsync();
    using var command = new SqlCommand(
        @"INSERT INTO omd.BATCH (BATCH_CODE, BATCH_TYPE, FREQUENCY_CODE, ACTIVE_INDICATOR, BATCH_DESCRIPTION)
          VALUES (@BatchCode, @BatchType, @FrequencyCode, @ActiveIndicator, @BatchDescription);
          SELECT SCOPE_IDENTITY();", connection);

    command.Parameters.AddWithValue("@BatchCode", batch.BatchCode);
    command.Parameters.AddWithValue("@BatchType", batch.BatchType);
    command.Parameters.AddWithValue("@FrequencyCode", batch.FrequencyCode);
    command.Parameters.AddWithValue("@ActiveIndicator", batch.ActiveIndicator);
    command.Parameters.AddWithValue("@BatchDescription", batch.BatchDescription);

    // Execute the insert and get the identity value
    var result = await command.ExecuteScalarAsync();
    batchId = Convert.ToInt32(result);

    Console.WriteLine($"Inserted batch: {batch.BatchCode} with id: {batchId}");

    var module = new
    {
      ModuleCode = "M_INGESTION_EXAMPLE",
      ModuleType = "Ingestion",
      DataObjectSource = "SourceObject",
      DataObjectTarget = "TargetObject",
      AreaCode = "STG",
      FrequencyCode = "On-demand",
      ModuleDescription = "Example module for ingestion",
      ActiveIndicator = "Y",
      Executable = "SELECT SYSUTCDATETIME() AS NowUtc"
    };
    // check if a module with the same code already exists
    using var checkCommand = new SqlCommand(
        "SELECT COUNT(*) FROM omd.MODULE WHERE MODULE_CODE = @ModuleCode", connection);
    checkCommand.Parameters.AddWithValue("@ModuleCode", module.ModuleCode);
    var exists = (int?)await checkCommand.ExecuteScalarAsync() > 0;
    if (exists)
    {
      Console.WriteLine($"Module with code {module.ModuleCode} already exists. Skipping insert.");
      // get the id of the existing module
      using var getModuleIdCommand = new SqlCommand(
          "SELECT MODULE_ID FROM omd.MODULE WHERE MODULE_CODE = @ModuleCode", connection);
      getModuleIdCommand.Parameters.AddWithValue("@ModuleCode", module.ModuleCode);
      moduleId = (int?)await getModuleIdCommand.ExecuteScalarAsync() ?? 0;
    }
    else
    {
      // insert the module into the database and get the identity value
      using var moduleCommand = new SqlCommand(
          @"INSERT INTO omd.MODULE (MODULE_CODE, MODULE_TYPE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, AREA_CODE, FREQUENCY_CODE, MODULE_DESCRIPTION, ACTIVE_INDICATOR, EXECUTABLE) 
                VALUES (@ModuleCode, @ModuleType, @DataObjectSource, @DataObjectTarget, @AreaCode, @FrequencyCode, @ModuleDescription, @ActiveIndicator, @Executable);
                SELECT SCOPE_IDENTITY();", connection);
      moduleCommand.Parameters.AddWithValue("@ModuleCode", module.ModuleCode);
      moduleCommand.Parameters.AddWithValue("@ModuleType", module.ModuleType);
      moduleCommand.Parameters.AddWithValue("@DataObjectSource", module.DataObjectSource);
      moduleCommand.Parameters.AddWithValue("@DataObjectTarget", module.DataObjectTarget);
      moduleCommand.Parameters.AddWithValue("@AreaCode", module.AreaCode);
      moduleCommand.Parameters.AddWithValue("@FrequencyCode", module.FrequencyCode);
      moduleCommand.Parameters.AddWithValue("@ModuleDescription", module.ModuleDescription);
      moduleCommand.Parameters.AddWithValue("@ActiveIndicator", module.ActiveIndicator);
      moduleCommand.Parameters.AddWithValue("@Executable", module.Executable);
      var moduleResult = await moduleCommand.ExecuteScalarAsync();
      moduleId = Convert.ToInt32(moduleResult);
      Console.WriteLine($"Inserted module: {module.ModuleCode} with id: {moduleId}");
    }

    var moduleInstance = new
    {
      ModuleId = moduleId,
      BatchInstanceId = 0,
      StartTimestamp = DateTime.UtcNow,
      EndTimestamp = (DateTime?)null,
      InternalProcessingCode = "Proceed",
      NextRunStatusCode = "Proceed",
      ExecutionStatusCode = "Succeeded",
      ExecutionContext = (string?)null,
      RowsInput = (long?)10,
      RowsInserted = (long?)10,
      RowsUpdated = (long?)0,
      RowsDeleted = (long?)0,
      RowsDiscarded = (long?)0,
      RowsRejected = (long?)0,
      ExecutedCodeChecksum = new byte[64]
    };

    // insert the module instance into the database and get the identity value
    using var moduleInstanceCommand = new SqlCommand(
        @"INSERT INTO omd.MODULE_INSTANCE (MODULE_ID, BATCH_INSTANCE_ID, START_TIMESTAMP, END_TIMESTAMP, INTERNAL_PROCESSING_CODE, NEXT_RUN_STATUS_CODE, EXECUTION_STATUS_CODE, EXECUTION_CONTEXT, ROWS_INPUT, ROWS_INSERTED, ROWS_UPDATED, ROWS_DELETED, ROWS_DISCARDED, ROWS_REJECTED, EXECUTED_CODE_CHECKSUM) 
              VALUES (@ModuleId, @BatchInstanceId, @StartTimestamp, @EndTimestamp, @InternalProcessingCode, @NextRunStatusCode, @ExecutionStatusCode, @ExecutionContext, @RowsInput, @RowsInserted, @RowsUpdated, @RowsDeleted, @RowsDiscarded, @RowsRejected, @ExecutedCodeChecksum);
              SELECT SCOPE_IDENTITY();", connection);
    moduleInstanceCommand.Parameters.AddWithValue("@ModuleId", moduleInstance.ModuleId);
    moduleInstanceCommand.Parameters.AddWithValue("@BatchInstanceId", 0);
    moduleInstanceCommand.Parameters.AddWithValue("@StartTimestamp", moduleInstance.StartTimestamp);
    moduleInstanceCommand.Parameters.AddWithValue("@EndTimestamp", moduleInstance.EndTimestamp ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@InternalProcessingCode", moduleInstance.InternalProcessingCode);
    moduleInstanceCommand.Parameters.AddWithValue("@NextRunStatusCode", moduleInstance.NextRunStatusCode);
    moduleInstanceCommand.Parameters.AddWithValue("@ExecutionStatusCode", moduleInstance.ExecutionStatusCode);
    moduleInstanceCommand.Parameters.AddWithValue("@ExecutionContext", moduleInstance.ExecutionContext ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsInput", moduleInstance.RowsInput ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsInserted", moduleInstance.RowsInserted ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsUpdated", moduleInstance.RowsUpdated ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsDeleted", moduleInstance.RowsDeleted ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsDiscarded", moduleInstance.RowsDiscarded ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@RowsRejected", moduleInstance.RowsRejected ?? (object)DBNull.Value);
    moduleInstanceCommand.Parameters.AddWithValue("@ExecutedCodeChecksum", moduleInstance.ExecutedCodeChecksum ?? (object)DBNull.Value);
    var moduleInstanceResult = await moduleInstanceCommand.ExecuteScalarAsync();
    moduleInstanceId = Convert.ToInt32(moduleInstanceResult);
    Console.WriteLine($"Inserted module instance with id: {moduleInstanceId}");
  }

  /// <summary>
  /// Resolved release info for the most recent <c>InitializeAsync(version)</c> call where the
  /// version was a published release tag (or "current"). Null when the active deploy is "next"
  /// or a local override. Used by MigrationTests to locate the previous release's
  /// PostDacpacDeployment.sql.
  /// </summary>
  public ResolvedRelease? ResolvedBaseline { get; private set; }

  /// <summary>
  /// Standard deploy options used for both initial deploy and migration deploy. Centralized so
  /// the migration test runs against the same options the container manager uses.
  /// </summary>
  public static DacDeployOptions DefaultDeployOptions() => new()
  {
    BlockOnPossibleDataLoss = false,
    CreateNewDatabase = true,
    DropObjectsNotInSource = true,
    VerifyDeployment = true,
    CommandTimeout = 120,
  };

  private async Task DeployDacpacAsync(string version, bool dropExistingDb = true)
  {
    if (_container is null)
      throw new InvalidOperationException("Container not initialized.");

    var dacpacPath = await FindDacpacPathAsync(version).ConfigureAwait(false);

    if (!File.Exists(dacpacPath))
    {
      throw new FileNotFoundException(
          $"DACPAC not found at: {dacpacPath}. " +
          "Ensure the Direct_Framework project is built before running tests.");
    }

    // If dropExisting is true, we will drop the existing database
    if (dropExistingDb)
    {
      Console.WriteLine("Dropping existing Direct_Framework database...");
      using var connection = new SqlConnection(_masterConnectionString);
      await connection.OpenAsync();
      using var command = new SqlCommand("DROP DATABASE IF EXISTS Direct_Framework", connection);
      await command.ExecuteNonQueryAsync();
      Console.WriteLine("Existing database dropped.");
    }

    Console.WriteLine($"Deploying DACPAC '{version}' from: {dacpacPath}");
    Console.WriteLine($"Target connection: {_masterConnectionString}");

    try
    {
      var dacpac = DacPackage.Load(dacpacPath);
      Console.WriteLine($"DACPAC loaded successfully: {dacpac.Name}");
      Console.WriteLine($"DACPAC version: {dacpac.Version}");

      var dacServices = new DacServices(_masterConnectionString);

      Console.WriteLine("Starting DACPAC deployment...");
      await Task.Run(() => dacServices.Deploy(dacpac, "Direct_Framework", upgradeExisting: true, DefaultDeployOptions()));
      Console.WriteLine("DACPAC deployment completed successfully");

      // Verify deployment by checking what was actually created
      await VerifyDeploymentAsync();
    }
    catch (Exception ex)
    {
      Console.WriteLine($"DACPAC deployment failed: {ex.GetType().Name}: {ex.Message}");
      if (ex.InnerException is not null)
      {
        Console.WriteLine($"Inner exception: {ex.InnerException.GetType().Name}: {ex.InnerException.Message}");
      }
      throw;
    }
  }

  /// <summary>
  /// Resolve the path of the Direct_Framework.dacpac for the requested version.
  ///   "next"     -> local build output under Releases.Direct_Framework/next/db/
  ///   "current"  -> Releases.Direct_Framework/current/ override if present, else latest GitHub release
  ///   "vX.Y..."  -> the matching GitHub release tag
  /// </summary>
  public async Task<string> FindDacpacPathAsync(string version)
  {
    var outputDir = AppContext.BaseDirectory;
    var projectDir = Directory.GetParent(outputDir)!.Parent!.Parent!.Parent!.Parent!.FullName;

    if (string.Equals(version, "next", StringComparison.OrdinalIgnoreCase))
    {
      var localNext = Path.Combine(projectDir, "Releases.Direct_Framework", "next", "db", "Direct_Framework.dacpac");
      if (!File.Exists(localNext))
        throw new FileNotFoundException(
          $"Could not locate 'next' Direct_Framework.dacpac at {localNext}. " +
          "Build the Direct_Framework project before running tests.");
      Console.WriteLine($">>> Resolved baseline: tag=next dacpac={localNext}");
      ResolvedBaseline = null;
      return localNext;
    }

    if (string.Equals(version, "current", StringComparison.OrdinalIgnoreCase))
    {
      // Local override path takes precedence (offline / power-user scenario)
      var localOverride = Path.Combine(projectDir, "Releases.Direct_Framework", "current", "db", "Direct_Framework.dacpac");
      if (File.Exists(localOverride))
      {
        Console.WriteLine($">>> Resolved baseline: tag=current(local-override) dacpac={localOverride}");
        ResolvedBaseline = new ResolvedRelease(
          Tag: "local-override",
          RootDir: Path.Combine(projectDir, "Releases.Direct_Framework", "current", "db"),
          HasDeploymentScripts: Directory.Exists(Path.Combine(projectDir, "Releases.Direct_Framework", "current", "db", "DeploymentScripts")));
        return localOverride;
      }
      // Otherwise fall through to "latest published release"
      version = "latest";
    }

    var resolved = await ReleaseAssetResolver.EnsureReleaseAsync(version).ConfigureAwait(false);
    var dacpac = Path.Combine(resolved.RootDir, "Direct_Framework.dacpac");
    if (!File.Exists(dacpac))
      throw new FileNotFoundException($"Resolved release {resolved.Tag} did not contain Direct_Framework.dacpac at {dacpac}");
    Console.WriteLine($">>> Resolved baseline: tag={resolved.Tag} dacpac={dacpac} hasScripts={resolved.HasDeploymentScripts}");
    ResolvedBaseline = resolved;
    return dacpac;
  }

  /// <summary>
  /// Waits for SQL Server to be fully ready to accept connections and execute commands
  /// </summary>
  private async Task WaitForSqlServerReadyAsync()
  {
    const int maxRetries = 30;
    const int delayMs = 5000;

    for (int i = 0; i < maxRetries; i++)
    {
      try
      {
        using var connection = new SqlConnection(_masterConnectionString);
        await connection.OpenAsync();

        // Try to execute a simple query to ensure SQL Server is fully ready
        using var command = new SqlCommand("SELECT 1", connection);
        await command.ExecuteScalarAsync();

        Console.WriteLine($"SQL Server is ready after {i + 1} attempts");
        return;
      }
      catch (Exception ex)
      {
        Console.WriteLine($"Attempt {i + 1}/{maxRetries}: SQL Server not ready yet - {ex.GetType().Name}: {ex.Message}");

        if (i == maxRetries - 1)
        {
          throw new InvalidOperationException($"SQL Server did not become ready after {maxRetries} attempts", ex);
        }

        await Task.Delay(delayMs);
      }
    }
  }

  /// <summary>
  /// Verifies that the DACPAC deployment was successful by checking for expected schemas and objects
  /// </summary>
  private async Task VerifyDeploymentAsync()
  {
    try
    {
      using var connection = new SqlConnection(_masterConnectionString);
      await connection.OpenAsync();

      // Check non-system databases
      using var dbCommand = new SqlCommand(@"
        SELECT [name]
        FROM [sys].[databases]
        WHERE [name] NOT IN ('master', 'tempdb', 'model', 'msdb')
      ", connection);
      using var dbReader = await dbCommand.ExecuteReaderAsync();
      Console.WriteLine("Databases found:");
      while (await dbReader.ReadAsync())
      {
        Console.WriteLine($"  - {dbReader.GetString(0)}");
      }
      dbReader.Close();

      // Switch to the Direct_Framework database
      connection.ChangeDatabase("Direct_Framework");

      // Check schemas
      using var schemaCommand = new SqlCommand(@"
        SELECT name
        FROM sys.schemas
        WHERE name IN ('omd', 'omd_metadata', 'omd_processing', 'omd_reporting')
      ", connection);
      using var schemaReader = await schemaCommand.ExecuteReaderAsync();
      Console.WriteLine("Expected schemas found:");
      while (await schemaReader.ReadAsync())
      {
        Console.WriteLine($"  - {schemaReader.GetString(0)}");
      }
      schemaReader.Close();

      // Check for the specific stored procedure
      using var procCommand = new SqlCommand(@"
        SELECT s.name as schema_name, p.name as procedure_name
        FROM sys.procedures p
        JOIN sys.schemas s ON p.schema_id = s.schema_id
        WHERE s.name = 'omd' AND p.name = 'GetBatch'
      ", connection);
      using var procReader = await procCommand.ExecuteReaderAsync();
      Console.WriteLine("omd.GetBatch procedure check:");
      if (await procReader.ReadAsync())
      {
        Console.WriteLine($"  Found: {procReader.GetString(0)}.{procReader.GetString(1)}");
      }
      else
      {
        Console.WriteLine("  NOT FOUND");
      }
      procReader.Close();

      // List all procedures in omd schema
      using var allProcCommand = new SqlCommand(@"
        SELECT s.name as schema_name, p.name as procedure_name
        FROM sys.procedures p
        JOIN sys.schemas s ON p.schema_id = s.schema_id
        WHERE s.name = 'omd'", connection);
      using var allProcReader = await allProcCommand.ExecuteReaderAsync();
      Console.WriteLine("All procedures in omd schema:");
      while (await allProcReader.ReadAsync())
      {
        Console.WriteLine($"  - {allProcReader.GetString(0)}.{allProcReader.GetString(1)}");
      }
    }
    catch (Exception ex)
    {
      Console.WriteLine($"Verification failed: {ex.Message}");
    }
  }

  /// <summary>
  /// Start an external sqlcmd process to run a stand-alone SQL script file. Mimics the way a
  /// CD pipeline runs pre/post-dacpac scripts (sqlcmd is required for <c>:r ./Migrations/...</c>
  /// includes used by PreDacpacDeployment.sql).
  ///
  /// Streams stdout/stderr live so long-running migrations are visible. On non-zero exit,
  /// the thrown exception includes the script path and the last ~50 lines of merged output.
  /// </summary>
  public void RunSqlCmdScript(string scriptPath, string ConnectionString)
  {
    var builder = new SqlConnectionStringBuilder(ConnectionString);

    using var process = new Process
    {
      StartInfo = new ProcessStartInfo
      {
        FileName = "sqlcmd",
        // -b: exit on error, -I: enable QUOTED_IDENTIFIER, -r 1: errors+messages to stderr
        Arguments = $"-S {builder.DataSource} -d {builder.InitialCatalog} -U {builder.UserID} -P {builder.Password} -i \"{scriptPath}\" -b -I -r 1",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        CreateNoWindow = true,
        WorkingDirectory = Path.GetDirectoryName(scriptPath)
      }
    };

    var tail = new System.Collections.Generic.Queue<string>(64);
    void Capture(string prefix, string? line)
    {
      if (line is null) return;
      var rendered = $"  [sqlcmd:{prefix}] {line}";
      Console.WriteLine(rendered);
      lock (tail)
      {
        tail.Enqueue(rendered);
        while (tail.Count > 50) tail.Dequeue();
      }
    }

    process.OutputDataReceived += (_, e) => Capture("out", e.Data);
    process.ErrorDataReceived += (_, e) => Capture("err", e.Data);

    Console.WriteLine($"[sqlcmd] running {scriptPath}");
    process.Start();
    process.BeginOutputReadLine();
    process.BeginErrorReadLine();
    process.WaitForExit();

    if (process.ExitCode != 0)
    {
      string snippet;
      lock (tail) snippet = string.Join(Environment.NewLine, tail);
      throw new InvalidOperationException(
        $"sqlcmd failed (exit {process.ExitCode}) running {scriptPath}{Environment.NewLine}--- last output ---{Environment.NewLine}{snippet}");
    }
  }


}
