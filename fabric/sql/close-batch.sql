-- DIRECT Run Batch, activity 'Close Batch' (repository database).
-- Reports the Module results to omd.EndBatchModuleInstances and closes the Batch Instance.
-- A child Batch Instance that failed makes the Batch fail as well (used by DIRECT Run Project).
-- With @RaiseError = 'Y' the activity fails (after the bookkeeping) when the Batch failed, so that the pipeline run shows the failure.
-- Parameters: @BatchInstanceId (string), @InternalProcessingStatusCode, @ModuleResults (string, JSON),
--             @BatchEventCode (string, '' for derived), @RaiseError (string, 'Y' or 'N').
SET NOCOUNT ON;

DECLARE @Id BIGINT = TRY_CONVERT(BIGINT, NULLIF(TRIM(@BatchInstanceId), N''));
DECLARE @Results NVARCHAR(MAX) = NULLIF(TRIM(@ModuleResults), N'');
DECLARE @EventCode NVARCHAR(100) = NULLIF(TRIM(@BatchEventCode), N'');
DECLARE @ReportedCount INT, @FailedCount INT, @ExecutionStatusCode NVARCHAR(100);
DECLARE @FailedChildCount INT = 0;
DECLARE @SuccessIndicator CHAR(1) = 'N';
DECLARE @MessageLog NVARCHAR(MAX);
DECLARE @ErrorMessage NVARCHAR(2048);

IF @Id IS NULL OR @InternalProcessingStatusCode <> N'Proceed'
BEGIN
  -- The Batch Instance was closed by its evaluation (Cancel or Abort); nothing to report.
  SELECT @Id AS BATCH_INSTANCE_ID, @InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE, NULL AS EXECUTION_STATUS_CODE, 0 AS REPORTED_COUNT, 0 AS FAILED_COUNT, 0 AS FAILED_CHILD_COUNT;
  RETURN;
END;

-- Child Batch Instances that failed (or were left executing) make this Batch fail
SELECT @FailedChildCount = COUNT(*)
FROM [omd].[BATCH_INSTANCE]
WHERE PARENT_BATCH_INSTANCE_ID = @Id
  AND BATCH_INSTANCE_ID <> @Id
  AND EXECUTION_STATUS_CODE IN (N'Failed', N'Executing');

IF @FailedChildCount > 0 AND @EventCode IS NULL SET @EventCode = N'Failure';

EXEC [omd].[EndBatchModuleInstances]
   @BatchInstanceId      = @Id
  ,@ModuleResults        = @Results
  ,@BatchEventCode       = @EventCode
  ,@ReportedCount        = @ReportedCount OUTPUT
  ,@FailedCount          = @FailedCount OUTPUT
  ,@ExecutionStatusCode  = @ExecutionStatusCode OUTPUT
  ,@SuccessIndicator     = @SuccessIndicator OUTPUT
  ,@MessageLog           = @MessageLog OUTPUT;

SELECT @Id AS BATCH_INSTANCE_ID, @InternalProcessingStatusCode AS INTERNAL_PROCESSING_STATUS_CODE, @ExecutionStatusCode AS EXECUTION_STATUS_CODE, @ReportedCount AS REPORTED_COUNT, @FailedCount AS FAILED_COUNT, @FailedChildCount AS FAILED_CHILD_COUNT;

IF @SuccessIndicator <> 'Y'
BEGIN
  SET @ErrorMessage = LEFT(N'DIRECT could not close Batch Instance ' + CONVERT(NVARCHAR(20), @Id) + N': ' + COALESCE(@MessageLog, N''), 2048);
  THROW 50000, @ErrorMessage, 1;
END;

IF UPPER(COALESCE(@RaiseError, N'Y')) = N'Y' AND (@FailedCount > 0 OR @FailedChildCount > 0 OR @ExecutionStatusCode <> N'Succeeded')
BEGIN
  SET @ErrorMessage = N'Batch Instance ' + CONVERT(NVARCHAR(20), @Id) + N' ended as ' + COALESCE(@ExecutionStatusCode, N'unknown') + N' with '
    + CONVERT(NVARCHAR(10), @FailedCount) + N' failed Module Instance(s) and ' + CONVERT(NVARCHAR(10), @FailedChildCount) + N' failed child Batch Instance(s). See omd_reporting.vw_MODULE_FAILURES and omd_reporting.vw_EXECUTION_LOG_BATCH_INSTANCE.';
  THROW 50000, @ErrorMessage, 1;
END;
