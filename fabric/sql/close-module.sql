-- DIRECT Run Module, activity 'Close Module' (repository database).
-- Records the load window and the outcome of the Module Instance from the result row of 'Run Modules'.
-- Fails the activity (after the bookkeeping) when the Module failed.
-- Parameters: @ModuleInstanceId (string), @InternalProcessingStatusCode, @ModuleResults (string, JSON array with one row).
SET NOCOUNT ON;

DECLARE @Id BIGINT = TRY_CONVERT(BIGINT, NULLIF(TRIM(@ModuleInstanceId), N''));
DECLARE @EventCode NVARCHAR(100), @StartValue NVARCHAR(100), @EndValue NVARCHAR(100), @RowCountInsert BIGINT, @RowCountDeleted BIGINT, @EventDetail NVARCHAR(4000);
DECLARE @SuccessIndicator CHAR(1) = 'N';
DECLARE @MessageLog NVARCHAR(MAX);
DECLARE @ErrorMessage NVARCHAR(2048);

IF @Id IS NULL OR @InternalProcessingStatusCode <> N'Proceed'
BEGIN
  -- The Module Instance was closed by its evaluation (Cancel or Abort); nothing to report.
  SELECT @Id AS MODULE_INSTANCE_ID, @InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE, NULL AS EVENT_CODE;
  RETURN;
END;

SELECT TOP 1
   @EventCode      = COALESCE(NULLIF(TRIM([EventCode]), N''), N'Failure')
  ,@StartValue     = NULLIF(TRIM([StartValue]), N'')
  ,@EndValue       = NULLIF(TRIM([EndValue]), N'')
  ,@RowCountInsert = COALESCE([RowCountInsert], 0)
  ,@RowCountDeleted = COALESCE([RowCountDeleted], 0)
  ,@EventDetail    = [EventDetail]
FROM OPENJSON(NULLIF(TRIM(@ModuleResults), N''))
WITH
(
   [ModuleInstanceId] BIGINT
  ,[EventCode]        NVARCHAR(100)
  ,[StartValue]       NVARCHAR(100)
  ,[EndValue]         NVARCHAR(100)
  ,[RowCountInsert]   BIGINT
  ,[RowCountDeleted]  BIGINT
  ,[EventDetail]      NVARCHAR(4000)
)
WHERE [ModuleInstanceId] = @Id;

IF @EventCode IS NULL
BEGIN
  SET @EventCode = N'Failure';
  SET @EventDetail = N'The orchestrator did not report a result for the Module Instance.';
END;

IF @StartValue IS NOT NULL
BEGIN
  EXEC [omd].[SetSourceControlValues] @ModuleInstanceId = @Id, @StartValue = @StartValue, @EndValue = @EndValue;
END;

IF @EventCode = N'Failure' AND @EventDetail IS NOT NULL
BEGIN
  EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = @Id, @EventDetail = @EventDetail;
END;

EXEC [omd].[UpdateModuleInstance]
   @ModuleInstanceId  = @Id
  ,@EventCode         = @EventCode
  ,@RowCountInsert    = @RowCountInsert
  ,@RowCountDeleted   = COALESCE(@RowCountDeleted, 0)
  ,@SuccessIndicator  = @SuccessIndicator OUTPUT
  ,@MessageLog        = @MessageLog OUTPUT;

SELECT @Id AS MODULE_INSTANCE_ID, @InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE, @EventCode AS EVENT_CODE;

IF @SuccessIndicator <> 'Y'
BEGIN
  SET @ErrorMessage = LEFT(N'DIRECT could not close Module Instance ' + CONVERT(NVARCHAR(20), @Id) + N': ' + COALESCE(@MessageLog, N''), 2048);
  THROW 50000, @ErrorMessage, 1;
END;

IF @EventCode = N'Failure'
BEGIN
  SET @ErrorMessage = LEFT(N'Module Instance ' + CONVERT(NVARCHAR(20), @Id) + N' failed: ' + COALESCE(@EventDetail, N'no detail'), 2048);
  THROW 50000, @ErrorMessage, 1;
END;
