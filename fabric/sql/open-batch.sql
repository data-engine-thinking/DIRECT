-- DIRECT Run Batch, activity 'Open Batch' (repository database).
-- Opens the Batch Instance, the Module Instances of the Batch and, recursively, its active child Batches with
-- omd.CreateBatchModuleInstances (the Modules of a Batch first, then its child Batches in sequence, as omd.RunBatch does).
-- Returns one row: BATCH_INSTANCE_ID, INTERNAL_PROCESSING_STATUS_CODE, BATCH_CODE, MODULE_COUNT, BATCH_INSTANCE_COUNT,
--   MODULES (JSON array with the 'Proceed' rows of omd.CreateBatchModuleInstances, in run order) and
--   BATCH_INSTANCES (JSON array with the Batch Instances that were opened: id, code, parent, level, status, module count).
-- Parameters: @BatchCode, @ParentBatchInstanceId (string, '0' when none), @ExecutionContext,
--             @ModuleInstanceIdColumnName, @DefaultStartValue, @ConsistencyModuleTypeList, @SourceTimestampColumn.
SET NOCOUNT ON;

DECLARE @BatchInstanceId BIGINT;
DECLARE @InternalProcessingStatusCode NVARCHAR(100);
DECLARE @SuccessIndicator CHAR(1) = 'N';
DECLARE @MessageLog NVARCHAR(MAX);
DECLARE @ErrorMessage NVARCHAR(2048);
DECLARE @ParentId BIGINT = COALESCE(TRY_CONVERT(BIGINT, NULLIF(TRIM(@ParentBatchInstanceId), N'')), 0);
DECLARE @ConsistencyTypes NVARCHAR(4000) = NULLIF(TRIM(@ConsistencyModuleTypeList), N'');

DECLARE @Modules NVARCHAR(MAX);
DECLARE @BatchInstances NVARCHAR(MAX);

-- The rows come back as JSON (no INSERT ... EXEC, which would wrap the call in a transaction that a failed evaluation dooms).
EXEC [omd].[CreateBatchModuleInstances]
   @BatchCode                    = @BatchCode
  ,@ParentBatchInstanceId        = @ParentId
  ,@ExecutionContext             = @ExecutionContext
  ,@ModuleInstanceIdColumnName   = @ModuleInstanceIdColumnName
  ,@DefaultStartValue            = @DefaultStartValue
  ,@ConsistencyModuleTypeList    = @ConsistencyTypes
  ,@SourceTimestampColumn        = @SourceTimestampColumn
  ,@ReturnResultSet              = 'N'
  ,@IncludeChildBatches          = 'Y'
  ,@ResultJson                   = @Modules OUTPUT
  ,@BatchInstancesJson           = @BatchInstances OUTPUT
  ,@BatchInstanceId              = @BatchInstanceId OUTPUT
  ,@InternalProcessingStatusCode = @InternalProcessingStatusCode OUTPUT
  ,@SuccessIndicator             = @SuccessIndicator OUTPUT
  ,@MessageLog                   = @MessageLog OUTPUT;

IF @SuccessIndicator <> 'Y'
BEGIN
  IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
  SET @ErrorMessage = LEFT(N'DIRECT could not open Batch ''' + COALESCE(@BatchCode, N'') + N''': ' + COALESCE(@MessageLog, N''), 2048);
  THROW 50000, @ErrorMessage, 1;
END;

-- Only the Modules that proceed are handed to the orchestrator, in run order (RUN_ORDER is the position in that order)
SET @Modules = COALESCE(
(
  SELECT
     ROW_NUMBER() OVER (ORDER BY TRY_CONVERT(INT, arr.[key])) AS RUN_ORDER
    ,r.BATCH_INSTANCE_ID, r.BATCH_CODE, r.MODULE_INSTANCE_ID, r.MODULE_ID, r.MODULE_CODE, r.MODULE_TYPE, r.AREA_CODE, r.[SEQUENCE]
    ,r.EXECUTABLE, r.DATA_OBJECT_SOURCE, r.DATA_OBJECT_TARGET, r.PREVIOUS_END_VALUE, r.INTERNAL_PROCESSING_STATUS_CODE, r.ROLLBACK_STATEMENT, r.CONSISTENCY_DATETIME
  FROM OPENJSON(@Modules) arr
  CROSS APPLY OPENJSON(arr.[value])
  WITH
  (
     BATCH_INSTANCE_ID BIGINT, BATCH_CODE NVARCHAR(500), MODULE_INSTANCE_ID BIGINT, MODULE_ID INT, MODULE_CODE NVARCHAR(500), MODULE_TYPE NVARCHAR(100)
    ,AREA_CODE NVARCHAR(100), [SEQUENCE] INT, EXECUTABLE NVARCHAR(MAX), DATA_OBJECT_SOURCE NVARCHAR(1000), DATA_OBJECT_TARGET NVARCHAR(1000)
    ,PREVIOUS_END_VALUE NVARCHAR(100), INTERNAL_PROCESSING_STATUS_CODE NVARCHAR(100), ROLLBACK_STATEMENT NVARCHAR(MAX), CONSISTENCY_DATETIME NVARCHAR(27)
  ) r
  WHERE r.INTERNAL_PROCESSING_STATUS_CODE = N'Proceed'
  ORDER BY TRY_CONVERT(INT, arr.[key])
  FOR JSON PATH
), N'[]');

SELECT
   @BatchInstanceId AS BATCH_INSTANCE_ID
  ,@InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE
  ,@BatchCode AS BATCH_CODE
  ,(SELECT COUNT(*) FROM OPENJSON(@Modules)) AS MODULE_COUNT
  ,(SELECT COUNT(*) FROM OPENJSON(COALESCE(@BatchInstances, N'[]'))) AS BATCH_INSTANCE_COUNT
  ,@Modules AS MODULES
  ,COALESCE(@BatchInstances, N'[]') AS BATCH_INSTANCES;
