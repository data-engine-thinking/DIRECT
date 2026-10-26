/**
 * @procedure [omd].[CreateBatchModuleInstances]
 * @description
 *   Open a Batch Instance and the Module Instances of all Modules in the Batch in one call,
 *   and return the Modules that are ready to run as a result set.
 *
 *   This procedure supports external orchestration, where the code that moves the data runs on another
 *   engine (for example a Microsoft Fabric Warehouse) while DIRECT keeps the bookkeeping. It performs the
 *   control-side half of [omd].[RunBatch]: the Batch Instance is created and evaluated, and for every Module
 *   in the Batch a Module Instance is created and evaluated. Nothing is executed. The orchestrator runs the
 *   returned executables and the returned rollback statements on the target engine, and reports back through
 *   [omd].[EndBatchModuleInstances].
 *
 *   The Modules of the Batch are processed in [SEQUENCE] order. The result set contains one row per Module
 *   with the Module Instance Id, the executable, the previous load window end value (the start of the next load
 *   window), the Internal Processing Status Code of the Module Instance ('Proceed', 'Cancel' or 'Abort') and,
 *   when the Module Instance evaluation decided to roll back earlier failed instances, the rollback statement
 *   that the orchestrator must run on the target engine before the executable.
 *
 *   When the Batch evaluation ends in 'Abort' or 'Cancel', no Module Instances are created and the result set is
 *   empty. A Batch without Modules (a parent Batch that only groups child Batches) also returns an empty result set;
 *   the Batch Instance Id is returned so that the child Batches can be run with it as parent.
 *
 * @package DIRECT Framework
 * @version 2.2.0
 * @see https://github.com/data-engine-thinking/DIRECT
 *
 * @param {NVARCHAR(500)}  @BatchCode                     [in]  (required)
 *   The Batch Code of the Batch to run.
 * @param {BIGINT}         @ParentBatchInstanceId         [in]  (optional, default=0)
 *   The Batch Instance Id of the parent Batch, when the Batch runs as a child Batch.
 * @param {NVARCHAR(4000)} @ExecutionContext              [in]  (optional, default='')
 *   Free-format execution context, for example the pipeline run id of the orchestrator.
 * @param {NVARCHAR(1000)} @ModuleInstanceIdColumnName    [in]  (optional, default='MODULE_INSTANCE_ID')
 *   The column that holds the Module Instance Id in the target data objects, used to build rollback statements.
 * @param {NVARCHAR(100)}  @DefaultStartValue             [in]  (optional, default='1900-01-01')
 *   The load window start value returned for a Module that has no load window recorded yet.
 * @param {NVARCHAR(4000)} @ConsistencyModuleTypeList     [in]  (optional, default=NULL)
 *   Comma-separated list of Module Types for which a consistency timestamp is calculated over the Module's
 *   source data objects, using [omd].[GetConsistencyTimestamp] on the information in the repository only.
 *   NULL means no consistency timestamp is calculated.
 * @param {NVARCHAR(128)}  @SourceTimestampColumn         [in]  (optional, default='LOAD_DATETIME')
 *   Passed to [omd].[GetConsistencyTimestamp].
 * @param {CHAR(1)}        @ReturnResultSet               [in]  (optional, default='Y')
 *   'N' suppresses the result set; the rows are then only available through @ResultJson. Callers that cannot
 *   consume a result set next to output parameters (for example a pipeline Script activity) use this.
 * @param {CHAR(1)}        @IncludeChildBatches           [in]  (optional, default='N')
 *   'Y' also opens the active child Batches of the Batch (omd.BATCH_HIERARCHY), recursively and in sequence,
 *   after the Modules of the Batch itself, with the Batch Instance as parent. The rows of all Batches are
 *   returned in run order: the Modules of a Batch first, then those of its child Batches. A child Batch that
 *   evaluates to 'Abort' or 'Cancel' is skipped with its own children. This mirrors omd.RunBatch.
 * @param {CHAR(1)}        @Debug                         [in]  (optional, default='N')
 *   Enables debug logging.
 * @param {NVARCHAR(MAX)}  @ResultJson                    [out] (optional)
 *   The result set as a JSON array (FOR JSON PATH), '[]' when there are no rows.
 * @param {NVARCHAR(MAX)}  @BatchInstancesJson            [out] (optional)
 *   JSON array with the Batch Instances that were created, in run order: BATCH_INSTANCE_ID, BATCH_CODE,
 *   PARENT_BATCH_INSTANCE_ID, LEVEL (0 for the Batch itself), INTERNAL_PROCESSING_STATUS_CODE and MODULE_COUNT.
 * @param {BIGINT}         @BatchInstanceId               [out] (optional)
 *   The identifier of the created Batch Instance.
 * @param {NVARCHAR(100)}  @InternalProcessingStatusCode  [out] (optional)
 *   The Internal Processing Status Code of the Batch Instance after evaluation ('Proceed', 'Cancel' or 'Abort').
 * @param {CHAR(1)}        @SuccessIndicator              [out] (optional)
 *   'Y' if the operation completed successfully; otherwise 'N'.
 * @param {NVARCHAR(MAX)}  @MessageLog                    [out] (optional)
 *   Structured JSON-format log for diagnostics.
 *
 * @returns {INT} Return code: 0 = success, -1 = failure, -2 = unhandled error.
 *
 * @resultset One row per Module in the Batch, in [SEQUENCE] order:
 *   - BATCH_INSTANCE_ID: The Batch Instance Id.
 *   - BATCH_CODE: The Batch Code.
 *   - MODULE_INSTANCE_ID: The Module Instance Id created for the Module.
 *   - MODULE_ID: The Module Id.
 *   - MODULE_CODE: The Module Code.
 *   - MODULE_TYPE: The Module Type.
 *   - AREA_CODE: The Area Code of the Module.
 *   - SEQUENCE: The position of the Module in the Batch.
 *   - EXECUTABLE: The executable registered for the Module.
 *   - DATA_OBJECT_SOURCE: The source data object(s) of the Module.
 *   - DATA_OBJECT_TARGET: The target data object of the Module.
 *   - PREVIOUS_END_VALUE: The end value of the last recorded load window, or @DefaultStartValue.
 *   - INTERNAL_PROCESSING_STATUS_CODE: 'Proceed', 'Cancel' or 'Abort'. Only 'Proceed' rows are to be executed.
 *   - ROLLBACK_STATEMENT: The rollback statement to run on the target engine before the executable, or NULL.
 *   - CONSISTENCY_DATETIME: The consistency timestamp as 'yyyy-MM-dd HH:mm:ss.fffffff', or NULL.
 *
 * @lineage
 * - reads:
 *     table [omd].[BATCH]
 *     table [omd].[BATCH_MODULE]
 *     table [omd].[MODULE]
 *     function [omd].[GetModuleLoadWindowValue]
 *     function [omd_metadata].[GetFrameworkVersion]
 *     function [omd_metadata].[GetTimestampString]
 *     function [omd_metadata].[GetSettingFlag]
 * - writes:
 *     procedure [omd].[CreateBatchInstance]
 *     procedure [omd].[BatchEvaluation]
 *     procedure [omd].[CreateModuleInstance]
 *     procedure [omd].[ModuleEvaluation]
 *     procedure [omd].[GetConsistencyTimestamp]
 *     procedure [omd].[UpdateBatchInstance]
 *     procedure [omd].[InsertIntoEventLog]
 * - utilities:
 *     function [omd].[AddLogMessage]
 *     procedure [omd].[PrintMessageLog]
 *
 * @example
 * DECLARE @BatchInstanceId BIGINT,
 *         @InternalProcessingStatusCode NVARCHAR(100),
 *         @SuccessIndicator CHAR(1),
 *         @MessageLog NVARCHAR(MAX);
 * EXEC [omd].[CreateBatchModuleInstances]
 *   @BatchCode = N'b_INGESTION_EXAMPLE',
 *   @ExecutionContext = N'pipeline run 7f3c...',
 *   @ConsistencyModuleTypeList = N'PIT,Snapshot',
 *   @Debug = 'Y',
 *   @BatchInstanceId = @BatchInstanceId OUTPUT,
 *   @InternalProcessingStatusCode = @InternalProcessingStatusCode OUTPUT,
 *   @SuccessIndicator = @SuccessIndicator OUTPUT,
 *   @MessageLog = @MessageLog OUTPUT;
 * EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
 */

CREATE PROCEDURE [omd].[CreateBatchModuleInstances]
(
   -- Mandatory parameters
   @BatchCode                     NVARCHAR(500)   = NULL
   -- Optional parameters
  ,@ParentBatchInstanceId         BIGINT          = 0
  ,@ExecutionContext              NVARCHAR(4000)  = N''
  ,@ModuleInstanceIdColumnName    NVARCHAR(1000)  = N'MODULE_INSTANCE_ID'
  ,@DefaultStartValue             NVARCHAR(100)   = N'1900-01-01'
  ,@ConsistencyModuleTypeList     NVARCHAR(4000)  = NULL
  ,@SourceTimestampColumn         NVARCHAR(128)   = N'LOAD_DATETIME'
  ,@ReturnResultSet               CHAR(1)         = 'Y'
  ,@IncludeChildBatches           CHAR(1)         = 'N'
  ,@Debug                         CHAR(1)         = 'N'
   -- Output parameters
  ,@ResultJson                    NVARCHAR(MAX)   = NULL  OUTPUT
  ,@BatchInstancesJson            NVARCHAR(MAX)   = NULL  OUTPUT
  ,@BatchInstanceId               BIGINT          = NULL  OUTPUT
  ,@InternalProcessingStatusCode  NVARCHAR(100)   = NULL  OUTPUT
  ,@SuccessIndicator              CHAR(1)         = 'N'   OUTPUT
  ,@MessageLog                    NVARCHAR(MAX)   = N''   OUTPUT
)
AS
BEGIN
  BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Prepare/clean standard process/output parameters
    SET @Debug = CASE WHEN UPPER(@Debug) = 'Y' THEN 'Y' ELSE 'N' END;
    SET @SuccessIndicator = 'N';
    SET @MessageLog = N'[]';

    -- Prepare/clean process/output parameters
    SET @BatchInstanceId = NULL;
    SET @InternalProcessingStatusCode = NULL;
    SET @ResultJson = N'[]';
    SET @ReturnResultSet = CASE WHEN UPPER(COALESCE(@ReturnResultSet, 'Y')) = 'N' THEN 'N' ELSE 'Y' END;
    SET @BatchInstancesJson = N'[]';
    SET @IncludeChildBatches = CASE WHEN UPPER(COALESCE(@IncludeChildBatches, 'N')) = 'Y' THEN 'Y' ELSE 'N' END;
    SET @ParentBatchInstanceId = COALESCE(@ParentBatchInstanceId, 0);
    SET @ExecutionContext = COALESCE(@ExecutionContext, N'');
    SET @ModuleInstanceIdColumnName = COALESCE(NULLIF(TRIM(@ModuleInstanceIdColumnName), N''), N'MODULE_INSTANCE_ID');
    SET @DefaultStartValue = COALESCE(NULLIF(TRIM(@DefaultStartValue), N''), N'1900-01-01');
    SET @SourceTimestampColumn = COALESCE(NULLIF(TRIM(@SourceTimestampColumn), N''), N'LOAD_DATETIME');

    -- Standard setup and initialization
    DECLARE @ReturnCode INT = 0;
    DECLARE @EventDetail NVARCHAR(4000);
    DECLARE @EventReturnCode NVARCHAR(100);
    DECLARE @AddLogsToEventLog CHAR(1) = [omd_metadata].[GetSettingFlag]('LOG_TO_EVENT_LOG');
    DECLARE @ThrowOnFailure CHAR(1) = [omd_metadata].[GetSettingFlag]('THROW_ON_FAILURE');
    DECLARE @StartTimestamp DATETIME2 = SYSUTCDATETIME();
    DECLARE @StartTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@StartTimestamp);
    DECLARE @LogMessage NVARCHAR(MAX);
    DECLARE @SpName NVARCHAR(300) = CONCAT(QUOTENAME(COALESCE(OBJECT_SCHEMA_NAME(@@PROCID),'Unknown')), N'.',
        QUOTENAME(COALESCE(OBJECT_NAME(@@PROCID), 'Unknown')));

    -- The result set is collected here and returned at the end, so that the caller always receives exactly one result set.
    DECLARE @Result TABLE
    (
       ROW_ORDER                        INT IDENTITY(1,1) NOT NULL
      ,BATCH_INSTANCE_ID                BIGINT          NULL
      ,BATCH_CODE                       NVARCHAR(500)   NULL
      ,MODULE_INSTANCE_ID               BIGINT          NULL
      ,MODULE_ID                        INT             NULL
      ,MODULE_CODE                      NVARCHAR(500)   NULL
      ,MODULE_TYPE                      NVARCHAR(100)   NULL
      ,AREA_CODE                        NVARCHAR(100)   NULL
      ,[SEQUENCE]                       INT             NULL
      ,EXECUTABLE                       NVARCHAR(MAX)   NULL
      ,DATA_OBJECT_SOURCE               NVARCHAR(1000)  NULL
      ,DATA_OBJECT_TARGET               NVARCHAR(1000)  NULL
      ,PREVIOUS_END_VALUE               NVARCHAR(100)   NULL
      ,INTERNAL_PROCESSING_STATUS_CODE  NVARCHAR(100)   NULL
      ,ROLLBACK_STATEMENT               NVARCHAR(MAX)   NULL
      ,CONSISTENCY_DATETIME             NVARCHAR(27)    NULL
    );

    -- The Batch Instances that are created by this call, in run order (the Batch itself first, then its child Batches).
    DECLARE @BatchInstances TABLE
    (
       ROW_ORDER                        INT IDENTITY(1,1) NOT NULL
      ,BATCH_INSTANCE_ID                BIGINT          NOT NULL
      ,BATCH_CODE                       NVARCHAR(500)   NOT NULL
      ,PARENT_BATCH_INSTANCE_ID         BIGINT          NULL
      ,[LEVEL]                          INT             NOT NULL
      ,INTERNAL_PROCESSING_STATUS_CODE  NVARCHAR(100)   NULL
      ,MODULE_COUNT                     INT             NOT NULL
    );

    -- Validate input parameters
    IF (@BatchCode IS NULL OR TRIM(@BatchCode) = N'')
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, N'Missing required parameter @BatchCode.', @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, 'Missing required parameter @BatchCode.', 1;
      GOTO EndOfProcedureFailure;
    END;

    -- Log standard metadata
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Procedure', @SpName, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Version', [omd_metadata].[GetFrameworkVersion](), @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Start Timestamp', @StartTimestampString, @MessageLog);

    -- Log parameters
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BatchCode', @BatchCode, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ParentBatchInstanceId', @ParentBatchInstanceId, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ExecutionContext', @ExecutionContext, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ModuleInstanceIdColumnName', @ModuleInstanceIdColumnName, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @DefaultStartValue', @DefaultStartValue, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ConsistencyModuleTypeList', @ConsistencyModuleTypeList, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SourceTimestampColumn', @SourceTimestampColumn, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @IncludeChildBatches', @IncludeChildBatches, @MessageLog);

/*******************************************************************************
* Start of main process
*******************************************************************************/

    -- The Batch must exist. Automatic registration is left to CreateBatchInstance, but an unknown Batch
    -- would otherwise silently return an empty result set, so the existence is checked here as well.
    DECLARE @BatchId INT = (SELECT TOP 1 BATCH_ID FROM [omd].[BATCH] WHERE BATCH_CODE = @BatchCode);
    DECLARE @AutoRegisterBatches CHAR(1) = [omd_metadata].[GetSettingFlag]('AUTO_REGISTER_BATCHES');

    IF @BatchId IS NULL AND @AutoRegisterBatches <> 'Y'
    BEGIN
      SET @LogMessage = N'The Batch Code ''' + @BatchCode + N''' is not registered in omd.BATCH.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Parameter Error', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    -- Create the Batch Instance
    DECLARE @StepSuccessIndicator CHAR(1) = 'N';
    DECLARE @StepMessageLog NVARCHAR(MAX) = N'';

    EXEC [omd].[CreateBatchInstance]
       @BatchCode             = @BatchCode
      ,@ParentBatchInstanceId = @ParentBatchInstanceId
      ,@ExecutionContext      = @ExecutionContext
      ,@Debug                 = @Debug
      ,@BatchInstanceId       = @BatchInstanceId OUTPUT
      ,@SuccessIndicator      = @StepSuccessIndicator OUTPUT
      ,@MessageLog            = @StepMessageLog OUTPUT;

    IF @StepSuccessIndicator <> 'Y' OR @BatchInstanceId IS NULL OR @BatchInstanceId <= 0
    BEGIN
      SET @LogMessage = N'The Batch Instance could not be created for Batch Code ''' + @BatchCode + N'''.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'CreateBatchInstance Message Log', @StepMessageLog, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    SET @LogMessage = N'Batch Instance ' + CONVERT(NVARCHAR(20), @BatchInstanceId) + N' was created for Batch Code ''' + @BatchCode + N'''.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    -- Evaluate the Batch Instance
    EXEC [omd].[BatchEvaluation]
       @BatchInstanceId               = @BatchInstanceId
      ,@Debug                         = @Debug
      ,@InternalProcessingStatusCode  = @InternalProcessingStatusCode OUTPUT
      ,@SuccessIndicator              = @StepSuccessIndicator OUTPUT
      ,@MessageLog                    = @StepMessageLog OUTPUT;

    SET @InternalProcessingStatusCode = COALESCE(@InternalProcessingStatusCode, N'Abort');

    SET @LogMessage = N'The Batch Instance evaluation returned Internal Processing Status Code ''' + @InternalProcessingStatusCode + N'''.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    IF @InternalProcessingStatusCode IN (N'Abort', N'Cancel')
    BEGIN
      -- End states for the Batch; the evaluation has already updated the Batch Instance. No Module Instances are created.
      SET @LogMessage = N'No Module Instances are created because the Batch Instance ended in ''' + @InternalProcessingStatusCode + N'''.';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      INSERT INTO @BatchInstances (BATCH_INSTANCE_ID, BATCH_CODE, PARENT_BATCH_INSTANCE_ID, [LEVEL], INTERNAL_PROCESSING_STATUS_CODE, MODULE_COUNT)
      VALUES (@BatchInstanceId, @BatchCode, @ParentBatchInstanceId, 0, @InternalProcessingStatusCode, 0);
      GOTO EndOfProcedureSuccess;
    END

    IF @InternalProcessingStatusCode <> N'Proceed'
    BEGIN
      -- The evaluation itself failed (for example a rollback error); the Batch Instance has been failed by the evaluation.
      SET @LogMessage = N'The Batch Instance evaluation did not return ''Proceed'' but ''' + @InternalProcessingStatusCode + N'''. No Module Instances are created.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'BatchEvaluation Message Log', @StepMessageLog, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    -- Collect the Modules of the Batch, in sequence
    DECLARE @BatchModules TABLE
    (
       ROW_ORDER            INT IDENTITY(1,1) NOT NULL
      ,MODULE_ID            INT             NOT NULL
      ,MODULE_CODE          NVARCHAR(500)   NOT NULL
      ,MODULE_TYPE          NVARCHAR(100)   NOT NULL
      ,AREA_CODE            NVARCHAR(100)   NOT NULL
      ,[SEQUENCE]           INT             NOT NULL
      ,EXECUTABLE           NVARCHAR(MAX)   NULL
      ,DATA_OBJECT_SOURCE   NVARCHAR(1000)  NULL
      ,DATA_OBJECT_TARGET   NVARCHAR(1000)  NULL
    );

    INSERT INTO @BatchModules (MODULE_ID, MODULE_CODE, MODULE_TYPE, AREA_CODE, [SEQUENCE], EXECUTABLE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET)
    SELECT
       module.MODULE_ID
      ,module.MODULE_CODE
      ,module.MODULE_TYPE
      ,module.AREA_CODE
      ,bm.[SEQUENCE]
      ,module.EXECUTABLE
      ,module.DATA_OBJECT_SOURCE
      ,module.DATA_OBJECT_TARGET
    FROM [omd].[BATCH_MODULE] bm
    JOIN [omd].[MODULE] module ON bm.MODULE_ID = module.MODULE_ID
    JOIN [omd].[BATCH] batch ON bm.BATCH_ID = batch.BATCH_ID
    WHERE batch.BATCH_CODE = @BatchCode
      AND bm.ACTIVE_INDICATOR = 'Y'
    ORDER BY bm.[SEQUENCE], module.MODULE_CODE;

    DECLARE @ModuleCount INT = @@ROWCOUNT;
    SET @LogMessage = N'The Batch contains ' + CONVERT(NVARCHAR(10), @ModuleCount) + N' active Module(s).';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    INSERT INTO @BatchInstances (BATCH_INSTANCE_ID, BATCH_CODE, PARENT_BATCH_INSTANCE_ID, [LEVEL], INTERNAL_PROCESSING_STATUS_CODE, MODULE_COUNT)
    VALUES (@BatchInstanceId, @BatchCode, @ParentBatchInstanceId, 0, @InternalProcessingStatusCode, @ModuleCount);

    -- The Module Types that get a consistency timestamp
    DECLARE @ConsistencyModuleTypes TABLE (MODULE_TYPE NVARCHAR(100) NOT NULL);
    IF @ConsistencyModuleTypeList IS NOT NULL AND TRIM(@ConsistencyModuleTypeList) <> N''
    BEGIN
      INSERT INTO @ConsistencyModuleTypes (MODULE_TYPE)
      SELECT DISTINCT TRIM([value]) FROM STRING_SPLIT(@ConsistencyModuleTypeList, ',') WHERE TRIM([value]) <> N'';
    END

    -- Create and evaluate a Module Instance for every Module
    DECLARE @RowOrder INT = 1;
    DECLARE @ModuleId INT;
    DECLARE @ModuleCode NVARCHAR(500);
    DECLARE @ModuleType NVARCHAR(100);
    DECLARE @AreaCode NVARCHAR(100);
    DECLARE @Sequence INT;
    DECLARE @Executable NVARCHAR(MAX);
    DECLARE @DataObjectSource NVARCHAR(1000);
    DECLARE @DataObjectTarget NVARCHAR(1000);
    DECLARE @ModuleInstanceId BIGINT;
    DECLARE @ModuleProcessingStatusCode NVARCHAR(100);
    DECLARE @RollbackStatement NVARCHAR(MAX);
    DECLARE @PreviousEndValue NVARCHAR(100);
    DECLARE @ConsistencyDateTime DATETIME2(7);
    DECLARE @ConsistencyDateTimeString NVARCHAR(27);
    DECLARE @SourceModuleInstanceColumn NVARCHAR(128) = LEFT(@ModuleInstanceIdColumnName, 128);

    WHILE @RowOrder <= @ModuleCount
    BEGIN
      SELECT
         @ModuleId          = MODULE_ID
        ,@ModuleCode        = MODULE_CODE
        ,@ModuleType        = MODULE_TYPE
        ,@AreaCode          = AREA_CODE
        ,@Sequence          = [SEQUENCE]
        ,@Executable        = EXECUTABLE
        ,@DataObjectSource  = DATA_OBJECT_SOURCE
        ,@DataObjectTarget  = DATA_OBJECT_TARGET
      FROM @BatchModules
      WHERE ROW_ORDER = @RowOrder;

      SET @ModuleInstanceId = NULL;
      SET @ModuleProcessingStatusCode = NULL;
      SET @RollbackStatement = NULL;
      SET @PreviousEndValue = NULL;
      SET @ConsistencyDateTime = NULL;
      SET @ConsistencyDateTimeString = NULL;

      SET @LogMessage = N'Creating a Module Instance for Module ''' + @ModuleCode + N''' (' + CONVERT(NVARCHAR(10), @ModuleId) + N').';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      EXEC [omd].[CreateModuleInstance]
         @ModuleCode        = @ModuleCode
        ,@Query             = @Executable
        ,@BatchInstanceId   = @BatchInstanceId
        ,@ExecutionContext  = @ExecutionContext
        ,@Debug             = @Debug
        ,@ModuleInstanceId  = @ModuleInstanceId OUTPUT
        ,@SuccessIndicator  = @StepSuccessIndicator OUTPUT
        ,@MessageLog        = @StepMessageLog OUTPUT;

      IF @StepSuccessIndicator <> 'Y' OR @ModuleInstanceId IS NULL OR @ModuleInstanceId <= 0
      BEGIN
        SET @LogMessage = N'The Module Instance could not be created for Module ''' + @ModuleCode + N'''. The Batch Instance is failed.';
        SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
        SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'CreateModuleInstance Message Log', @StepMessageLog, @MessageLog);

        SET @EventDetail = LEFT(@LogMessage, 4000);
        IF @AddLogsToEventLog = 'Y' EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = 0, @EventDetail = @EventDetail, @BatchInstanceId = @BatchInstanceId;

        EXEC [omd].[UpdateBatchInstance] @BatchInstanceId = @BatchInstanceId, @EventCode = N'Failure', @Debug = @Debug;

        IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
        ELSE GOTO EndOfProcedureFailure;
      END

      -- Evaluate the Module Instance. Rollback statements are returned, not executed, because the target data object lives on another engine.
      EXEC [omd].[ModuleEvaluation]
         @ModuleInstanceId               = @ModuleInstanceId
        ,@ModuleInstanceIdColumnName     = @ModuleInstanceIdColumnName
        ,@ExecuteRollbackIndicator       = 'N'
        ,@Debug                          = @Debug
        ,@InternalProcessingStatusCode   = @ModuleProcessingStatusCode OUTPUT
        ,@RollbackStatement              = @RollbackStatement OUTPUT
        ,@SuccessIndicator               = @StepSuccessIndicator OUTPUT
        ,@MessageLog                     = @StepMessageLog OUTPUT;

      SET @ModuleProcessingStatusCode = COALESCE(@ModuleProcessingStatusCode, N'Abort');

      SET @LogMessage = N'Module Instance ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' for Module ''' + @ModuleCode
        + N''' was evaluated as ''' + @ModuleProcessingStatusCode + N'''' + CASE WHEN @RollbackStatement IS NULL THEN N'.' ELSE N' with a rollback statement.' END;
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      -- The previous load window end value is read after the evaluation, because a rollback removes the Source Control entries of failed instances.
      SET @PreviousEndValue = COALESCE([omd].[GetModuleLoadWindowValue](@ModuleId, 2), @DefaultStartValue);

      -- Consistency timestamp, calculated on repository information only, for the configured Module Types.
      IF @ModuleProcessingStatusCode = N'Proceed'
         AND @DataObjectSource IS NOT NULL
         AND EXISTS (SELECT 1 FROM @ConsistencyModuleTypes WHERE MODULE_TYPE = @ModuleType)
      BEGIN
        EXEC [omd].[GetConsistencyTimestamp]
           @TableList                  = @DataObjectSource
          ,@SourceTimestampColumn      = @SourceTimestampColumn
          ,@SourceModuleInstanceColumn = @SourceModuleInstanceColumn
          ,@SourceDataLookupIndicator  = 'N'
          ,@Debug                      = @Debug
          ,@ConsistencyDateTime        = @ConsistencyDateTime OUTPUT
          ,@SuccessIndicator           = @StepSuccessIndicator OUTPUT
          ,@MessageLog                 = @StepMessageLog OUTPUT;

        SET @ConsistencyDateTimeString = CASE WHEN @ConsistencyDateTime IS NULL THEN NULL ELSE FORMAT(@ConsistencyDateTime, 'yyyy-MM-dd HH:mm:ss.fffffff') END;

        SET @LogMessage = N'The consistency timestamp for Module ''' + @ModuleCode + N''' is ' + COALESCE(@ConsistencyDateTimeString, N'NULL') + N'.';
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      END

      INSERT INTO @Result
      (
         BATCH_INSTANCE_ID, BATCH_CODE, MODULE_INSTANCE_ID, MODULE_ID, MODULE_CODE, MODULE_TYPE, AREA_CODE, [SEQUENCE]
        ,EXECUTABLE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, PREVIOUS_END_VALUE, INTERNAL_PROCESSING_STATUS_CODE, ROLLBACK_STATEMENT, CONSISTENCY_DATETIME
      )
      VALUES
      (
         @BatchInstanceId, @BatchCode, @ModuleInstanceId, @ModuleId, @ModuleCode, @ModuleType, @AreaCode, @Sequence
        ,@Executable, @DataObjectSource, @DataObjectTarget, @PreviousEndValue, @ModuleProcessingStatusCode, @RollbackStatement, @ConsistencyDateTimeString
      );

      SET @RowOrder = @RowOrder + 1;
    END

    -- Child Batches, after the Modules of the Batch itself (the order omd.RunBatch uses)
    IF @IncludeChildBatches = 'Y'
    BEGIN
      DECLARE @ChildBatches TABLE
      (
         ROW_ORDER    INT IDENTITY(1,1) NOT NULL
        ,BATCH_CODE   NVARCHAR(500)   NOT NULL
      );

      INSERT INTO @ChildBatches (BATCH_CODE)
      SELECT child.BATCH_CODE
      FROM [omd].[BATCH_HIERARCHY] bh
      JOIN [omd].[BATCH] child ON bh.BATCH_ID = child.BATCH_ID
      WHERE bh.PARENT_BATCH_ID = @BatchId
        AND bh.ACTIVE_INDICATOR = 'Y'
        AND child.ACTIVE_INDICATOR = 'Y'
        AND child.BATCH_ID <> @BatchId
      ORDER BY bh.[SEQUENCE], child.BATCH_CODE;

      DECLARE @ChildCount INT = @@ROWCOUNT;
      SET @LogMessage = N'The Batch has ' + CONVERT(NVARCHAR(10), @ChildCount) + N' active child Batch(es).';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      DECLARE @ChildOrder INT = 1;
      DECLARE @ChildBatchCode NVARCHAR(500);
      DECLARE @ChildBatchInstanceId BIGINT;
      DECLARE @ChildProcessingStatusCode NVARCHAR(100);
      DECLARE @ChildResultJson NVARCHAR(MAX);
      DECLARE @ChildBatchInstancesJson NVARCHAR(MAX);

      WHILE @ChildOrder <= @ChildCount
      BEGIN
        SELECT @ChildBatchCode = BATCH_CODE FROM @ChildBatches WHERE ROW_ORDER = @ChildOrder;
        SET @ChildOrder = @ChildOrder + 1;

        SET @ChildBatchInstanceId = NULL;
        SET @ChildProcessingStatusCode = NULL;
        SET @ChildResultJson = NULL;
        SET @ChildBatchInstancesJson = NULL;
        SET @StepMessageLog = N'';

        SET @LogMessage = N'Opening child Batch ''' + @ChildBatchCode + N''' with Batch Instance ' + CONVERT(NVARCHAR(20), @BatchInstanceId) + N' as parent.';
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

        EXEC [omd].[CreateBatchModuleInstances]
           @BatchCode                     = @ChildBatchCode
          ,@ParentBatchInstanceId         = @BatchInstanceId
          ,@ExecutionContext              = @ExecutionContext
          ,@ModuleInstanceIdColumnName    = @ModuleInstanceIdColumnName
          ,@DefaultStartValue             = @DefaultStartValue
          ,@ConsistencyModuleTypeList     = @ConsistencyModuleTypeList
          ,@SourceTimestampColumn         = @SourceTimestampColumn
          ,@ReturnResultSet               = 'N'
          ,@IncludeChildBatches           = 'Y'
          ,@Debug                         = @Debug
          ,@ResultJson                    = @ChildResultJson OUTPUT
          ,@BatchInstancesJson            = @ChildBatchInstancesJson OUTPUT
          ,@BatchInstanceId               = @ChildBatchInstanceId OUTPUT
          ,@InternalProcessingStatusCode  = @ChildProcessingStatusCode OUTPUT
          ,@SuccessIndicator              = @StepSuccessIndicator OUTPUT
          ,@MessageLog                    = @StepMessageLog OUTPUT;

        IF @StepSuccessIndicator <> 'Y'
        BEGIN
          SET @LogMessage = N'The child Batch ''' + @ChildBatchCode + N''' could not be opened. The Batch Instance is failed.';
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Child Batch Message Log', @StepMessageLog, @MessageLog);

          SET @EventDetail = LEFT(@LogMessage, 4000);
          IF @AddLogsToEventLog = 'Y' EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = 0, @EventDetail = @EventDetail, @BatchInstanceId = @BatchInstanceId;

          IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
          ELSE GOTO EndOfProcedureFailure;
        END

        SET @LogMessage = N'Child Batch ''' + @ChildBatchCode + N''' was opened as Batch Instance ' + CONVERT(NVARCHAR(20), COALESCE(@ChildBatchInstanceId, 0))
          + N' with Internal Processing Status Code ''' + COALESCE(@ChildProcessingStatusCode, N'NULL') + N'''.';
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

        -- The rows of the child Batch (and its children) follow the rows of this Batch, in their own order
        INSERT INTO @Result
        (
           BATCH_INSTANCE_ID, BATCH_CODE, MODULE_INSTANCE_ID, MODULE_ID, MODULE_CODE, MODULE_TYPE, AREA_CODE, [SEQUENCE]
          ,EXECUTABLE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, PREVIOUS_END_VALUE, INTERNAL_PROCESSING_STATUS_CODE, ROLLBACK_STATEMENT, CONSISTENCY_DATETIME
        )
        SELECT
           r.BATCH_INSTANCE_ID, r.BATCH_CODE, r.MODULE_INSTANCE_ID, r.MODULE_ID, r.MODULE_CODE, r.MODULE_TYPE, r.AREA_CODE, r.[SEQUENCE]
          ,r.EXECUTABLE, r.DATA_OBJECT_SOURCE, r.DATA_OBJECT_TARGET, r.PREVIOUS_END_VALUE, r.INTERNAL_PROCESSING_STATUS_CODE, r.ROLLBACK_STATEMENT, r.CONSISTENCY_DATETIME
        FROM OPENJSON(COALESCE(@ChildResultJson, N'[]')) arr
        CROSS APPLY OPENJSON(arr.[value])
        WITH
        (
           BATCH_INSTANCE_ID                BIGINT
          ,BATCH_CODE                       NVARCHAR(500)
          ,MODULE_INSTANCE_ID               BIGINT
          ,MODULE_ID                        INT
          ,MODULE_CODE                      NVARCHAR(500)
          ,MODULE_TYPE                      NVARCHAR(100)
          ,AREA_CODE                        NVARCHAR(100)
          ,[SEQUENCE]                       INT
          ,EXECUTABLE                       NVARCHAR(MAX)
          ,DATA_OBJECT_SOURCE               NVARCHAR(1000)
          ,DATA_OBJECT_TARGET               NVARCHAR(1000)
          ,PREVIOUS_END_VALUE               NVARCHAR(100)
          ,INTERNAL_PROCESSING_STATUS_CODE  NVARCHAR(100)
          ,ROLLBACK_STATEMENT               NVARCHAR(MAX)
          ,CONSISTENCY_DATETIME             NVARCHAR(27)
        ) r
        ORDER BY TRY_CONVERT(INT, arr.[key]);

        INSERT INTO @BatchInstances (BATCH_INSTANCE_ID, BATCH_CODE, PARENT_BATCH_INSTANCE_ID, [LEVEL], INTERNAL_PROCESSING_STATUS_CODE, MODULE_COUNT)
        SELECT b.BATCH_INSTANCE_ID, b.BATCH_CODE, b.PARENT_BATCH_INSTANCE_ID, b.[LEVEL] + 1, b.INTERNAL_PROCESSING_STATUS_CODE, b.MODULE_COUNT
        FROM OPENJSON(COALESCE(@ChildBatchInstancesJson, N'[]')) arr
        CROSS APPLY OPENJSON(arr.[value])
        WITH
        (
           BATCH_INSTANCE_ID                BIGINT
          ,BATCH_CODE                       NVARCHAR(500)
          ,PARENT_BATCH_INSTANCE_ID         BIGINT
          ,[LEVEL]                          INT
          ,INTERNAL_PROCESSING_STATUS_CODE  NVARCHAR(100)
          ,MODULE_COUNT                     INT
        ) b
        ORDER BY TRY_CONVERT(INT, arr.[key]);
      END
    END

    SET @SuccessIndicator = 'Y';
    GOTO EndOfProcedureSuccess;

/*******************************************************************************
* Start of end state management
*******************************************************************************/

    EndOfProcedureFailure:
      SET @SuccessIndicator = 'N';
      SET @LogMessage = N'Create Batch Module Instances process encountered errors.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
      SET @ReturnCode = -1;

      -- Nothing that was opened by this call will run; the Module and Batch Instances that are still executing are
      -- failed, so that they do not block the next run.
      IF @BatchInstanceId IS NOT NULL
      BEGIN
        DECLARE @OpenInstances TABLE (ROW_ORDER INT IDENTITY(1,1) NOT NULL, MODULE_INSTANCE_ID BIGINT NOT NULL, BATCH_INSTANCE_ID BIGINT NULL);
        INSERT INTO @OpenInstances (MODULE_INSTANCE_ID, BATCH_INSTANCE_ID)
        SELECT mi.MODULE_INSTANCE_ID, mi.BATCH_INSTANCE_ID
        FROM @Result r
        JOIN [omd].[MODULE_INSTANCE] mi ON r.MODULE_INSTANCE_ID = mi.MODULE_INSTANCE_ID
        WHERE mi.EXECUTION_STATUS_CODE = N'Executing'
        ORDER BY r.ROW_ORDER;

        DECLARE @OpenCount INT = @@ROWCOUNT;
        DECLARE @OpenOrder INT = 1;
        DECLARE @OpenModuleInstanceId BIGINT;
        DECLARE @OpenBatchInstanceId BIGINT;
        DECLARE @OpenEventDetail NVARCHAR(4000) = N'The Module Instance was opened, but the Batch could not be fully opened and nothing was run.';

        WHILE @OpenOrder <= @OpenCount
        BEGIN
          SELECT @OpenModuleInstanceId = MODULE_INSTANCE_ID, @OpenBatchInstanceId = BATCH_INSTANCE_ID FROM @OpenInstances WHERE ROW_ORDER = @OpenOrder;
          SET @OpenOrder = @OpenOrder + 1;
          EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = @OpenModuleInstanceId, @EventDetail = @OpenEventDetail, @BatchInstanceId = @OpenBatchInstanceId, @Debug = @Debug;
          EXEC [omd].[UpdateModuleInstance] @ModuleInstanceId = @OpenModuleInstanceId, @EventCode = N'Failure', @Debug = @Debug;
        END

        UPDATE r SET r.INTERNAL_PROCESSING_STATUS_CODE = N'Failure' FROM @Result r JOIN @OpenInstances o ON r.MODULE_INSTANCE_ID = o.MODULE_INSTANCE_ID;

        -- Child Batch Instances first (deepest last in the list, so in reverse order), then the Batch Instance itself
        DECLARE @OpenBatches TABLE (ROW_ORDER INT IDENTITY(1,1) NOT NULL, BATCH_INSTANCE_ID BIGINT NOT NULL);
        INSERT INTO @OpenBatches (BATCH_INSTANCE_ID)
        SELECT b.BATCH_INSTANCE_ID
        FROM (SELECT ROW_ORDER, BATCH_INSTANCE_ID FROM @BatchInstances UNION SELECT 0, @BatchInstanceId) b
        JOIN [omd].[BATCH_INSTANCE] bi ON b.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID
        WHERE bi.EXECUTION_STATUS_CODE = N'Executing'
        ORDER BY b.ROW_ORDER DESC;

        SET @OpenCount = @@ROWCOUNT;
        SET @OpenOrder = 1;
        WHILE @OpenOrder <= @OpenCount
        BEGIN
          SELECT @OpenBatchInstanceId = BATCH_INSTANCE_ID FROM @OpenBatches WHERE ROW_ORDER = @OpenOrder;
          SET @OpenOrder = @OpenOrder + 1;
          EXEC [omd].[UpdateBatchInstance] @BatchInstanceId = @OpenBatchInstanceId, @EventCode = N'Failure', @Debug = @Debug;
        END

        UPDATE b SET b.INTERNAL_PROCESSING_STATUS_CODE = N'Failure' FROM @BatchInstances b JOIN @OpenBatches o ON b.BATCH_INSTANCE_ID = o.BATCH_INSTANCE_ID;
        IF EXISTS (SELECT 1 FROM @OpenBatches WHERE BATCH_INSTANCE_ID = @BatchInstanceId) SET @InternalProcessingStatusCode = N'Failure';
      END

      GOTO EndOfProcedure;

    EndOfProcedureSuccess:
      SET @SuccessIndicator = 'Y';
      SET @LogMessage = N'Create Batch Module Instances process completed successfully.';
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
      SET @ReturnCode = 0;
      GOTO EndOfProcedure;

    EndOfProcedure:
      DECLARE @EndTimestamp DATETIME2 = SYSUTCDATETIME();
      DECLARE @EndTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@EndTimestamp);
      DECLARE @DurationSeconds NVARCHAR(10) = CONVERT(NVARCHAR(10), COALESCE(DATEDIFF(SECOND, @StartTimestamp, @EndTimestamp), 0));
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'End Timestamp', @EndTimestampString, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Elapsed Time (s)', @DurationSeconds, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BatchInstanceId', @BatchInstanceId, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @InternalProcessingStatusCode', @InternalProcessingStatusCode, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SuccessIndicator', @SuccessIndicator, @MessageLog);
      IF @Debug = 'Y' EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

      -- The rows as JSON, for callers that cannot consume the result set
      SET @ResultJson = COALESCE(
      (
        SELECT
           BATCH_INSTANCE_ID, BATCH_CODE, MODULE_INSTANCE_ID, MODULE_ID, MODULE_CODE, MODULE_TYPE, AREA_CODE, [SEQUENCE]
          ,EXECUTABLE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, PREVIOUS_END_VALUE, INTERNAL_PROCESSING_STATUS_CODE, ROLLBACK_STATEMENT, CONSISTENCY_DATETIME
        FROM @Result
        ORDER BY ROW_ORDER
        FOR JSON PATH
      ), N'[]');

      SET @BatchInstancesJson = COALESCE(
      (
        SELECT BATCH_INSTANCE_ID, BATCH_CODE, PARENT_BATCH_INSTANCE_ID, [LEVEL], INTERNAL_PROCESSING_STATUS_CODE, MODULE_COUNT
        FROM @BatchInstances
        ORDER BY ROW_ORDER
        FOR JSON PATH
      ), N'[]');

      IF @ReturnResultSet = 'N' RETURN @ReturnCode;

      -- The result set is returned in all other cases, empty when no Module Instances were created.
      SELECT
         BATCH_INSTANCE_ID
        ,BATCH_CODE
        ,MODULE_INSTANCE_ID
        ,MODULE_ID
        ,MODULE_CODE
        ,MODULE_TYPE
        ,AREA_CODE
        ,[SEQUENCE]
        ,EXECUTABLE
        ,DATA_OBJECT_SOURCE
        ,DATA_OBJECT_TARGET
        ,PREVIOUS_END_VALUE
        ,INTERNAL_PROCESSING_STATUS_CODE
        ,ROLLBACK_STATEMENT
        ,CONSISTENCY_DATETIME
      FROM @Result
      ORDER BY ROW_ORDER;

      RETURN @ReturnCode;

  END TRY
/*******************************************************************************
* Common, standardized, Procedure-wrapping error handling
*******************************************************************************/
  BEGIN CATCH
    -- Reset output parameters
    SET @SuccessIndicator = 'N';
    SET @ResultJson = N'[]';
    SET @BatchInstancesJson = N'[]';
    SET @InternalProcessingStatusCode = COALESCE(@InternalProcessingStatusCode, N'Abort');
    SET @BatchInstanceId = @BatchInstanceId; -- keeps the created instance, if any; assignment required on every path

    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SuccessIndicator Exit Value', @SuccessIndicator, @MessageLog);

    DECLARE
      @ErrorMessage NVARCHAR(4000),
      @ErrorSeverity INT,
      @ErrorState INT,
      @ErrorProcedure NVARCHAR(128),
      @ErrorNumber INT,
      @ErrorLine INT;

    SELECT
      @ErrorMessage   = COALESCE(ERROR_MESSAGE(),     'No Message'    ),
      @ErrorSeverity  = COALESCE(ERROR_SEVERITY(),    -1              ),
      @ErrorState     = COALESCE(ERROR_STATE(),       -1              ),
      @ErrorProcedure = COALESCE(ERROR_PROCEDURE(),   'No Procedure'  ),
      @ErrorLine      = COALESCE(ERROR_LINE(),        -1              ),
      @ErrorNumber    = COALESCE(ERROR_NUMBER(),      -1              );

    IF @Debug = 'Y'
    BEGIN
      PRINT 'Error in:         ' + @SpName;
      PRINT 'Error Message:    ' + @ErrorMessage;
      PRINT 'Error Severity:   ' + CONVERT(NVARCHAR(10), @ErrorSeverity);
      PRINT 'Error State:      ' + CONVERT(NVARCHAR(10), @ErrorState);
      PRINT 'Error Procedure:  ' + @ErrorProcedure;
      PRINT 'Error Line:       ' + CONVERT(NVARCHAR(10), @ErrorLine);
      PRINT 'Error Number:     ' + CONVERT(NVARCHAR(10), @ErrorNumber);
      PRINT 'SuccessIndicator: ' + @SuccessIndicator;

      -- Spool full message log
      EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
    END;
    IF @AddLogsToEventLog = 'Y'
    BEGIN
      SET @EventDetail =
        CONCAT('Error in ''', @SpName,
        ''' from ''', @ErrorProcedure, ''' at line ''',
        CONVERT(NVARCHAR(10), COALESCE(@ErrorLine,'N/A')), ''': ', CHAR(10),
        COALESCE(@ErrorMessage,'N/A'));
      SET @EventReturnCode = ERROR_NUMBER();
      DECLARE @EventBatchInstanceId BIGINT = COALESCE(@BatchInstanceId, 0);

      EXEC [omd].[InsertIntoEventLog]
         @ModuleInstanceId  = 0
        ,@EventDetail       = @EventDetail
        ,@BatchInstanceId   = @EventBatchInstanceId
        ,@EventReturnCode   = @EventReturnCode
        ,@Debug             = @Debug

      SET @MessageLog = [omd].[AddLogMessage] ('CRITICAL', DEFAULT, N'Error Details', @EventDetail, @MessageLog);
    END
    IF @ThrowOnFailure = 'Y' THROW 50000, @EventDetail, 1;

    RETURN -2;

  END CATCH
END;
