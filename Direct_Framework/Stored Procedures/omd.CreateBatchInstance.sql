/**
 * @procedure [omd].[CreateBatchInstance]
 * @description
 *   Creates/registers a new Batch Instance (execution/run) for a Batch by its code.
 *
 * @package DIRECT Framework
 * @version 2.1.0
 * @see https://github.com/data-solution-automation-engine/DIRECT
 *
 * @param {NVARCHAR(500)}  @BatchCode                     [in]  (required)
 *   The Batch Code (BATCH.BATCH_CODE) for which to create an instance.
 * @param {BIGINT}         @ParentBatchInstanceId         [in]  (optional, default=0)
 *   Parent Batch Instance when creating hierarchical runs; 0 for none.
 * @param {CHAR(1)}        @Debug                         [in]  (optional, default='N')
 *   Enables debug logging.
 * @param {NVARCHAR(4000)} @ExecutionContext              [in]  (optional, default='')
 *   Runtime context (e.g., GUID, SPID) for traceability.
 * @param {BIGINT}         @BatchInstanceId               [out] (optional)
 *   Newly created Batch Instance Id.
 * @param {DATETIME2}      @BatchInstanceStartTimestamp   [out] (optional)
 *   Start timestamp captured at creation.
 * @param {CHAR(1)}        @SuccessIndicator              [out] (optional)
 *   'Y' if creation succeeded, otherwise 'N'.
 * @param {NVARCHAR(MAX)}  @MessageLog                    [out] (optional)
 *   Structured JSON-format log for diagnostics.
 *
 * @resultset none
 *
 * @lineage
 * - reads:
 *     function [omd].[GetBatchIdByName]
 *     function [omd_metadata].[GetFrameworkVersion]
 * - writes:
 *     table [omd].[BATCH_INSTANCE]
 *     procedure [omd].[InsertIntoEventLog]
 *
 * @example
 *

DECLARE @BatchInstanceId BIGINT,
        @BatchInstanceStartTimestamp DATETIME2,
        @SuccessIndicator CHAR(1),
        @MessageLog NVARCHAR(MAX);

EXEC [omd].[CreateBatchInstance]
  @BatchCode = N'MyBatch',
  @Debug = 'Y',
  @ExecutionContext = N'MyContext',
  @BatchInstanceId = @BatchInstanceId OUTPUT,
  @BatchInstanceStartTimestamp = @BatchInstanceStartTimestamp OUTPUT,
  @SuccessIndicator = @SuccessIndicator OUTPUT,
  @MessageLog = @MessageLog OUTPUT;

PRINT @BatchInstanceId;
EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

 */

CREATE PROCEDURE [omd].[CreateBatchInstance]
(
   /* Required parameters */
   @BatchCode                    NVARCHAR(500)  = NULL
   /* Optional parameters */
  ,@ParentBatchInstanceId        BIGINT          = 0
  ,@ExecutionContext             NVARCHAR(4000)  = N''
  ,@Debug                        CHAR(1)         = 'N'
   /* Output parameters */
  ,@BatchInstanceId              BIGINT          = NULL OUTPUT
  ,@BatchInstanceStartTimestamp  DATETIME2       = NULL OUTPUT
  ,@SuccessIndicator             CHAR(1)         = 'N' OUTPUT
  ,@MessageLog                   NVARCHAR(MAX)   = N'' OUTPUT
)
AS
BEGIN
  BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* standard setup and initialization */
    SET @Debug = CASE WHEN TRIM(UPPER(@Debug)) = 'Y' THEN 'Y' ELSE 'N' END;
    SET @SuccessIndicator = 'N';
    SET @MessageLog = N'[]';
    DECLARE @LogMessage NVARCHAR(2048);
    DECLARE @ProcessDescription NVARCHAR(4000) = N'Create Batch Instance process';

    /* Set output variables to default */
    SET @BatchInstanceId = NULL;
    SET @BatchInstanceStartTimestamp = NULL;

    /* Event and return codes */
    DECLARE @ReturnCode INT = 0;
    DECLARE @EventTypeCode NVARCHAR(100) = N'2';
    DECLARE @EventDetail NVARCHAR(4000) = N'';
    DECLARE @EventReturnCode NVARCHAR(100) = N'';

    /* Load framework settings */
    DECLARE @AddLogsToEventLog CHAR(1)      = [omd_metadata].[GetSettingFlag]('LOG_TO_EVENT_LOG');
    DECLARE @PrintMessages CHAR(1)          = [omd_metadata].[GetSettingFlag]('SP_PRINT_MESSAGES');
    DECLARE @ProcessMessageLog CHAR(1)      = [omd_metadata].[GetSettingFlag]('SP_PROCESS_MESSAGE_LOG');
    DECLARE @ThrowOnFailure CHAR(1)         = [omd_metadata].[GetSettingFlag]('THROW_ON_FAILURE');

    DECLARE @AutoRegisterBatches CHAR(1) =
            [omd_metadata].[GetSettingFlag]('AUTO_REGISTER_BATCHES');
    DECLARE @AutoRegisterRelationships CHAR(1) =
            [omd_metadata].[GetSettingFlag]('AUTO_REGISTER_RELATIONSHIPS');
    DECLARE @DefaultTimeZone NVARCHAR(4000) =
            [omd_metadata].[GetSetting]('DEFAULT_TIMEZONE');

    /* ----- Validate input parameters -------------------------------------- */

    IF @BatchCode IS NULL OR TRIM(@BatchCode) = ''
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @LogMessage = N'Parameter @BatchCode is required.'
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Parameter', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      GOTO EndOfProcedureFailure;
    END;

    /* ----- Default logging setup ------------------------------------------ */

    DECLARE @StartTimestamp DATETIME2 = SYSUTCDATETIME();
    DECLARE @StartTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@StartTimestamp);
    DECLARE @SpName NVARCHAR(300) = CONCAT(
      QUOTENAME(COALESCE(OBJECT_SCHEMA_NAME(@@PROCID),'Unknown')), N'.',
      QUOTENAME(COALESCE(OBJECT_NAME(@@PROCID), 'Unknown')));

    IF @ProcessMessageLog = 'Y'
    BEGIN
      /* Log standard metadata */
      SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Procedure',
        @SpName, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Version',
        [omd_metadata].[GetFrameworkVersion](), @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Start Timestamp',
        @StartTimestampString, @MessageLog);

      /* Log parameters in a single JSON block */
      DECLARE @paramsJson NVARCHAR(MAX) = (
        SELECT
          @BatchCode AS BatchCode,
          @ParentBatchInstanceId AS ParentBatchInstanceId,
          @ExecutionContext AS ExecutionContext,
          @Debug AS Debug
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameters',
        @paramsJson, @MessageLog);
    END

    DECLARE @RowsAffected INT = 0;

    /* ----- Start of main process ------------------------------------------ */

    BEGIN TRY
      BEGIN TRANSACTION;

      /* Local procedure variables */
      DECLARE @BatchId INT;
      DECLARE @ParentBatchId INT;

      SELECT @BatchId = [omd].[GetBatchIdByCode](@BatchCode);

      /* If auto-register Batch is enabled, register the Batch if needed */
      IF @BatchId IS NULL AND @AutoRegisterBatches = 'Y'
      BEGIN
        SET @LogMessage = CONCAT(N'Batch Code ''', @BatchCode,
          ''' not found, attempting to auto-register the Batch.');
        IF @ProcessMessageLog = 'Y' SET @MessageLog =
          [omd].[AddLogMessage](DEFAULT, DEFAULT, DEFAULT, @LogMessage, @MessageLog);

        DECLARE @RegisterSuccessIndicator CHAR(1);
        EXEC [omd].[RegisterBatch]
          @BatchCode = @BatchCode,
          @Debug = @Debug,
          @BatchId = @BatchId OUTPUT,
          @SuccessIndicator = @RegisterSuccessIndicator OUTPUT,
          @MessageLog = @MessageLog OUTPUT;

        IF @RegisterSuccessIndicator = 'N' OR @BatchId IS NULL
        BEGIN
          SET @SuccessIndicator = 'N';
          SET @LogMessage = CONCAT(N'Auto-registration of Batch Code ''', @BatchCode,
            ''' failed.');
          IF @ProcessMessageLog = 'Y' SET @MessageLog =
            [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
          IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
          GOTO EndOfProcedureFailure;
        END
      END

      /* Exception handling: The Batch Id cannot be NULL, 0, or negative. */
      IF @BatchId IS NULL OR @BatchId <= 0
      BEGIN
        SET @SuccessIndicator = 'N';
        SET @LogMessage = CONCAT(N'A Valid Batch Id was not found for Batch Code ''', @BatchCode, '''');
        IF @ProcessMessageLog = 'Y' SET @MessageLog =
          [omd].[AddLogMessage]('ERROR', DEFAULT, 'Parameter', @LogMessage, @MessageLog);
        IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
        GOTO EndOfProcedureFailure;
      END

      SET @LogMessage = CONCAT(N'For Batch Code ''', @BatchCode,
        ''' the following Batch Id was found in omd.BATCH: ', @BatchId);
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage](DEFAULT, DEFAULT, DEFAULT, @LogMessage, @MessageLog);

      /* If a ParentBatchInstanceId was provided and auto-register relationships
        is enabled, register any missing relationship */

      IF @ParentBatchInstanceId IS NOT NULL AND @ParentBatchInstanceId > 0
        AND @AutoRegisterRelationships = 'Y'
      BEGIN
        /* Get the Parents BATCH_ID and BATCH_CODE from the instance */
        SET @ParentBatchId = [omd].[GetBatchIdByBatchInstanceId](@ParentBatchInstanceId);
        DECLARE @ParentBatchCode NVARCHAR(500) =
          [omd].[GetBatchCodeById](@ParentBatchId);
        SET @LogMessage = CONCAT(N'Auto-registering any missing Batch relationship ' +
          N'between Parent Batch Code ''', @ParentBatchCode,
          ''' and Child Batch Code ''', @BatchCode, '''.');
        IF @ProcessMessageLog = 'Y' SET @MessageLog =
          [omd].[AddLogMessage](DEFAULT, DEFAULT, DEFAULT, @LogMessage, @MessageLog);
        DECLARE @RegisterRelSuccessIndicator CHAR(1);
        EXEC [omd].[AddBatchToParentBatch]
          @BatchCode = @BatchCode,
          @ParentBatchCode = @ParentBatchCode,
          @Debug = @Debug,
          @SuccessIndicator = @RegisterRelSuccessIndicator OUTPUT,
          @MessageLog = @MessageLog OUTPUT;
        IF @RegisterRelSuccessIndicator = 'N'
        BEGIN
          SET @SuccessIndicator = 'N';
          SET @LogMessage = CONCAT(N'Auto-registration of Batch relationship ' +
            N'between Parent Batch Code ''', @ParentBatchCode,
            ''' and Child Batch Code ''', @BatchCode, ''' failed.');
          IF @ProcessMessageLog = 'Y' SET @MessageLog =
            [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
          IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
          GOTO EndOfProcedureFailure;
        END
      END

      INSERT INTO omd.BATCH_INSTANCE
      (
        [BATCH_ID],
        [PARENT_BATCH_INSTANCE_ID],
        [START_TIMESTAMP],
        [EXECUTION_STATUS_CODE],
        [NEXT_RUN_STATUS_CODE],
        [INTERNAL_PROCESSING_CODE],
        [EXECUTION_CONTEXT]
      )
      VALUES
      (
         @BatchId
        ,@ParentBatchInstanceId
        ,@StartTimestamp -- Start Timestamp (UTC)
        ,N'Executing' -- Execution Status Code
        ,N'Proceed' -- Next Run Indicator
        ,N'Abort' -- Processing Indicator
        ,@ExecutionContext   -- Execution Context, runtime information
      );

      SET @BatchInstanceId = SCOPE_IDENTITY();
      SET @BatchInstanceStartTimestamp = @StartTimestamp;

      SET @LogMessage = CONCAT('A new Batch Instance Id ''', @BatchInstanceId,
        ''' has been created for Batch Code: ', @BatchCode);
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage](DEFAULT, DEFAULT, DEFAULT, @LogMessage, @MessageLog);

      COMMIT TRANSACTION;
      GOTO EndOfProcedureSuccess;
    END TRY
    BEGIN CATCH
      DECLARE
        @TxnErrorMessage NVARCHAR(4000) = ERROR_MESSAGE(),
        @TxnErrorNumber INT = ERROR_NUMBER(),
        @TxnErrorSeverity INT = ERROR_SEVERITY(),
        @TxnErrorState INT = ERROR_STATE(),
        @TxnErrorLine INT = ERROR_LINE();

      IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
      SET @SuccessIndicator = 'N';
      IF COALESCE(TRIM(@MessageLog), '') = '' SET @MessageLog = N'[]';

      SET @LogMessage = CONCAT('Transaction error (', @TxnErrorNumber, '/', @TxnErrorState,
        ') at line ', @TxnErrorLine, ': ', COALESCE(@TxnErrorMessage, 'No additional details.'));
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Transaction Error', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW;
      GOTO EndOfProcedureFailure;
    END CATCH;

    /* ----- Start of end state management ---------------------------------- */

    EndOfProcedureFailure:

      /* The failure jumps inside the main transaction (an unknown Batch code, a failed
         auto-registration) arrive here past both the COMMIT and the CATCH's rollback, which
         left the transaction open and failed the procedure's return with a mismatched
         transaction count (error 266). Roll back any transaction still open. */
      IF @@TRANCOUNT > 0 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;

      SET @SuccessIndicator = 'N';
      SET @LogMessage = CONCAT(@ProcessDescription, N' encountered errors.');
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Processing Error', @LogMessage, @MessageLog);
      SET @ReturnCode = -1;

      GOTO EndOfProcedure;

    EndOfProcedureSuccess:

      SET @SuccessIndicator = 'Y';
      SET @LogMessage = CONCAT(@ProcessDescription, N' completed successfully.');
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('SUCCESS', DEFAULT, 'Processing Completion', @LogMessage, @MessageLog);
      SET @ReturnCode = 0;

      GOTO EndOfProcedure;

    EndOfProcedure:

      DECLARE @EndTimestamp DATETIME2 = SYSUTCDATETIME();
      DECLARE @EndTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@EndTimestamp);
      DECLARE @DurationSeconds NVARCHAR(10) =
        CAST(COALESCE(DATEDIFF(SECOND, @StartTimestamp, @EndTimestamp), 0) AS NVARCHAR(10));

      IF @ProcessMessageLog = 'Y'
      BEGIN
        SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'End Timestamp', @EndTimestampString, @MessageLog);
        SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Elapsed Time (s)', @DurationSeconds, @MessageLog);
        SET @MessageLog =
          [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SuccessIndicator', @SuccessIndicator, @MessageLog);
      END

      IF @Debug = 'Y' AND @ProcessMessageLog = 'Y' AND @PrintMessages = 'Y'
        EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

      RETURN @ReturnCode;
  END TRY

  /* ----- Common, standardized, Procedure-wrapping error handling ---------- */

  BEGIN CATCH
    /* reset all return/output values except the message log */
    SET @SuccessIndicator = 'N';
    SET @ReturnCode = -2;
    SET @BatchInstanceId = NULL;
    SET @BatchInstanceStartTimestamp = NULL;

    IF @ProcessMessageLog <> 'Y' SET @MessageLog = N'[]'
    ELSE SET @MessageLog =
      [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Parameter @SuccessIndicator',
      @SuccessIndicator, @MessageLog);

    DECLARE
      @ErrorMessage     NVARCHAR(4000),
      @ErrorSeverity    NVARCHAR(10),
      @ErrorState       NVARCHAR(10),
      @ErrorProcedure   NVARCHAR(128),
      @ErrorNumber      NVARCHAR(10),
      @ErrorLine        NVARCHAR(10);

    SELECT
      @ErrorMessage   = COALESCE(ERROR_MESSAGE(), 'No Message'),
      @ErrorSeverity  = COALESCE(CAST(ERROR_SEVERITY() AS NVARCHAR(10)), 'N/A'),
      @ErrorState     = COALESCE(CAST(ERROR_STATE()    AS NVARCHAR(10)), 'N/A'),
      @ErrorProcedure = ERROR_PROCEDURE(),
      @ErrorLine      = COALESCE(CAST(ERROR_LINE()     AS NVARCHAR(10)), 'N/A'),
      @ErrorNumber    = COALESCE(CAST(ERROR_NUMBER()   AS NVARCHAR(10)), 'N/A');

    IF @Debug = 'Y' AND @PrintMessages = 'Y'
    BEGIN
      PRINT 'Error in:         ' + @SpName;
      PRINT 'Error Message:    ' + @ErrorMessage;
      PRINT 'Error Severity:   ' + @ErrorSeverity;
      PRINT 'Error State:      ' + @ErrorState;
      PRINT 'Error Procedure:  ' + @ErrorProcedure;
      PRINT 'Error Line:       ' + @ErrorLine;
      PRINT 'Error Number:     ' + @ErrorNumber;
      PRINT 'SuccessIndicator: ' + @SuccessIndicator;
    END;

    SET @EventTypeCode = N'2';
    DECLARE @ErrorProcedureString NVARCHAR(500);
    IF TRIM(ISNULL(@ErrorProcedure, '')) <> ''
      SET @ErrorProcedureString = CONCAT(', called from procedure: ''', @ErrorProcedure, '''');

    SET @EventDetail = CONCAT(
      'Error in procedure: ''', @SpName,''', at line: ''', @ErrorLine, '''',
      @ErrorProcedureString, ', error message:', CHAR(10), @ErrorMessage
    );
    SET @EventReturnCode = ERROR_NUMBER();

    EXEC [omd].[InsertIntoEventLog]
       @EventTypeCode     = @EventTypeCode
      ,@EventDetail       = @EventDetail
      ,@EventReturnCode   = @EventReturnCode;

    IF @ProcessMessageLog = 'Y'
    BEGIN
      SET @MessageLog = [omd].[AddLogMessage]
        ('CRITICAL', DEFAULT, N'Error EventTypeCode', @EventTypeCode, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]
        ('CRITICAL', DEFAULT, N'Error Details', @EventDetail, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]
        ('CRITICAL', DEFAULT, N'Error EventReturnCode', @EventReturnCode, @MessageLog);
    END

    IF @Debug = 'Y' AND @ProcessMessageLog = 'Y' AND @PrintMessages = 'Y'
      EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

    IF @ThrowOnFailure = 'Y' THROW;
    RETURN @ReturnCode;

  END CATCH;
END;
