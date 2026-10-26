-- DIRECT Run Batch, activity 'Fail Batch' (repository database). Runs when 'Run Modules' itself failed.
-- Fails all open Module Instances of the Batch Instance and its child Batch Instances, closes them as Failure, logs the error, then fails when @RaiseError = 'Y'.
-- Parameters: @BatchInstanceId (string), @InternalProcessingStatusCode, @ErrorMessage (string), @RaiseError (string, 'Y' or 'N').
SET NOCOUNT ON;

DECLARE @Id BIGINT = TRY_CONVERT(BIGINT, NULLIF(TRIM(@BatchInstanceId), N''));
DECLARE @Detail NVARCHAR(4000) = LEFT(N'The orchestrator failed to run the Modules of the Batch: ' + COALESCE(@ErrorMessage, N'no error message'), 4000);
DECLARE @Message NVARCHAR(2048) = LEFT(@Detail, 2048);

IF @Id IS NOT NULL AND @InternalProcessingStatusCode = N'Proceed'
BEGIN
  EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = 0, @BatchInstanceId = @Id, @EventDetail = @Detail;
  EXEC [omd].[EndBatchModuleInstances] @BatchInstanceId = @Id, @ModuleResults = NULL, @BatchEventCode = N'Failure', @IncludeChildBatches = 'Y';
END;

IF UPPER(COALESCE(@RaiseError, N'Y')) = N'Y' THROW 50000, @Message, 1;

SELECT @Id AS INSTANCE_ID, N'Failure' AS EVENT_CODE;
