/**
 * @procedure [omd].[RunModule]
 * @description
 *   !! THIS IS AN IN-ENGINE EXECUTION PROCEDURE !!
 *   Run a module code in-engine by executing a data logistics process or query
 *   in a DIRECT wrapper in the local database context of the DIRECT database.
 *
 * @package DIRECT Framework
 * @version 2.1.0
 * @see https://github.com/data-solution-automation-engine/DIRECT
 *
 * @param {NVARCHAR(500)} @ModuleCode       [in]  (required)
 *   The code of the module to run.
 * @param {NVARCHAR(MAX)} @Query            [in]  (optional)
 *   An input query, i.e. bespoke SQL or a procedure call.
 *   This will override the executable defined for the Module.
 *   If not provided, the Modules executable code will be run.
 * @param {BIGINT}        @BatchInstanceId  [in]  (optional, default=0)
 *   The Batch Instance Id, if the Module is run from a Batch.
 *   If provided, the module run will be registered with the Batch Instance.
 * @param {NVARCHAR(128)} @ModuleInstanceIdColumnName [in]
 *  (optional, default='MODULE_INSTANCE_ID')
 *  The column name used for the Module Instance Id.
 * @param {CHAR(1)}       @Debug            [in]  (optional, default='N')
 *   Enables debug logging.
 *   If set to 'Y', additional debug information will be logged.
 * @param {BIGINT}        @ModuleInstanceId [out] (optional)
 *   The Module Instance Id created during the execution.
 * @param {DATETIME2}     @ModuleInstanceStartTimestamp [out] (optional)
 *   The start timestamp of the Module Instance.
 * @param {CHAR(1)}       @SuccessIndicator [out] (optional)
 *   'Y' if the module execution was successful, 'N' otherwise.
 * @param {NVARCHAR(MAX)} @MessageLog       [out] (optional)
 *   A structured JSON-format log for diagnostics.
 *
 * @note
 *   This procedure is designed to run a module in-engine, executing the defined process or query
 *   in the context of the DIRECT database. It handles the creation of a Module Instance,
 *   executes the process, and logs the results. It also provides error handling and logging capabilities.
 *
 * @returns {INT} Return code: 0 = success, -1 = failure, -2 = unhandled error.
 *
 * @resultset none
 *
 * @lineage
 * - reads:
 *     table [omd].[MODULE]
 * - writes:
 *     table [omd].[MODULE_INSTANCE]
 *
 * @example

DECLARE @RC INT
  ,@SuccessIndicator CHAR(1)
  ,@MessageLog NVARCHAR(MAX);

EXEC @RC = [omd].[RunModule]
   @ModuleCode = 'MyModule'
  ,@SuccessIndicator = @SuccessIndicator OUTPUT
  ,@MessageLog = @MessageLog OUTPUT;

PRINT(CONCAT('Module run completed. Success: ', @SuccessIndicator));
PRINT(CONCAT('Return Code: ', @RC));
EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

or

EXEC @RC = [omd].[RunModule]
   @ModuleCode = 'MyModule',
  ,@Query = 'SELECT SYSDATETIME() AS CurrentTime'
  ,@Debug = 'Y'
  ,@SuccessIndicator = @SuccessIndicator OUTPUT
  ,@MessageLog = @MessageLog OUTPUT;

PRINT(CONCAT('Module run completed. Success: ', @SuccessIndicator));
PRINT(CONCAT('Return Code: ', @RC));
EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;

 */

CREATE PROCEDURE [omd].[RunModule]
(
   /* Required parameters */
   @ModuleCode                   NVARCHAR(500)    = NULL
   /* Optional parameters with defaults */
  ,@Query                        NVARCHAR(MAX)    = NULL
  ,@BatchInstanceId              BIGINT           = 0
  ,@ModuleInstanceIdColumnName   NVARCHAR(128)    = 'MODULE_INSTANCE_ID'
  ,@Debug                        CHAR(1)          = 'N'
   /* Output parameters */
  ,@ModuleInstanceId             BIGINT           = NULL OUTPUT
  ,@ModuleInstanceStartTimestamp DATETIME2        = NULL OUTPUT
  ,@SuccessIndicator             CHAR(1)          = 'N' OUTPUT
  ,@MessageLog                   NVARCHAR(MAX)    = N'' OUTPUT
)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* standard setup and initialization */
  SET @Debug = CASE WHEN TRIM(UPPER(@Debug)) = 'Y' THEN 'Y' ELSE 'N' END;
  SET @SuccessIndicator = 'N';
  SET @MessageLog = N'[]';
  SET @ModuleInstanceId = NULL;
  SET @ModuleInstanceStartTimestamp = NULL;

  BEGIN TRY
    /* Event and return codes */
    DECLARE @ReturnCode INT = 0;
    DECLARE @EventTypeCode NVARCHAR(100) = N'2';
    DECLARE @EventDetail NVARCHAR(4000) = N'';
    DECLARE @EventReturnCode NVARCHAR(100) = N'';
    DECLARE @LogMessage NVARCHAR(2048);

    /* Load framework settings */
    DECLARE @AddLogsToEventLog CHAR(1)      = [omd_metadata].[GetSettingFlag]('LOG_TO_EVENT_LOG');
    DECLARE @PrintMessages CHAR(1)          = [omd_metadata].[GetSettingFlag]('SP_PRINT_MESSAGES');
    DECLARE @ProcessMessageLog CHAR(1)      = [omd_metadata].[GetSettingFlag]('SP_PROCESS_MESSAGE_LOG');
    DECLARE @ThrowOnFailure CHAR(1)         = [omd_metadata].[GetSettingFlag]('THROW_ON_FAILURE');
    DECLARE @DefaultTimeZone NVARCHAR(4000) = [omd_metadata].[GetSetting]('DEFAULT_TIMEZONE');

/* ----- Validate input parameters ------------------------------------------ */

    IF TRIM(COALESCE(@ModuleCode, '')) = ''
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @LogMessage = N'Parameter @ModuleCode is required.'
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Parameter', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      GOTO EndOfProcedureFailure;
    END;

/* ----- Default logging setup ---------------------------------------------- */

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
      /* Log parameters */
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BModuleCode',
        @ModuleCode, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @Query',
        @Query, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BatchInstanceId',
        CAST(@BatchInstanceId AS NVARCHAR(20)), @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ModuleInstanceIdColumnName',
        @ModuleInstanceIdColumnName, @MessageLog);
    END

/* ----- Start of main process ---------------------------------------------- */

    /* Retrieve the code to execute, if not overridden by the @query parameter. */
    IF @Query IS NULL OR TRIM(@Query) = ''
    BEGIN
      SELECT @Query = [EXECUTABLE] FROM [omd].[MODULE] WHERE MODULE_CODE = @ModuleCode;

      SET @LogMessage = CONCAT('The executable code retrieved is: ''', COALESCE(@Query, ''), '''.');
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
    END
    ELSE
    BEGIN
      SET @LogMessage = CONCAT('An executable code override parameter/query has been provided: ''',
        COALESCE(@Query, ''), '''.');
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
    END

    -- Create Module Instance
    EXEC [omd].[CreateModuleInstance]
      @ModuleCode         = @ModuleCode,
      @Query              = @Query,
      @Debug              = @Debug,
      @BatchInstanceId    = @BatchInstanceId, -- The Batch Instance Id, if the Module is run from a Batch.
      @ModuleInstanceId   = @ModuleInstanceId OUTPUT,
      @ModuleInstanceStartTimestamp = @ModuleInstanceStartTimestamp OUTPUT;

    -- Make sure that a valid module instance was created
    IF @ModuleInstanceId IS NULL
    BEGIN
      -- If not, raise a soft error.
      SET @SuccessIndicator = 'N';
      SET @ModuleInstanceStartTimestamp = NULL;
      SET @LogMessage = CONCAT(N'Failed to register a module instance for Module Code ''', @ModuleCode, N'''.');
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Dependency', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      GOTO EndOfProcedureFailure;
    END

    -- Module Evaluation
    DECLARE @InternalProcessingStatusCode NVARCHAR(100);

    EXEC [omd].[ModuleEvaluation]
      @ModuleInstanceId               = @ModuleInstanceId,
      @Debug                          = @Debug,
      @ModuleInstanceIdColumnName     = @ModuleInstanceIdColumnName,
      @InternalProcessingStatusCode   = @InternalProcessingStatusCode OUTPUT;

      SET @LogMessage = CONCAT('The Processing Status Code is: ', @InternalProcessingStatusCode);
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    IF @InternalProcessingStatusCode NOT IN ('Abort','Cancel') -- These are end-states for the process.
    BEGIN
      -- Replace placeholder variable(s)
      SET @Query = REPLACE(@Query,'@ModuleInstanceId', @ModuleInstanceId);

      -- Run the code
      DECLARE @RowCount BIGINT = 0;
      EXEC(@Query);
      SET @RowCount = @@ROWCOUNT;

      SET @LogMessage = 'The returned row count is '  + CONVERT(NVARCHAR(20),@RowCount);
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      -- Wrap up
      SET @LogMessage = 'Success pathway';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      -- Module Success
      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @RowCountInsert   = @RowCount,
        @RowCountSelect   = 0,
        @Debug            = @Debug,
        @EventCode        = 'Success'

      SET @SuccessIndicator = 'Y';
      GOTO EndOfProcedureSuccess;
    END
    ELSE
    BEGIN
      -- Nothing is done because the internal processing code is either Abort or Cancel.
      -- The process completes successfully.
      SET @SuccessIndicator = 'Y';
      -- SET @ModuleInstanceId = NULL;
      -- SET @ModuleInstanceStartTimestamp = NULL;

      SET @LogMessage = 'Nothing is done, the process reported Abort or Cancel.';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      GOTO EndOfProcedureSuccess;
    END

/* ----- Start of end state management -------------------------------------- */

    EndOfProcedureFailure:
      /* Record the failure in the event log while @LogMessage still holds the specific reason.
         Without this, a failure that produced no module instance - such as a module code that
         does not exist - left no trace in the log tables at all: the only event log write sat
         in the CATCH block, which a soft failure never reaches. */
      SET @EventDetail = COALESCE(NULLIF(TRIM(@LogMessage), N''), N'Run Module process encountered errors.');
      EXEC [omd].[InsertIntoEventLog]
         @ModuleInstanceId  = @ModuleInstanceId
        ,@BatchInstanceId   = @BatchInstanceId
        ,@EventTypeCode     = @EventTypeCode
        ,@EventDetail       = @EventDetail;

      -- close run as failed if there is a module instance id available
      IF @ModuleInstanceId IS NOT NULL
      BEGIN
        EXEC [omd].[UpdateModuleInstance]
          @ModuleInstanceId = @ModuleInstanceId,
          @RowCountInsert   = 0,
          @RowCountSelect   = 0,
          @Debug            = @Debug,
          @EventCode        = 'Failure';
      END
      SET @SuccessIndicator = 'N';
      SET @LogMessage = N'Run Module process encountered errors.';
      IF @ProcessMessageLog = 'Y' SET @MessageLog =
        [omd].[AddLogMessage]('ERROR', DEFAULT, 'Processing Error', @LogMessage, @MessageLog);
      SET @ReturnCode = -1;

      GOTO EndOfProcedure;

    EndOfProcedureSuccess:

      SET @SuccessIndicator = 'Y';
      SET @LogMessage = N'Run Module process completed successfully.';
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

/* ----- Common, standardized, Procedure-wrapping error handling ------------ */

  BEGIN CATCH
    /* reset relevant return/output values */
    SET @SuccessIndicator = 'N';
    SET @ReturnCode = -2;

    -- try to close run as failed if there is a module instance id available
    IF @ModuleInstanceId IS NOT NULL
    BEGIN
      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @RowCountInsert   = 0,
        @RowCountSelect   = 0,
        @Debug            = @Debug,
        @EventCode        = 'Failure';
    END

    IF @ProcessMessageLog = 'Y' SET @MessageLog =
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
       @ModuleInstanceId  = @ModuleInstanceId
      ,@EventTypeCode     = @EventTypeCode
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
