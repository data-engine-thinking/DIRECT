/**
 * @procedure [omd].[ModuleEvaluation]
 * @description Determine whether a Module Instance can proceed based on current and prior instance states.
 *
 * @package DIRECT Framework
 * @version 2.2.0
 * @see https://github.com/data-engine-thinking/DIRECT
 *
 * @param {BIGINT}        @ModuleInstanceId           [in] (required)
 *   The Module Instance Id to evaluate.
 * @param {NVARCHAR(1000)} @ModuleInstanceIdColumnName [in] (optional, default='MODULE_INSTANCE_ID')
 *   Column name used as Module Instance Id for rollback SQL.
 * @param {CHAR(1)}       @ExecuteRollbackIndicator   [in] (optional, default='Y')
 *   'Y' executes the rollback statement against the target data object in this database.
 *   'N' returns the statement in @RollbackStatement instead, for an external orchestrator
 *   whose target data object lives in another engine (such as a Fabric Warehouse).
 *   The Source Control rows of the rolled-back instances are removed in both cases.
 * @param {CHAR(1)}       @Debug                      [in] (optional, default='N')
 *   Enables debug logging.
 * @param {NVARCHAR(100)} @InternalProcessingStatusCode [out] (optional, default='Cancel')
 *   One of: 'Proceed', 'Cancel', 'Abort', 'Rollback'.
 * @param {NVARCHAR(MAX)} @RollbackStatement          [out] (optional)
 *   The rollback DELETE statement for the target data object when @ExecuteRollbackIndicator = 'N'
 *   and a rollback is due; otherwise NULL.
 * @param {CHAR(1)}       @SuccessIndicator           [out] (optional)
 *   'Y' if evaluation completed successfully; otherwise 'N'.
 * @param {NVARCHAR(MAX)} @MessageLog                 [out] (optional)
 *   Structured JSON-format log for diagnostics.
 *
 * @returns {INT} Return code: 0 = success, -1 = failure, -2 = unhandled error.
 *
 * @resultset none
 *
 * @lineage
 * - reads:
 *     tables [omd].[MODULE], [omd].[MODULE_INSTANCE]
 *     functions [omd].[GetModuleIdByModuleInstanceId], [omd].[GetBatchIdByModuleInstanceId]
 *     function [omd_metadata].[GetFrameworkVersion]
 * - writes:
 *     procedures [omd].[InsertIntoEventLog], [omd].[UpdateModuleInstance]
 * - utilities:
 *     function [omd].[AddLogMessage]
 *     procedure [omd].[PrintMessageLog]
 *
 * @example
 * DECLARE @Status NVARCHAR(100), @SuccessIndicator CHAR(1), @MessageLog NVARCHAR(MAX);
 * EXEC [omd].[ModuleEvaluation]
 *   @ModuleInstanceId = 123,
 *   @InternalProcessingStatusCode = @Status OUTPUT,
 *   @SuccessIndicator = @SuccessIndicator OUTPUT,
 *   @MessageLog = @MessageLog OUTPUT;
 * PRINT @Status;
 * EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
 */

CREATE PROCEDURE [omd].[ModuleEvaluation]
(
   -- Mandatory parameters
   @ModuleInstanceId             BIGINT         = NULL
   -- Optional parameters
  ,@ModuleInstanceIdColumnName   NVARCHAR(1000) = 'MODULE_INSTANCE_ID'
  ,@ExecuteRollbackIndicator     CHAR(1)        = 'Y'
  ,@Debug                        CHAR(1)        = 'N'
   -- Output parameters
  ,@InternalProcessingStatusCode NVARCHAR(100)  = 'Cancel' OUTPUT
  ,@RollbackStatement            NVARCHAR(MAX)  = NULL OUTPUT
  ,@SuccessIndicator             CHAR(1)        = 'N' OUTPUT
  ,@MessageLog                   NVARCHAR(MAX)  = N'' OUTPUT
)
AS
BEGIN
  BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @RollbackStatement = NULL;

    -- Default output logging setup
    DECLARE @SpName NVARCHAR(100) = N'[' + OBJECT_SCHEMA_NAME(@@PROCID) + '].[' + OBJECT_NAME(@@PROCID) + ']';
    DECLARE @DirectVersion NVARCHAR(4000) = [omd_metadata].[GetFrameworkVersion]();
    DECLARE @StartTimestamp DATETIME2 = SYSUTCDATETIME();
    DECLARE @StartTimestampString NVARCHAR(20) = FORMAT(@StartTimestamp, 'yyyy-MM-dd HH:mm:ss.fffffff');
    DECLARE @EndTimestamp DATETIME2 = NULL;
    DECLARE @EndTimestampString NVARCHAR(20) = N'';
    DECLARE @LogMessage NVARCHAR(MAX);

    -- Log standard metadata
    SET @LogMessage = @SpName;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Procedure', @LogMessage, @MessageLog)
    SET @LogMessage = @DirectVersion;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Version',@LogMessage, @MessageLog)
    SET @LogMessage = @StartTimestampString;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Start Timestamp', @LogMessage, @MessageLog)

    -- Log parameters
    SET @LogMessage = @ModuleInstanceId;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Parameter @ModuleInstanceId', @LogMessage, @MessageLog)
    SET @LogMessage = @ModuleInstanceIdColumnName;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Parameter @ModuleInstanceIdColumnName', @LogMessage, @MessageLog)

    -- Process variables
    DECLARE @EventDetail NVARCHAR(4000);
    DECLARE @EventReturnCode NVARCHAR(100);

  /*******************************************************************************
   * Start of main process
   ******************************************************************************/

    DECLARE @ModuleId INT;
    DECLARE @BatchId INT;
    DECLARE @MinimumActiveModuleInstance BIGINT;
    DECLARE @ActiveModuleInstanceCount INT;
    DECLARE @BatchModuleActiveIndicator CHAR(1);

    SET @LogMessage = 'Start of the Module Evaluation process. (' + @SpName + ') - ModuleInstanceId: ' + CONVERT(NVARCHAR(20), @ModuleInstanceId)
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    SELECT @ModuleId = omd.GetModuleIdByModuleInstanceId(@ModuleInstanceId);

    -- Exception handling
    -- The Module Id cannot be NULL
    IF @ModuleId IS NULL
    BEGIN
      SET @EventDetail = 'The Module Id was not found for Module Instance Id ''' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + '''';
      EXEC [omd].[InsertIntoEventLog]
        @EventDetail = @EventDetail;

      GOTO  ModuleFailure
    END

    SET @LogMessage = 'For Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + ' the Module Id ' + CONVERT(NVARCHAR(10), @ModuleId) + ' was found in [omd].[MODULE].'
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    /*
      Region: Check for multiple active Module Instances
      Multiple active instances indicate corruption in the DIRECT repository.
    */

    SET @LogMessage = 'Beginning of active instance checks.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    -- Check for the lowest instance of the Module Instances since the process must continue if it's the first of the started instances for the particular Module.
    SELECT @MinimumActiveModuleInstance = MIN(MODULE_INSTANCE_ID)
    FROM omd.MODULE_INSTANCE
    WHERE EXECUTION_STATUS_CODE = 'Executing'
      AND MODULE_ID = @ModuleId
    GROUP BY MODULE_ID

    -- Check if there are no additional running instances other than the current Module Instance. The count should be 1.
    SELECT @ActiveModuleInstanceCount = COUNT(*)
    FROM omd.MODULE_INSTANCE
    WHERE EXECUTION_STATUS_CODE = 'Executing'
       AND MODULE_ID = @ModuleId
       AND MODULE_INSTANCE_ID <> @ModuleInstanceId
    GROUP BY MODULE_ID

    SET @LogMessage = 'The number of active Module Instances is ' + COALESCE(CONVERT(NVARCHAR(10), @ActiveModuleInstanceCount), '0') + '.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    SET @LogMessage = 'The minimum active Module Instance Id is ' + COALESCE(CONVERT(NVARCHAR(10), @MinimumActiveModuleInstance), '0') + '.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    IF (
          (@ActiveModuleInstanceCount IS NULL) OR
          (@ActiveModuleInstanceCount IS NOT NULL AND @MinimumActiveModuleInstance = @ModuleInstanceId)
    )
    BEGIN
      -- Continue, either there is only 1 active instance for the Module (this one) OR this instance is the first of many running instances and this one should be allowed to continue.
      SET @LogMessage = 'Either there is only 1 active instance for the Module (this one) OR this instance is the first (MIN) of many running instances and should be allowed to continue.';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      -- Go to the next step in the process.
      GOTO BatchModuleEvaluation;
    END
    ELSE -- There are already multiple running instances for the same Module, the process must be aborted.
    BEGIN

      SET @LogMessage = 'There are already multiple running instances for the same Module, the process must be aborted. (abort and go to end of procedure).'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      -- Call the Abort event.
      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @EventCode = N'Abort',
        @Debug = @Debug

      SET @InternalProcessingStatusCode = 'Abort';
      SET @SuccessIndicator = 'Y'

      GOTO EndOfProcedure
      -- End
    END

    BatchModuleEvaluation:
    /*
      Region: Batch/Module relationship validation.
      In case the Module is called from a parent Batch this task verifies if the administration is done properly
      and if the Module is disabled as part of the Batch configuration (BATCH_MODULE).

      If the current instance is started from a Batch (Batch Instance <> 0) then the Batch / Module flag must be set to ACTIVE_INDICATOR = 'Y'
      If the current instance has a Batch Instance Id (or Batch Id) of 0 then this step can be skipped, as the Module was not started by a Batch.
    */

    SELECT @BatchId = omd.GetBatchIdByModuleInstanceId(@ModuleInstanceId);

    -- Exception handling, The Batch Id cannot be NULL
    IF @BatchId IS NULL
    BEGIN
      SET @EventDetail = 'The Batch Id was not found for Module Instance Id ''' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + '''';
      EXEC [omd].[InsertIntoEventLog]
        @EventDetail = @EventDetail;

      GOTO ModuleFailure
    END

    SET @LogMessage = 'Start of Batch / Module relationship evaluation.'
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    IF @BatchId = 0 -- The Module was run stand-alone (not from a Batch).
      BEGIN
        -- The Module Instance was not started from a Batch, so processing can skip this step and continue.
        SET @LogMessage = 'The Module Instance was not started from a Batch (0), so processing can skip this step and continue to Rollback Evaluation.'
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

        GOTO RollBackEvaluation -- Go to the next process step after this section.
      END
    ELSE -- Batch Id has a value, so the Module was run from a Batch and we need to check if the Module is active for the Batch.
      BEGIN

        SET @LogMessage = 'The Module Instance was started from a Batch (Id: ' + CONVERT(NVARCHAR(10), @BatchId) + '), so processing will evaluate if the Batch/Module registration is correct.'
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

        -- The Module Instance was started by a Batch, so we must check if the Module is allowed to run.
        SELECT @BatchModuleActiveIndicator = [omd].[GetBatchModuleActiveIndicatorValue](@BatchId, @ModuleId)

        SET @LogMessage = 'The Batch / Module active indicator value is ' + @BatchModuleActiveIndicator
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

        -- If the active indicator at Batch/Module level is set to 'N' the process is disabled in the framework.
        -- In this case, the Module must be cancelled (was attempted to be run, but not allowed to).
        IF (@BatchModuleActiveIndicator = 'N') -- Cancel
        BEGIN
          SET @LogMessage = 'The Module Instance will be cancelled'
          SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

          -- Update the Module Instance to set the Internal Status Processing Code to 'Cancel'.
          EXEC [omd].[UpdateModuleInstance]
            @ModuleInstanceId = @ModuleInstanceId,
            @EventCode = N'Cancel',
            @Debug = @Debug

          SET @InternalProcessingStatusCode = 'Cancel';
          SET @SuccessIndicator = 'Y'

          GOTO EndOfProcedure
      END

      -- If the inactive indicator at Batch/Module level is NULL or unknown then there is an error in the framework registration / setup.
      -- In this case, the Module must be aborted. The module was attempted to be run from a Batch it is not registered for).
      IF (@BatchModuleActiveIndicator = 'U') -- Abort
      BEGIN
        SET @LogMessage = 'The Module Instance will be aborted.'
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

        -- Update the Module Instance to set the Internal Status Processing Code to 'Abort'.
        EXEC [omd].[UpdateModuleInstance]
          @ModuleInstanceId = @ModuleInstanceId,
          @EventCode = N'Abort',
          @Debug = @Debug

        SET @InternalProcessingStatusCode = 'Abort';
        SET @SuccessIndicator = 'Y'

        GOTO EndOfProcedure
      END
      ELSE -- Continue with regular processing
        GOTO RollBackEvaluation

      -- The procedure should not be able to end in this part.
      -- Logging and exception handling
      SET @EventDetail = 'Incorrect Module Evaluation path encountered during BatchModuleEvaluation step.'

      EXEC [omd].[InsertIntoEventLog]
        @ModuleInstanceId = @ModuleInstanceId,
        @EventDetail = @EventDetail;

        GOTO ModuleFailure
    END

    RollBackEvaluation:
    /*
      Region: Rollback.
      Any erroneous previous instances must be rolled-back before processing can continue.
    */

    SET @LogMessage = 'Start of rollback evaluation process step.'
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    DECLARE @PreviousModuleInstanceTable TABLE
    (
      LastBatchInstanceID       BIGINT,
      LastModuleInstanceID      BIGINT,
      LastStartTimestamp        DATETIME2,
      LastEndTimestamp          DATETIME2,
      LastExecutionStatus       NVARCHAR(100),
      LastNextExecutionFlag     NVARCHAR(100),
      LastModuleInstanceIDList  VARCHAR(MAX),
      ActiveIndicator           CHAR(1)
    );

    INSERT @PreviousModuleInstanceTable
    SELECT
       [LastBatchInstanceID]
      ,[LastModuleInstanceID]
      ,[LastStartTimestamp]
      ,[LastEndTimestamp]
      ,[LastExecutionStatus]
      ,[LastNextExecutionFlag]
      ,[LastModuleInstanceIDList]
      ,[ActiveIndicator]
    FROM [omd].[GetPreviousModuleInstanceDetails](@ModuleId, @BatchId)

    /* Internal debug only
    SELECT * FROM @PreviousModuleInstanceTable;
    */

    -- If the previously completed Module Instance (for the same Module) is set to cancel OR the module is set to inactive the run must be cancelled.
    IF (EXISTS (SELECT 1 FROM @PreviousModuleInstanceTable WHERE COALESCE(LastNextExecutionFlag, '') = 'Cancel')
        OR EXISTS (SELECT 1 FROM @PreviousModuleInstanceTable WHERE COALESCE(ActiveIndicator, '') = 'N'))
    BEGIN
      SET @LogMessage = 'The last Execution Flag is ''Cancel'' OR the Active Indicator at Module level is ''N''. The process will be cancelled. The Module Instance will be cancelled'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      -- Call the Cancel (skip) event.
      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @EventCode = N'Cancel',
        @Debug = @Debug

      SET @InternalProcessingStatusCode = N'Cancel';
      SET @SuccessIndicator = 'Y'

      GOTO EndOfProcedure
     END

    -- Proceed with success
    -- If the previous run for the module (the previous Module Instance) was completed successfully and the Module is not disabled, the process can report 'proceed' for
    IF (
        EXISTS (SELECT 1 FROM @PreviousModuleInstanceTable WHERE COALESCE(LastNextExecutionFlag, '') = 'Proceed')
        AND NOT EXISTS (SELECT 1 FROM @PreviousModuleInstanceTable WHERE COALESCE(ActiveIndicator, '')  = 'N')
       )
    BEGIN
      SET @LogMessage = 'The last Execution Flag is ''Proceed'' AND the Active Indicator at Module level is not ''N''. The process can proceed (no rollback is required). The Module Instance will be set to proceed'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @EventCode = N'Proceed',
        @Debug = @Debug

      SET @InternalProcessingStatusCode = N'Proceed';
      SET @SuccessIndicator = 'Y'

      GOTO EndOfProcedure
    END

    -- Proceed with Rollback.
    -- If the previous Module Instance is set to Rollback, this will trigger the current Module instance to do so before proceeding.
    IF ((SELECT MIN(LastNextExecutionFlag) FROM @PreviousModuleInstanceTable) = 'Rollback') AND ((SELECT MIN(ActiveIndicator) FROM @PreviousModuleInstanceTable) <> 'N')
    BEGIN
      SET @LogMessage = 'The last Execution Code is ''Rollback'' and the Active Indicator at Module level is not ''N''. The process should perform a rollback. The Module Instance will be set to rollback'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId = @ModuleInstanceId,
        @EventCode = N'Rollback',
        @Debug = @Debug

      SET @InternalProcessingStatusCode = 'Rollback';
      GOTO CallRollback
    END

    /*
      Region: execution of rollback.
    */

    CallRollback:

    SET @LogMessage = 'Start of rollback evaluation process step.'
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    BEGIN TRY
      -- Call the rollback procedure for the current Module.
      -- Technically, this is rolling back of the previous Module Instance.
      -- This has to happen in the same transaction block to prevent process setting to commence before rollback ends.

    BEGIN -- Rollback
      DECLARE @ModuleInstanceIdList VARCHAR(MAX);
      SET @ModuleInstanceIdList = (SELECT LastModuleInstanceIDList FROM @PreviousModuleInstanceTable);

      SET @LogMessage = 'Input variables are Module ' + CONVERT(VARCHAR(10), @ModuleId) + ' with Previous Module Instance Id list ' + @ModuleInstanceIdList + '.'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      DECLARE @SqlStatement VARCHAR(MAX);
      --DECLARE @AreaCode VARCHAR(10);
      --SELECT @AreaCode = AREA_CODE FROM omd.MODULE WHERE MODULE_ID=@ModuleId;
      DECLARE @TableCode NVARCHAR(1000);
      DECLARE @TableCodeSafe NVARCHAR(1000);
      SELECT @TableCode = DATA_OBJECT_TARGET FROM [omd].[MODULE] WHERE MODULE_ID=@ModuleId;

      -- Safety net to ensure brackets are in place for table names with brackets.
      SELECT @TableCodeSafe = CASE
         WHEN CHARINDEX('[', @TableCode) > 0
           OR CHARINDEX(']', @TableCode) > 0
           THEN @TableCode          -- Already has brackets, leave as-is
         ELSE QUOTENAME(@TableCode) -- No brackets, add them
       END;

      SET @LogMessage = 'The Table Code (DATA_OBJECT_TARGET) for Module ' + CONVERT(VARCHAR(10), @ModuleId) + ' is ' + @TableCodeSafe + '.'
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

      -- Rollback
      BEGIN
        BEGIN TRY

        SET @LogMessage = 'Rollback.'
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

        DECLARE @LocalAreaCode NVARCHAR(100) = (SELECT omd.GetModuleAreaByModuleId(@ModuleId));

        IF @TableCodeSafe <> 'N/A'
        BEGIN
        --IF @LocalAreaCode = 'INT'
          --SET @SqlStatement = 'DELETE FROM '+@TableCodeSafe+' WHERE (omd_module_instance_id IN '+@ModuleInstanceIdList+') OR (omd_update_module_instance_id IN '+@ModuleInstanceIdList+')';
        --ELSE
          -- @TableCodeSafe is already quoted (see the safety net above); quoting it again would break schema-qualified names.
          SET @SqlStatement = 'DELETE FROM ' + @TableCodeSafe + ' WHERE ' + QUOTENAME(@ModuleInstanceIdColumnName) + ' IN (' + @ModuleInstanceIdList + ')';

          SET @LogMessage = 'Rollback SQL statement is: ' + @SqlStatement
          SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

          IF UPPER(COALESCE(@ExecuteRollbackIndicator, 'Y')) = 'Y'
          BEGIN
            EXEC (@SqlStatement);
          END
          ELSE
          BEGIN
            -- The target data object lives in another engine; the orchestrator runs the statement there.
            SET @RollbackStatement = CONVERT(NVARCHAR(MAX), @SqlStatement);
            SET @LogMessage = 'The rollback statement is returned to the caller (@ExecuteRollbackIndicator = N) and not executed here.'
            SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)
          END

          SET @SqlStatement = 'DELETE FROM omd.SOURCE_CONTROL WHERE MODULE_INSTANCE_ID IN (' +
            CASE
              WHEN LEFT(LTRIM(RTRIM(@ModuleInstanceIdList)), 1) = '(' AND RIGHT(LTRIM(RTRIM(@ModuleInstanceIdList)), 1) = ')'
                THEN SUBSTRING(@ModuleInstanceIdList, 2, LEN(@ModuleInstanceIdList) - 2)
              ELSE @ModuleInstanceIdList
            END + ')';

          SET @LogMessage = 'Source Control Rollback SQL statement is: ' + @SqlStatement
          SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

          EXEC (@SqlStatement);
        END
        ELSE
        BEGIN
          SET @LogMessage = 'No rollback is required for '+@TableCodeSafe
          SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)
        END

        END TRY
        BEGIN CATCH
          -- Module Failure
          EXEC [omd].[UpdateModuleInstance]
          @ModuleInstanceId = @ModuleInstanceId,
          @Debug = @Debug,
          @EventCode = 'Failure';

          SET @InternalProcessingStatusCode = 'Failure';

          THROW
        END CATCH
      END

    END -- End of Rollback


      -- After rollback is completed, the process is allowed to continue.
      IF @Debug = 'Y'
        PRINT 'The Module Instance will be set to proceed';

      EXEC [omd].[UpdateModuleInstance]
       @ModuleInstanceId  = @ModuleInstanceId,
       @EventCode         = N'Proceed',
       @Debug             = @Debug

      SET @InternalProcessingStatusCode = 'Proceed';

      GOTO EndOfProcedure

    END TRY
    BEGIN CATCH
        -- Module Failure
      SET @SuccessIndicator = 'N'
      SET @RollbackStatement = NULL;
      EXEC [omd].[UpdateModuleInstance]
        @ModuleInstanceId   = @ModuleInstanceId,
        @Debug              = @Debug,
        @EventCode          = 'Failure';

    SET @InternalProcessingStatusCode = 'Failure';

    -- Logging and exception handling
    SET @EventDetail = 'Failure during rollback process in Module Evaluation, with error: ' + ERROR_MESSAGE();
    SET @EventReturnCode = ERROR_NUMBER();

    EXEC [omd].[InsertIntoEventLog]
      @ModuleInstanceId   = @ModuleInstanceId,
      @EventDetail        = @EventDetail,
      @EventReturnCode    = @EventReturnCode;

      THROW
    END CATCH
    -- All branches completed

    ModuleFailure:
    -- The procedure should not be able to end in this part, so this is just to be sure there is a failure reported when this happens.
    SET @SuccessIndicator = 'N'
    EXEC [omd].[UpdateModuleInstance]
      @ModuleInstanceId   = @ModuleInstanceId,
      @Debug              = @Debug,
      @EventCode          = 'Failure';

    SET @InternalProcessingStatusCode = 'Failure';

    /*
      Region: end of processing, final step.
    */

    SET @LogMessage = 'Module Instance Id ''' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + ''' was processed'
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)
    SET @LogMessage = 'The result (processing status code) is ''' + @InternalProcessingStatusCode + ''''
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog)

    -- End of procedure label
    EndOfProcedure:

    IF @InternalProcessingStatusCode <> 'Failure'
      SET @SuccessIndicator = 'Y'
    -- Otherwise, leave @SuccessIndicator as set earlier (likely 'N' on failure)

    SET @EndTimestamp = SYSUTCDATETIME();
    SET @EndTimestampString = FORMAT(@EndTimestamp, 'yyyy-MM-dd HH:mm:ss.fffffff');

    SET @LogMessage = CONVERT(NVARCHAR(20), DATEDIFF(SECOND, @StartTimestamp, @EndTimestamp)) + N' seconds';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Elapsed Time', @LogMessage, @MessageLog)
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'End Timestamp', @LogMessage, @MessageLog)
    SET @LogMessage = DATEDIFF(SECOND, @StartTimestamp, @EndTimestamp);
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Elapsed Time (s)', @LogMessage, @MessageLog)
    SET @LogMessage = @SuccessIndicator;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Parameter @SuccessIndicator', @LogMessage, @MessageLog)

    IF @Debug = 'Y'
    BEGIN
      EXEC [omd].[PrintMessageLog] @MessageLog;
    END

  END TRY
  BEGIN CATCH
    -- SP-wide error handler and logging
    SET @SuccessIndicator = 'N'
    set @InternalProcessingStatusCode = 'Abort';
    SET @RollbackStatement = NULL;
    SET @LogMessage = @SuccessIndicator;
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Parameter @SuccessIndicator', @LogMessage, @MessageLog)

    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ErrorSeverity INT;
    DECLARE @ErrorState INT;
    DECLARE @ErrorProcedure NVARCHAR(128);
    DECLARE @ErrorNumber INT;
    DECLARE @ErrorLine INT;

    SELECT
      @ErrorMessage   = COALESCE(ERROR_MESSAGE(),     'No Message'    ),
      @ErrorSeverity  = COALESCE(ERROR_SEVERITY(),    -1              ),
      @ErrorState     = COALESCE(ERROR_STATE(),       -1              ),
      @ErrorProcedure = COALESCE(ERROR_PROCEDURE(),   'No Procedure'  ),
      @ErrorLine      = COALESCE(ERROR_LINE(),        -1              ),
      @ErrorNumber    = COALESCE(ERROR_NUMBER(),      -1              );

    IF @Debug = 'Y'
    BEGIN
      PRINT 'Error in '''       + @SpName + ''''
      PRINT 'Error Message: '   + @ErrorMessage
      PRINT 'Error Severity: '  + CONVERT(NVARCHAR(10), @ErrorSeverity)
      PRINT 'Error State: '     + CONVERT(NVARCHAR(10), @ErrorState)
      PRINT 'Error Procedure: ' + @ErrorProcedure
      PRINT 'Error Line: '      + CONVERT(NVARCHAR(10), @ErrorLine)
      PRINT 'Error Number: '    + CONVERT(NVARCHAR(10), @ErrorNumber)
      PRINT 'SuccessIndicator: '+ @SuccessIndicator

      -- Spool message log
      EXEC [omd].[PrintMessageLog] @MessageLog;

    END

    SET @EventDetail = 'Error in ''' + COALESCE(@SpName,'N/A') + ''' from ''' + COALESCE(@ErrorProcedure,'N/A') + ''' at line ''' + CONVERT(NVARCHAR(10), COALESCE(@ErrorLine,'N/A')) + ''': '+ CHAR(10) + COALESCE(@ErrorMessage,'N/A');
    SET @EventReturnCode = ERROR_NUMBER();

    EXEC [omd].[InsertIntoEventLog]
      @EventDetail       = @EventDetail,
      @EventReturnCode   = @EventReturnCode,
      @ModuleInstanceId  = @ModuleInstanceId;

  END CATCH
END
