-- DIRECT Run Module, activity 'Open Module' (repository database).
-- Opens and evaluates one Module Instance; the rollback statement is returned, not executed.
-- Returns one row: MODULE_INSTANCE_ID, INTERNAL_PROCESSING_STATUS_CODE, MODULE_CODE and
--   MODULES (JSON array with the Module to run in the shape of omd.CreateBatchModuleInstances; empty unless 'Proceed').
-- Parameters: @ModuleCode, @ExecutionContext, @ModuleInstanceIdColumnName, @DefaultStartValue, @ConsistencyModuleTypeList, @SourceTimestampColumn.
SET NOCOUNT ON;

DECLARE @ModuleInstanceId BIGINT;
DECLARE @InternalProcessingStatusCode NVARCHAR(100);
DECLARE @RollbackStatement NVARCHAR(MAX);
DECLARE @SuccessIndicator CHAR(1) = 'N';
DECLARE @MessageLog NVARCHAR(MAX);
DECLARE @ErrorMessage NVARCHAR(2048);
DECLARE @ModuleId INT, @ModuleType NVARCHAR(100), @DataObjectSource NVARCHAR(1000);
DECLARE @ConsistencyDateTime DATETIME2(7), @ConsistencyDateTimeString NVARCHAR(27);
DECLARE @StartValue NVARCHAR(100) = COALESCE(NULLIF(TRIM(@DefaultStartValue), N''), N'1900-01-01');

EXEC [omd].[CreateModuleInstance]
   @ModuleCode        = @ModuleCode
  ,@ExecutionContext  = @ExecutionContext
  ,@ModuleInstanceId  = @ModuleInstanceId OUTPUT
  ,@SuccessIndicator  = @SuccessIndicator OUTPUT
  ,@MessageLog        = @MessageLog OUTPUT;

IF @SuccessIndicator <> 'Y' OR @ModuleInstanceId IS NULL
BEGIN
  SET @ErrorMessage = LEFT(N'DIRECT could not open Module ''' + COALESCE(@ModuleCode, N'') + N''': ' + COALESCE(@MessageLog, N''), 2048);
  THROW 50000, @ErrorMessage, 1;
END;

EXEC [omd].[ModuleEvaluation]
   @ModuleInstanceId               = @ModuleInstanceId
  ,@ModuleInstanceIdColumnName     = @ModuleInstanceIdColumnName
  ,@ExecuteRollbackIndicator       = 'N'
  ,@InternalProcessingStatusCode   = @InternalProcessingStatusCode OUTPUT
  ,@RollbackStatement              = @RollbackStatement OUTPUT
  ,@SuccessIndicator               = @SuccessIndicator OUTPUT
  ,@MessageLog                     = @MessageLog OUTPUT;

SET @InternalProcessingStatusCode = COALESCE(@InternalProcessingStatusCode, N'Abort');
SET @ModuleId = [omd].[GetModuleIdByModuleInstanceId](@ModuleInstanceId);

SELECT @ModuleType = MODULE_TYPE, @DataObjectSource = DATA_OBJECT_SOURCE FROM [omd].[MODULE] WHERE MODULE_ID = @ModuleId;

IF @InternalProcessingStatusCode = N'Proceed'
   AND @DataObjectSource IS NOT NULL
   AND EXISTS (SELECT 1 FROM STRING_SPLIT(COALESCE(@ConsistencyModuleTypeList, N''), ',') WHERE TRIM([value]) = @ModuleType)
BEGIN
  EXEC [omd].[GetConsistencyTimestamp]
     @TableList                   = @DataObjectSource
    ,@SourceTimestampColumn       = @SourceTimestampColumn
    ,@SourceModuleInstanceColumn  = @ModuleInstanceIdColumnName
    ,@SourceDataLookupIndicator   = 'N'
    ,@ConsistencyDateTime         = @ConsistencyDateTime OUTPUT;
  SET @ConsistencyDateTimeString = CASE WHEN @ConsistencyDateTime IS NULL THEN NULL ELSE FORMAT(@ConsistencyDateTime, 'yyyy-MM-dd HH:mm:ss.fffffff') END;
END;

DECLARE @Modules NVARCHAR(MAX) =
(
  SELECT
     CONVERT(BIGINT, 0) AS BATCH_INSTANCE_ID
    ,CONVERT(NVARCHAR(500), NULL) AS BATCH_CODE
    ,@ModuleInstanceId AS MODULE_INSTANCE_ID
    ,m.MODULE_ID
    ,m.MODULE_CODE
    ,m.MODULE_TYPE
    ,m.AREA_CODE
    ,1 AS [SEQUENCE]
    ,m.EXECUTABLE
    ,m.DATA_OBJECT_SOURCE
    ,m.DATA_OBJECT_TARGET
    ,COALESCE([omd].[GetModuleLoadWindowValue](m.MODULE_ID, 2), @StartValue) AS PREVIOUS_END_VALUE
    ,@InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE
    ,@RollbackStatement AS ROLLBACK_STATEMENT
    ,@ConsistencyDateTimeString AS CONSISTENCY_DATETIME
  FROM [omd].[MODULE] m
  WHERE m.MODULE_ID = @ModuleId
    AND @InternalProcessingStatusCode = N'Proceed'
  FOR JSON PATH
);

SELECT
   @ModuleInstanceId AS MODULE_INSTANCE_ID
  ,@InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE
  ,@ModuleCode AS MODULE_CODE
  ,COALESCE(@Modules, N'[]') AS MODULES;
