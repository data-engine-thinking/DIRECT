-- DIRECT Run Module, activity 'Fail Module' (repository database). Runs when 'Run Modules' itself failed.
-- Fails the Module Instance, logs the error, then fails when @RaiseError = 'Y'.
-- Parameters: @ModuleInstanceId (string), @InternalProcessingStatusCode, @ErrorMessage (string), @RaiseError (string, 'Y' or 'N').
SET NOCOUNT ON;

DECLARE @Id BIGINT = TRY_CONVERT(BIGINT, NULLIF(TRIM(@ModuleInstanceId), N''));
DECLARE @Detail NVARCHAR(4000) = LEFT(N'The orchestrator failed to run the Module: ' + COALESCE(@ErrorMessage, N'no error message'), 4000);
DECLARE @Message NVARCHAR(2048) = LEFT(@Detail, 2048);

IF @Id IS NOT NULL AND @InternalProcessingStatusCode = N'Proceed'
BEGIN
  EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = @Id, @EventDetail = @Detail;
  EXEC [omd].[UpdateModuleInstance] @ModuleInstanceId = @Id, @EventCode = N'Failure';
END;

IF UPPER(COALESCE(@RaiseError, N'Y')) = N'Y' THROW 50000, @Message, 1;

SELECT @Id AS INSTANCE_ID, N'Failure' AS EVENT_CODE;
