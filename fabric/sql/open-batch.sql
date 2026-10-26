-- DIRECT Run Batch, activity 'Open Batch' (repository database).
-- Opens the Batch Instance and the Module Instances of the Batch with omd.CreateBatchModuleInstances.
-- Returns one row: BATCH_INSTANCE_ID, INTERNAL_PROCESSING_STATUS_CODE, BATCH_CODE, MODULE_COUNT,
--   MODULES (JSON array with the 'Proceed' rows of omd.CreateBatchModuleInstances, in sequence) and
--   CHILD_BATCHES (JSON array with the active child Batches of the Batch, in sequence; used by DIRECT Run Project).
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
  ,@ResultJson                   = @Modules OUTPUT
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

-- Only the Modules that proceed are handed to the orchestrator
SET @Modules = COALESCE(
(
  SELECT
     BATCH_INSTANCE_ID, BATCH_CODE, MODULE_INSTANCE_ID, MODULE_ID, MODULE_CODE, MODULE_TYPE, AREA_CODE, [SEQUENCE]
    ,EXECUTABLE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, PREVIOUS_END_VALUE, INTERNAL_PROCESSING_STATUS_CODE, ROLLBACK_STATEMENT, CONSISTENCY_DATETIME
  FROM OPENJSON(@Modules)
  WITH
  (
     BATCH_INSTANCE_ID BIGINT, BATCH_CODE NVARCHAR(500), MODULE_INSTANCE_ID BIGINT, MODULE_ID INT, MODULE_CODE NVARCHAR(500), MODULE_TYPE NVARCHAR(100)
    ,AREA_CODE NVARCHAR(100), [SEQUENCE] INT, EXECUTABLE NVARCHAR(MAX), DATA_OBJECT_SOURCE NVARCHAR(1000), DATA_OBJECT_TARGET NVARCHAR(1000)
    ,PREVIOUS_END_VALUE NVARCHAR(100), INTERNAL_PROCESSING_STATUS_CODE NVARCHAR(100), ROLLBACK_STATEMENT NVARCHAR(MAX), CONSISTENCY_DATETIME NVARCHAR(27)
  )
  WHERE INTERNAL_PROCESSING_STATUS_CODE = N'Proceed'
  ORDER BY [SEQUENCE], MODULE_CODE
  FOR JSON PATH
), N'[]');

DECLARE @ChildBatches NVARCHAR(MAX) =
(
  SELECT
     BATCH_CODE
    ,[SEQUENCE]
  FROM [omd_processing].[vw_BATCH_HIERARCHY]
  WHERE PARENT_BATCH_CODE = @BatchCode
    AND RELATIONSHIP_ACTIVE_INDICATOR = 'Y'
    AND BATCH_ACTIVE_INDICATOR = 'Y'
    AND @InternalProcessingStatusCode = N'Proceed'
  ORDER BY [SEQUENCE], BATCH_CODE
  FOR JSON PATH
);

SELECT
   @BatchInstanceId AS BATCH_INSTANCE_ID
  ,@InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE
  ,@BatchCode AS BATCH_CODE
  ,(SELECT COUNT(*) FROM OPENJSON(@Modules)) AS MODULE_COUNT
  ,@Modules AS MODULES
  ,COALESCE(@ChildBatches, N'[]') AS CHILD_BATCHES;
