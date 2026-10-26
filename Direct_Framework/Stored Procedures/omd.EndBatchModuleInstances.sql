/**
 * @procedure [omd].[EndBatchModuleInstances]
 * @description
 *   Close the Module Instances of a Batch Instance from the results reported by an external orchestrator,
 *   and then close the Batch Instance itself.
 *
 *   This is the counterpart of [omd].[CreateBatchModuleInstances]. The orchestrator runs the executables on the
 *   target engine and reports the outcome of every Module Instance as a JSON array. For each reported Module
 *   Instance the load window is recorded in [omd].[SOURCE_CONTROL] (when a start value is reported), the Module
 *   Instance is updated with the reported event and row counts, and a failure detail is written to the event log.
 *
 *   Module Instances of the Batch Instance that are still 'Executing' but were not reported are failed, because
 *   the orchestrator did not come back for them. The Batch Instance then receives the 'Success' event when none of
 *   its Module Instances failed, and the 'Failure' event otherwise. The caller can override the Batch event with
 *   @BatchEventCode.
 *
 *   With @IncludeChildBatches = 'Y' the child Batch Instances that were opened under the Batch Instance (by
 *   [omd].[CreateBatchModuleInstances] with the same option) are closed as well: their Module Instances are accepted
 *   in @ModuleResults, unreported ones are failed, and the child Batch Instances are closed from the deepest level
 *   up. A Batch Instance fails when one of its Module Instances or one of its child Batch Instances failed, which
 *   is how [omd].[RunBatch] behaves. Child Batch Instances that ended in their evaluation (Abort, Cancel) are left
 *   as they are and do not fail the parent.
 *
 *   The JSON array has one object per Module Instance. Keys are matched case-insensitively. Only ModuleInstanceId
 *   is required:
 *
 *   [
 *     {
 *       "ModuleInstanceId": 123,
 *       "EventCode": "Success",            -- 'Success' (default) or 'Failure'
 *       "StartValue": "2026-10-26 07:00:00.000000",
 *       "EndValue":   "2026-10-26 07:05:00.000000",
 *       "RowCountSelect": 0, "RowCountInsert": 0, "RowCountUpdated": 0,
 *       "RowCountDeleted": 0, "RowCountDiscarded": 0, "RowCountRejected": 0,
 *       "EventDetail": "error message, when the Module failed"
 *     }
 *   ]
 *
 * @package DIRECT Framework
 * @version 2.2.0
 * @see https://github.com/data-engine-thinking/DIRECT
 *
 * @param {BIGINT}         @BatchInstanceId     [in]  (required)
 *   The Batch Instance to close. It must be in the 'Executing' state.
 * @param {NVARCHAR(MAX)}  @ModuleResults       [in]  (optional, default=NULL)
 *   JSON array with the outcome per Module Instance, see the description. NULL or an empty array is allowed
 *   for a Batch without Modules.
 * @param {NVARCHAR(100)}  @BatchEventCode      [in]  (optional, default=NULL)
 *   'Success' or 'Failure' to override the Batch event that is derived from the Module Instance outcomes.
 * @param {CHAR(1)}        @IncludeChildBatches [in]  (optional, default='N')
 *   'Y' also closes the child Batch Instances of the Batch Instance, see the description.
 * @param {CHAR(1)}        @Debug               [in]  (optional, default='N')
 *   Enables debug logging.
 * @param {INT}            @ReportedCount       [out] (optional)
 *   The number of Module Instances that were reported and closed.
 * @param {INT}            @FailedCount         [out] (optional)
 *   The number of Module Instances of the Batch Instance (and its child Batch Instances, when included) that ended
 *   in 'Failure', reported or not.
 * @param {INT}            @FailedBatchCount    [out] (optional)
 *   The number of child Batch Instances that ended in 'Failed'. Always 0 without @IncludeChildBatches.
 * @param {NVARCHAR(100)}  @ExecutionStatusCode [out] (optional)
 *   The Execution Status Code the Batch Instance ended with ('Succeeded' or 'Failed').
 * @param {CHAR(1)}        @SuccessIndicator    [out] (optional)
 *   'Y' if the operation completed successfully; otherwise 'N'.
 * @param {NVARCHAR(MAX)}  @MessageLog          [out] (optional)
 *   Structured JSON-format log for diagnostics.
 *
 * @returns {INT} Return code: 0 = success, -1 = failure, -2 = unhandled error.
 *
 * @resultset none
 *
 * @lineage
 * - reads:
 *     table [omd].[BATCH_INSTANCE]
 *     table [omd].[MODULE_INSTANCE]
 *     function [omd_metadata].[GetFrameworkVersion]
 *     function [omd_metadata].[GetTimestampString]
 *     function [omd_metadata].[GetSettingFlag]
 * - writes:
 *     procedure [omd].[SetSourceControlValues]
 *     procedure [omd].[UpdateModuleInstance]
 *     procedure [omd].[UpdateBatchInstance]
 *     procedure [omd].[InsertIntoEventLog]
 * - utilities:
 *     function [omd].[AddLogMessage]
 *     procedure [omd].[PrintMessageLog]
 *
 * @example
 * DECLARE @ReportedCount INT, @FailedCount INT, @ExecutionStatusCode NVARCHAR(100),
 *         @SuccessIndicator CHAR(1), @MessageLog NVARCHAR(MAX);
 * EXEC [omd].[EndBatchModuleInstances]
 *   @BatchInstanceId = 42,
 *   @ModuleResults = N'[{"ModuleInstanceId":123,"EventCode":"Success","StartValue":"2026-10-26 07:00:00","EndValue":"2026-10-26 07:05:00","RowCountInsert":17}]',
 *   @Debug = 'Y',
 *   @ReportedCount = @ReportedCount OUTPUT,
 *   @FailedCount = @FailedCount OUTPUT,
 *   @ExecutionStatusCode = @ExecutionStatusCode OUTPUT,
 *   @SuccessIndicator = @SuccessIndicator OUTPUT,
 *   @MessageLog = @MessageLog OUTPUT;
 * EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
 */

CREATE PROCEDURE [omd].[EndBatchModuleInstances]
(
   -- Mandatory parameters
   @BatchInstanceId        BIGINT          = NULL
   -- Optional parameters
  ,@ModuleResults          NVARCHAR(MAX)   = NULL
  ,@BatchEventCode         NVARCHAR(100)   = NULL
  ,@IncludeChildBatches    CHAR(1)         = 'N'
  ,@Debug                  CHAR(1)         = 'N'
   -- Output parameters
  ,@ReportedCount          INT             = NULL  OUTPUT
  ,@FailedCount            INT             = NULL  OUTPUT
  ,@FailedBatchCount       INT             = NULL  OUTPUT
  ,@ExecutionStatusCode    NVARCHAR(100)   = NULL  OUTPUT
  ,@SuccessIndicator       CHAR(1)         = 'N'   OUTPUT
  ,@MessageLog             NVARCHAR(MAX)   = N''   OUTPUT
)
AS
BEGIN
  BEGIN TRY
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- Prepare/clean standard process/output parameters
    SET @Debug = CASE WHEN UPPER(@Debug) = 'Y' THEN 'Y' ELSE 'N' END;
    SET @SuccessIndicator = 'N';
    SET @MessageLog = N'[]';

    -- Prepare/clean process/output parameters
    SET @ReportedCount = 0;
    SET @FailedCount = 0;
    SET @FailedBatchCount = 0;
    SET @IncludeChildBatches = CASE WHEN UPPER(COALESCE(@IncludeChildBatches, 'N')) = 'Y' THEN 'Y' ELSE 'N' END;
    SET @ExecutionStatusCode = NULL;
    SET @ModuleResults = NULLIF(TRIM(COALESCE(@ModuleResults, N'')), N'');
    SET @BatchEventCode = NULLIF(TRIM(COALESCE(@BatchEventCode, N'')), N'');

    -- Standard setup and initialization
    DECLARE @ReturnCode INT = 0;
    DECLARE @EventDetail NVARCHAR(4000);
    DECLARE @EventReturnCode NVARCHAR(100);
    DECLARE @AddLogsToEventLog CHAR(1) = [omd_metadata].[GetSettingFlag]('LOG_TO_EVENT_LOG');
    DECLARE @ThrowOnFailure CHAR(1) = [omd_metadata].[GetSettingFlag]('THROW_ON_FAILURE');
    DECLARE @StartTimestamp DATETIME2 = SYSUTCDATETIME();
    DECLARE @StartTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@StartTimestamp);
    DECLARE @LogMessage NVARCHAR(MAX);
    DECLARE @SpName NVARCHAR(300) = CONCAT(QUOTENAME(COALESCE(OBJECT_SCHEMA_NAME(@@PROCID),'Unknown')), N'.',
        QUOTENAME(COALESCE(OBJECT_NAME(@@PROCID), 'Unknown')));

    -- Validate input parameters
    IF (@BatchInstanceId IS NULL OR @BatchInstanceId <= 0)
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, N'Missing required parameter @BatchInstanceId.', @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, 'Missing required parameter @BatchInstanceId.', 1;
      GOTO EndOfProcedureFailure;
    END;

    IF @ModuleResults IS NOT NULL AND ISJSON(@ModuleResults) <> 1
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, N'Parameter @ModuleResults is not valid JSON.', @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, 'Parameter @ModuleResults is not valid JSON.', 1;
      GOTO EndOfProcedureFailure;
    END;

    IF @BatchEventCode IS NOT NULL AND @BatchEventCode NOT IN (N'Success', N'Failure')
    BEGIN
      SET @SuccessIndicator = 'N';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, N'Parameter @BatchEventCode must be ''Success'', ''Failure'' or NULL.', @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, 'Parameter @BatchEventCode must be ''Success'', ''Failure'' or NULL.', 1;
      GOTO EndOfProcedureFailure;
    END;

    -- Log standard metadata
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Procedure', @SpName, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Version', [omd_metadata].[GetFrameworkVersion](), @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('DEBUG', DEFAULT, N'Start Timestamp', @StartTimestampString, @MessageLog);

    -- Log parameters
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BatchInstanceId', @BatchInstanceId, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ModuleResults', @ModuleResults, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @BatchEventCode', @BatchEventCode, @MessageLog);
    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @IncludeChildBatches', @IncludeChildBatches, @MessageLog);

/*******************************************************************************
* Start of main process
*******************************************************************************/

    -- The Batch Instance must exist and still be executing
    DECLARE @BatchExecutionStatusCode NVARCHAR(100) = (SELECT EXECUTION_STATUS_CODE FROM [omd].[BATCH_INSTANCE] WHERE BATCH_INSTANCE_ID = @BatchInstanceId);

    IF @BatchExecutionStatusCode IS NULL
    BEGIN
      SET @LogMessage = N'Batch Instance Id ' + CONVERT(NVARCHAR(20), @BatchInstanceId) + N' was not found in omd.BATCH_INSTANCE.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Parameter Error', @LogMessage, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    IF @BatchExecutionStatusCode <> N'Executing'
    BEGIN
      SET @LogMessage = N'Batch Instance Id ' + CONVERT(NVARCHAR(20), @BatchInstanceId) + N' is not executing (Execution Status Code is ''' + @BatchExecutionStatusCode + N''') and cannot be closed again.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      SET @ExecutionStatusCode = @BatchExecutionStatusCode;
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    -- The Batch Instances whose Module Instances are closed by this call: the Batch Instance itself and, when
    -- included, every Batch Instance opened under it.
    DECLARE @BatchInstanceTree TABLE
    (
       BATCH_INSTANCE_ID          BIGINT          NOT NULL PRIMARY KEY
      ,PARENT_BATCH_INSTANCE_ID   BIGINT          NULL
      ,[LEVEL]                    INT             NOT NULL
      ,EXECUTION_STATUS_CODE      NVARCHAR(100)   NULL
    );

    INSERT INTO @BatchInstanceTree (BATCH_INSTANCE_ID, PARENT_BATCH_INSTANCE_ID, [LEVEL], EXECUTION_STATUS_CODE)
    VALUES (@BatchInstanceId, NULL, 0, @BatchExecutionStatusCode);

    IF @IncludeChildBatches = 'Y'
    BEGIN
      ;WITH tree AS
      (
        SELECT bi.BATCH_INSTANCE_ID, bi.PARENT_BATCH_INSTANCE_ID, 1 AS [LEVEL]
        FROM [omd].[BATCH_INSTANCE] bi
        WHERE bi.PARENT_BATCH_INSTANCE_ID = @BatchInstanceId
          AND bi.BATCH_INSTANCE_ID <> @BatchInstanceId
        UNION ALL
        SELECT bi.BATCH_INSTANCE_ID, bi.PARENT_BATCH_INSTANCE_ID, t.[LEVEL] + 1
        FROM [omd].[BATCH_INSTANCE] bi
        JOIN tree t ON bi.PARENT_BATCH_INSTANCE_ID = t.BATCH_INSTANCE_ID
        WHERE bi.BATCH_INSTANCE_ID <> bi.PARENT_BATCH_INSTANCE_ID
          AND t.[LEVEL] < 32
      )
      INSERT INTO @BatchInstanceTree (BATCH_INSTANCE_ID, PARENT_BATCH_INSTANCE_ID, [LEVEL], EXECUTION_STATUS_CODE)
      SELECT t.BATCH_INSTANCE_ID, t.PARENT_BATCH_INSTANCE_ID, t.[LEVEL], bi.EXECUTION_STATUS_CODE
      FROM tree t
      JOIN [omd].[BATCH_INSTANCE] bi ON t.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID;

      SET @LogMessage = N'The Batch Instance has ' + CONVERT(NVARCHAR(10), (SELECT COUNT(*) FROM @BatchInstanceTree WHERE [LEVEL] > 0)) + N' child Batch Instance(s).';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
    END

    -- Interpret the reported results
    DECLARE @Reported TABLE
    (
       ROW_ORDER           INT IDENTITY(1,1) NOT NULL
      ,MODULE_INSTANCE_ID  BIGINT         NULL
      ,EVENT_CODE          NVARCHAR(100)  NULL
      ,START_VALUE         NVARCHAR(100)  NULL
      ,END_VALUE           NVARCHAR(100)  NULL
      ,ROW_COUNT_SELECT    BIGINT         NULL
      ,ROW_COUNT_INSERT    BIGINT         NULL
      ,ROW_COUNT_UPDATED   BIGINT         NULL
      ,ROW_COUNT_DELETED   BIGINT         NULL
      ,ROW_COUNT_DISCARDED BIGINT         NULL
      ,ROW_COUNT_REJECTED  BIGINT         NULL
      ,EVENT_DETAIL        NVARCHAR(4000) NULL
    );

    IF @ModuleResults IS NOT NULL
    BEGIN
      -- Keys are read case-insensitively by lower-casing the key names of every object.
      INSERT INTO @Reported (MODULE_INSTANCE_ID, EVENT_CODE, START_VALUE, END_VALUE, ROW_COUNT_SELECT, ROW_COUNT_INSERT, ROW_COUNT_UPDATED, ROW_COUNT_DELETED, ROW_COUNT_DISCARDED, ROW_COUNT_REJECTED, EVENT_DETAIL)
      SELECT
         TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'moduleinstanceid' THEN kv.[value] END))
        ,NULLIF(TRIM(MAX(CASE WHEN LOWER(kv.[key]) = N'eventcode' THEN kv.[value] END)), N'')
        ,NULLIF(TRIM(MAX(CASE WHEN LOWER(kv.[key]) = N'startvalue' THEN kv.[value] END)), N'')
        ,NULLIF(TRIM(MAX(CASE WHEN LOWER(kv.[key]) = N'endvalue' THEN kv.[value] END)), N'')
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountselect' THEN kv.[value] END))
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountinsert' THEN kv.[value] END))
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountupdated' THEN kv.[value] END))
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountdeleted' THEN kv.[value] END))
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountdiscarded' THEN kv.[value] END))
        ,TRY_CONVERT(BIGINT, MAX(CASE WHEN LOWER(kv.[key]) = N'rowcountrejected' THEN kv.[value] END))
        ,LEFT(MAX(CASE WHEN LOWER(kv.[key]) = N'eventdetail' THEN kv.[value] END), 4000)
      FROM OPENJSON(@ModuleResults) AS arr
      CROSS APPLY OPENJSON(arr.[value]) AS kv
      WHERE arr.[type] = 5 -- objects only
      GROUP BY arr.[key]
      ORDER BY TRY_CONVERT(INT, arr.[key]);
    END

    DECLARE @ResultCount INT = (SELECT COUNT(*) FROM @Reported);
    SET @LogMessage = CONVERT(NVARCHAR(10), @ResultCount) + N' Module Instance result(s) were reported.';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    -- Process the reported results in order
    DECLARE @RowOrder INT = 1;
    DECLARE @ModuleInstanceId BIGINT;
    DECLARE @EventCode NVARCHAR(100);
    DECLARE @StartValue NVARCHAR(100);
    DECLARE @EndValue NVARCHAR(100);
    DECLARE @RowCountSelect BIGINT, @RowCountInsert BIGINT, @RowCountUpdated BIGINT, @RowCountDeleted BIGINT, @RowCountDiscarded BIGINT, @RowCountRejected BIGINT;
    DECLARE @ModuleEventDetail NVARCHAR(4000);
    DECLARE @ModuleBatchInstanceId BIGINT;
    DECLARE @ModuleExecutionStatusCode NVARCHAR(100);
    DECLARE @StepSuccessIndicator CHAR(1);
    DECLARE @StepMessageLog NVARCHAR(MAX);
    DECLARE @ProcessingErrorIndicator CHAR(1) = 'N';

    WHILE @RowOrder <= @ResultCount
    BEGIN
      SELECT
         @ModuleInstanceId   = MODULE_INSTANCE_ID
        ,@EventCode          = COALESCE(EVENT_CODE, N'Success')
        ,@StartValue         = START_VALUE
        ,@EndValue           = END_VALUE
        ,@RowCountSelect     = COALESCE(ROW_COUNT_SELECT, 0)
        ,@RowCountInsert     = COALESCE(ROW_COUNT_INSERT, 0)
        ,@RowCountUpdated    = COALESCE(ROW_COUNT_UPDATED, 0)
        ,@RowCountDeleted    = COALESCE(ROW_COUNT_DELETED, 0)
        ,@RowCountDiscarded  = COALESCE(ROW_COUNT_DISCARDED, 0)
        ,@RowCountRejected   = COALESCE(ROW_COUNT_REJECTED, 0)
        ,@ModuleEventDetail  = EVENT_DETAIL
      FROM @Reported
      WHERE ROW_ORDER = @RowOrder;

      SET @RowOrder = @RowOrder + 1;

      -- Only Success and Failure are accepted; anything else is treated as a Failure with the original value in the event detail.
      IF @EventCode NOT IN (N'Success', N'Failure')
      BEGIN
        SET @ModuleEventDetail = LEFT(N'Unknown event code ''' + @EventCode + N''' reported by the orchestrator. ' + COALESCE(@ModuleEventDetail, N''), 4000);
        SET @EventCode = N'Failure';
      END

      -- The Module Instance must belong to this Batch Instance and still be executing
      SELECT
         @ModuleBatchInstanceId = BATCH_INSTANCE_ID
        ,@ModuleExecutionStatusCode = EXECUTION_STATUS_CODE
      FROM [omd].[MODULE_INSTANCE]
      WHERE MODULE_INSTANCE_ID = @ModuleInstanceId;

      IF @ModuleInstanceId IS NULL OR @ModuleBatchInstanceId IS NULL OR NOT EXISTS (SELECT 1 FROM @BatchInstanceTree WHERE BATCH_INSTANCE_ID = @ModuleBatchInstanceId)
      BEGIN
        SET @LogMessage = N'Reported Module Instance Id ' + COALESCE(CONVERT(NVARCHAR(20), @ModuleInstanceId), N'NULL') + N' does not belong to Batch Instance Id ' + CONVERT(NVARCHAR(20), @BatchInstanceId)
          + CASE WHEN @IncludeChildBatches = 'Y' THEN N' or its child Batch Instances' ELSE N'' END + N' and is skipped.';
        SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
        SET @EventDetail = LEFT(@LogMessage, 4000);
        IF @AddLogsToEventLog = 'Y' EXEC [omd].[InsertIntoEventLog] @ModuleInstanceId = 0, @EventDetail = @EventDetail, @BatchInstanceId = @BatchInstanceId;
        SET @ProcessingErrorIndicator = 'Y';
        CONTINUE;
      END

      IF @ModuleExecutionStatusCode <> N'Executing'
      BEGIN
        SET @LogMessage = N'Reported Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' is not executing (Execution Status Code is ''' + @ModuleExecutionStatusCode + N''') and is skipped.';
        SET @MessageLog = [omd].[AddLogMessage]('WARNING', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
        CONTINUE;
      END

      -- Record the load window
      IF @StartValue IS NOT NULL
      BEGIN
        EXEC [omd].[SetSourceControlValues]
           @ModuleInstanceId  = @ModuleInstanceId
          ,@StartValue        = @StartValue
          ,@EndValue          = @EndValue
          ,@Debug             = @Debug
          ,@SuccessIndicator  = @StepSuccessIndicator OUTPUT
          ,@MessageLog        = @StepMessageLog OUTPUT;

        IF @StepSuccessIndicator <> 'Y'
        BEGIN
          SET @LogMessage = N'The load window for Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' could not be recorded.';
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'SetSourceControlValues Message Log', @StepMessageLog, @MessageLog);
          SET @ProcessingErrorIndicator = 'Y';
        END
      END

      -- Failure detail to the event log
      IF @EventCode = N'Failure' AND @ModuleEventDetail IS NOT NULL
      BEGIN
        EXEC [omd].[InsertIntoEventLog]
           @ModuleInstanceId  = @ModuleInstanceId
          ,@EventDetail       = @ModuleEventDetail
          ,@BatchInstanceId   = @BatchInstanceId
          ,@Debug             = @Debug;
      END

      -- Close the Module Instance
      EXEC [omd].[UpdateModuleInstance]
         @ModuleInstanceId   = @ModuleInstanceId
        ,@EventCode          = @EventCode
        ,@RowCountSelect     = @RowCountSelect
        ,@RowCountInsert     = @RowCountInsert
        ,@RowCountUpdated    = @RowCountUpdated
        ,@RowCountDeleted    = @RowCountDeleted
        ,@RowCountDiscarded  = @RowCountDiscarded
        ,@RowCountRejected   = @RowCountRejected
        ,@Debug              = @Debug
        ,@SuccessIndicator   = @StepSuccessIndicator OUTPUT
        ,@MessageLog         = @StepMessageLog OUTPUT;

      IF @StepSuccessIndicator <> 'Y'
      BEGIN
        SET @LogMessage = N'Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' could not be updated with event ''' + @EventCode + N'''.';
        SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
        SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'UpdateModuleInstance Message Log', @StepMessageLog, @MessageLog);
        SET @ProcessingErrorIndicator = 'Y';
        CONTINUE;
      END

      SET @ReportedCount = @ReportedCount + 1;
      SET @LogMessage = N'Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' was closed with event ''' + @EventCode + N'''.';
      SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);
    END

    -- Module Instances of this Batch Instance (and its child Batch Instances) that are still executing were not reported by the orchestrator; they are failed.
    DECLARE @Unreported TABLE (ROW_ORDER INT IDENTITY(1,1) NOT NULL, MODULE_INSTANCE_ID BIGINT NOT NULL, BATCH_INSTANCE_ID BIGINT NOT NULL);

    INSERT INTO @Unreported (MODULE_INSTANCE_ID, BATCH_INSTANCE_ID)
    SELECT MODULE_INSTANCE_ID, BATCH_INSTANCE_ID
    FROM [omd].[MODULE_INSTANCE]
    WHERE BATCH_INSTANCE_ID IN (SELECT BATCH_INSTANCE_ID FROM @BatchInstanceTree)
      AND EXECUTION_STATUS_CODE = N'Executing'
    ORDER BY MODULE_INSTANCE_ID;

    DECLARE @UnreportedCount INT = @@ROWCOUNT;
    SET @RowOrder = 1;

    WHILE @RowOrder <= @UnreportedCount
    BEGIN
      SELECT @ModuleInstanceId = MODULE_INSTANCE_ID, @ModuleBatchInstanceId = BATCH_INSTANCE_ID FROM @Unreported WHERE ROW_ORDER = @RowOrder;
      SET @RowOrder = @RowOrder + 1;

      SET @ModuleEventDetail = N'The Module Instance was still executing when the Batch Instance was closed and no result was reported by the orchestrator.';
      SET @LogMessage = N'Module Instance Id ' + CONVERT(NVARCHAR(20), @ModuleInstanceId) + N' was not reported and is failed.';
      SET @MessageLog = [omd].[AddLogMessage]('WARNING', DEFAULT, N'Status Update', @LogMessage, @MessageLog);

      EXEC [omd].[InsertIntoEventLog]
         @ModuleInstanceId  = @ModuleInstanceId
        ,@EventDetail       = @ModuleEventDetail
        ,@BatchInstanceId   = @ModuleBatchInstanceId
        ,@Debug             = @Debug;

      EXEC [omd].[UpdateModuleInstance]
         @ModuleInstanceId   = @ModuleInstanceId
        ,@EventCode          = N'Failure'
        ,@Debug              = @Debug;
    END

    -- Child Batch Instances are closed from the deepest level up; a Batch Instance fails when one of its Module
    -- Instances or one of its child Batch Instances failed.
    IF @IncludeChildBatches = 'Y'
    BEGIN
      DECLARE @ChildBatchInstances TABLE (ROW_ORDER INT IDENTITY(1,1) NOT NULL, BATCH_INSTANCE_ID BIGINT NOT NULL);

      INSERT INTO @ChildBatchInstances (BATCH_INSTANCE_ID)
      SELECT BATCH_INSTANCE_ID
      FROM @BatchInstanceTree
      WHERE [LEVEL] > 0
        AND COALESCE(EXECUTION_STATUS_CODE, N'') = N'Executing'
      ORDER BY [LEVEL] DESC, BATCH_INSTANCE_ID;

      DECLARE @ChildCount INT = @@ROWCOUNT;
      DECLARE @ChildBatchInstanceId BIGINT;
      DECLARE @ChildEventCode NVARCHAR(100);
      SET @RowOrder = 1;

      WHILE @RowOrder <= @ChildCount
      BEGIN
        SELECT @ChildBatchInstanceId = BATCH_INSTANCE_ID FROM @ChildBatchInstances WHERE ROW_ORDER = @RowOrder;
        SET @RowOrder = @RowOrder + 1;

        SET @ChildEventCode =
          CASE
            WHEN EXISTS (SELECT 1 FROM [omd].[MODULE_INSTANCE] WHERE BATCH_INSTANCE_ID = @ChildBatchInstanceId AND EXECUTION_STATUS_CODE = N'Failed')
              OR EXISTS (SELECT 1 FROM [omd].[BATCH_INSTANCE] WHERE PARENT_BATCH_INSTANCE_ID = @ChildBatchInstanceId AND BATCH_INSTANCE_ID <> @ChildBatchInstanceId AND EXECUTION_STATUS_CODE = N'Failed')
            THEN N'Failure'
            ELSE N'Success'
          END;

        SET @LogMessage = N'Child Batch Instance Id ' + CONVERT(NVARCHAR(20), @ChildBatchInstanceId) + N' ends with event ''' + @ChildEventCode + N'''.';
        SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

        EXEC [omd].[UpdateBatchInstance]
           @BatchInstanceId   = @ChildBatchInstanceId
          ,@EventCode         = @ChildEventCode
          ,@Debug             = @Debug
          ,@SuccessIndicator  = @StepSuccessIndicator OUTPUT
          ,@MessageLog        = @StepMessageLog OUTPUT;

        IF @StepSuccessIndicator <> 'Y'
        BEGIN
          SET @LogMessage = N'Child Batch Instance Id ' + CONVERT(NVARCHAR(20), @ChildBatchInstanceId) + N' could not be updated with event ''' + @ChildEventCode + N'''.';
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
          SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'UpdateBatchInstance Message Log', @StepMessageLog, @MessageLog);
          SET @ProcessingErrorIndicator = 'Y';
        END
      END

      SET @FailedBatchCount = (SELECT COUNT(*) FROM [omd].[BATCH_INSTANCE] WHERE BATCH_INSTANCE_ID IN (SELECT BATCH_INSTANCE_ID FROM @BatchInstanceTree WHERE [LEVEL] > 0) AND EXECUTION_STATUS_CODE = N'Failed');
    END

    -- Batch outcome
    SET @FailedCount = (SELECT COUNT(*) FROM [omd].[MODULE_INSTANCE] WHERE BATCH_INSTANCE_ID IN (SELECT BATCH_INSTANCE_ID FROM @BatchInstanceTree) AND EXECUTION_STATUS_CODE = N'Failed');

    DECLARE @DerivedBatchEventCode NVARCHAR(100) =
      CASE WHEN @FailedCount > 0 OR @FailedBatchCount > 0 OR @ProcessingErrorIndicator = 'Y' THEN N'Failure' ELSE N'Success' END;
    DECLARE @FinalBatchEventCode NVARCHAR(100) = COALESCE(@BatchEventCode, @DerivedBatchEventCode);

    SET @LogMessage = N'The Batch Instance ends with event ''' + @FinalBatchEventCode + N''' ('
      + CONVERT(NVARCHAR(10), @ReportedCount) + N' reported, ' + CONVERT(NVARCHAR(10), @UnreportedCount) + N' unreported, '
      + CONVERT(NVARCHAR(10), @FailedCount) + N' failed Module Instance(s), ' + CONVERT(NVARCHAR(10), @FailedBatchCount) + N' failed child Batch Instance(s)).';
    SET @MessageLog = [omd].[AddLogMessage](DEFAULT, DEFAULT, N'Status Update', @LogMessage, @MessageLog);

    EXEC [omd].[UpdateBatchInstance]
       @BatchInstanceId   = @BatchInstanceId
      ,@EventCode         = @FinalBatchEventCode
      ,@Debug             = @Debug
      ,@SuccessIndicator  = @StepSuccessIndicator OUTPUT
      ,@MessageLog        = @StepMessageLog OUTPUT;

    SET @ExecutionStatusCode = (SELECT EXECUTION_STATUS_CODE FROM [omd].[BATCH_INSTANCE] WHERE BATCH_INSTANCE_ID = @BatchInstanceId);

    IF @StepSuccessIndicator <> 'Y'
    BEGIN
      SET @LogMessage = N'Batch Instance Id ' + CONVERT(NVARCHAR(20), @BatchInstanceId) + N' could not be updated with event ''' + @FinalBatchEventCode + N'''.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'Status Update', @LogMessage, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, N'UpdateBatchInstance Message Log', @StepMessageLog, @MessageLog);
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    -- A reporting problem on one of the Module Instances makes the call itself a failure, so that the orchestrator notices.
    IF @ProcessingErrorIndicator = 'Y'
    BEGIN
      SET @LogMessage = N'One or more reported Module Instance results could not be processed; see the message log.';
      IF @ThrowOnFailure = 'Y' THROW 50000, @LogMessage, 1;
      ELSE GOTO EndOfProcedureFailure;
    END

    SET @SuccessIndicator = 'Y';
    GOTO EndOfProcedureSuccess;

/*******************************************************************************
* Start of end state management
*******************************************************************************/

    EndOfProcedureFailure:
      SET @SuccessIndicator = 'N';
      SET @LogMessage = N'End Batch Module Instances process encountered errors.';
      SET @MessageLog = [omd].[AddLogMessage]('ERROR', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
      SET @ReturnCode = -1;
      GOTO EndOfProcedure;

    EndOfProcedureSuccess:
      SET @SuccessIndicator = 'Y';
      SET @LogMessage = N'End Batch Module Instances process completed successfully.';
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, DEFAULT, @LogMessage, @MessageLog);
      SET @ReturnCode = 0;
      GOTO EndOfProcedure;

    EndOfProcedure:
      DECLARE @EndTimestamp DATETIME2 = SYSUTCDATETIME();
      DECLARE @EndTimestampString NVARCHAR(4000) = [omd_metadata].[GetTimestampString](@EndTimestamp);
      DECLARE @DurationSeconds NVARCHAR(10) = CONVERT(NVARCHAR(10), COALESCE(DATEDIFF(SECOND, @StartTimestamp, @EndTimestamp), 0));
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'End Timestamp', @EndTimestampString, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Elapsed Time (s)', @DurationSeconds, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ReportedCount', @ReportedCount, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @FailedCount', @FailedCount, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @ExecutionStatusCode', @ExecutionStatusCode, @MessageLog);
      SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SuccessIndicator', @SuccessIndicator, @MessageLog);
      IF @Debug = 'Y' EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
      RETURN @ReturnCode;

  END TRY
/*******************************************************************************
* Common, standardized, Procedure-wrapping error handling
*******************************************************************************/
  BEGIN CATCH
    -- Reset output parameters
    SET @SuccessIndicator = 'N';
    SET @ReportedCount = COALESCE(@ReportedCount, 0);
    SET @FailedCount = COALESCE(@FailedCount, 0);
    SET @FailedBatchCount = COALESCE(@FailedBatchCount, 0);
    SET @ExecutionStatusCode = @ExecutionStatusCode; -- keeps the status reached, if any; assignment required on every path

    SET @MessageLog = [omd].[AddLogMessage]('INFO', DEFAULT, N'Parameter @SuccessIndicator Exit Value', @SuccessIndicator, @MessageLog);

    DECLARE
      @ErrorMessage NVARCHAR(4000),
      @ErrorSeverity INT,
      @ErrorState INT,
      @ErrorProcedure NVARCHAR(128),
      @ErrorNumber INT,
      @ErrorLine INT;

    SELECT
      @ErrorMessage   = COALESCE(ERROR_MESSAGE(),     'No Message'    ),
      @ErrorSeverity  = COALESCE(ERROR_SEVERITY(),    -1              ),
      @ErrorState     = COALESCE(ERROR_STATE(),       -1              ),
      @ErrorProcedure = COALESCE(ERROR_PROCEDURE(),   'No Procedure'  ),
      @ErrorLine      = COALESCE(ERROR_LINE(),        -1              ),
      @ErrorNumber    = COALESCE(ERROR_NUMBER(),      -1              );

    IF @Debug = 'Y'
    BEGIN
      PRINT 'Error in:         ' + @SpName;
      PRINT 'Error Message:    ' + @ErrorMessage;
      PRINT 'Error Severity:   ' + CONVERT(NVARCHAR(10), @ErrorSeverity);
      PRINT 'Error State:      ' + CONVERT(NVARCHAR(10), @ErrorState);
      PRINT 'Error Procedure:  ' + @ErrorProcedure;
      PRINT 'Error Line:       ' + CONVERT(NVARCHAR(10), @ErrorLine);
      PRINT 'Error Number:     ' + CONVERT(NVARCHAR(10), @ErrorNumber);
      PRINT 'SuccessIndicator: ' + @SuccessIndicator;

      -- Spool full message log
      EXEC [omd].[PrintMessageLog] @MessageLog = @MessageLog;
    END;
    IF @AddLogsToEventLog = 'Y'
    BEGIN
      SET @EventDetail =
        CONCAT('Error in ''', @SpName,
        ''' from ''', @ErrorProcedure, ''' at line ''',
        CONVERT(NVARCHAR(10), COALESCE(@ErrorLine,'N/A')), ''': ', CHAR(10),
        COALESCE(@ErrorMessage,'N/A'));
      SET @EventReturnCode = ERROR_NUMBER();
      DECLARE @EventBatchInstanceId BIGINT = COALESCE(@BatchInstanceId, 0);

      EXEC [omd].[InsertIntoEventLog]
         @ModuleInstanceId  = 0
        ,@EventDetail       = @EventDetail
        ,@BatchInstanceId   = @EventBatchInstanceId
        ,@EventReturnCode   = @EventReturnCode
        ,@Debug             = @Debug

      SET @MessageLog = [omd].[AddLogMessage] ('CRITICAL', DEFAULT, N'Error Details', @EventDetail, @MessageLog);
    END
    IF @ThrowOnFailure = 'Y' THROW 50000, @EventDetail, 1;

    RETURN -2;

  END CATCH
END;
