/*******************************************************************************
 * https://github.com/data-solution-automation-engine/DIRECT
 * Reference data insert and update script
 * DIRECT Framework v2.0
 *
 * [omd].[MODULE_INSTANCE]
 *
 ******************************************************************************/

SET NOCOUNT ON;

SET IDENTITY_INSERT [omd].[MODULE_INSTANCE] ON;

DECLARE @tblMerge TABLE
(
  [MODULE_INSTANCE_ID]        BIGINT          NOT NULL,
  [MODULE_ID]                 INT             NOT NULL,
  [BATCH_INSTANCE_ID]         BIGINT          NOT NULL,
  [START_TIMESTAMP]           DATETIME2       NOT NULL,
  [END_TIMESTAMP]             DATETIME2       NULL,
  [INTERNAL_PROCESSING_CODE]  NVARCHAR (100)  NOT NULL,
  [NEXT_RUN_STATUS_CODE]      NVARCHAR (100)  NOT NULL,
  [EXECUTION_STATUS_CODE]     NVARCHAR (100)  NOT NULL,
  [EXECUTION_CONTEXT]         NVARCHAR (4000) NULL,
  [ROWS_INPUT]                INT             NULL,
  [ROWS_INSERTED]             INT             NULL,
  [ROWS_UPDATED]              INT             NULL,
  [ROWS_DELETED]              INT             NULL,
  [ROWS_DISCARDED]            INT             NULL,
  [ROWS_REJECTED]             INT             NULL,
  [EXECUTED_CODE_CHECKSUM]    VARBINARY(64)   NULL
);

INSERT INTO @tblMerge
(
  [MODULE_INSTANCE_ID],
  [MODULE_ID],
  [BATCH_INSTANCE_ID],
  [START_TIMESTAMP],
  [END_TIMESTAMP],
  [INTERNAL_PROCESSING_CODE],
  [NEXT_RUN_STATUS_CODE],
  [EXECUTION_STATUS_CODE],
  [EXECUTION_CONTEXT],
  [ROWS_INPUT],
  [ROWS_INSERTED],
  [ROWS_UPDATED],
  [ROWS_DELETED],
  [ROWS_DISCARDED],
  [ROWS_REJECTED],
  [EXECUTED_CODE_CHECKSUM]
)
VALUES
(
  0,                                              -- [MODULE_INSTANCE_ID]
  0,                                              -- [MODULE_ID]
  0,                                              -- [BATCH_INSTANCE_ID]
  CAST('0001-01-01T00:00:00.000' AS DATETIME2),   -- [START_TIMESTAMP]
  CAST('9999-12-31T00:00:00.000' AS DATETIME2),   -- [END_TIMESTAMP]
  N'Proceed',                                     -- [INTERNAL_PROCESSING_CODE]
  N'Proceed',                                     -- [NEXT_RUN_STATUS_CODE]
  N'Succeeded',                                   -- [EXECUTION_STATUS_CODE]
  N'N/A',                                         -- [EXECUTION_CONTEXT]
  0,                                              -- [ROWS_INPUT]
  0,                                              -- [ROWS_INSERTED]
  0,                                              -- [ROWS_UPDATED]
  0,                                              -- [ROWS_DELETED]
  0,                                              -- [ROWS_DISCARDED]
  0,                                              -- [ROWS_REJECTED]

  -- special mapping of null or empty query to a 0-hash placeholder in the
  -- omd.MODULE_INSTANCE_EXECUTED_CODE table
  CONVERT(VARBINARY(64), REPLICATE(0x00, 64))     -- [EXECUTED_CODE_CHECKSUM]
)

MERGE [omd].[MODULE_INSTANCE] AS TARGET
USING @tblMerge AS src
  ON TARGET.[MODULE_INSTANCE_ID] = src.[MODULE_INSTANCE_ID]

WHEN MATCHED THEN
  UPDATE
  SET
    [MODULE_ID]                 = src.[MODULE_ID],
    [BATCH_INSTANCE_ID]         = src.[BATCH_INSTANCE_ID],
    [START_TIMESTAMP]           = src.[START_TIMESTAMP],
    [END_TIMESTAMP]             = src.[END_TIMESTAMP],
    [INTERNAL_PROCESSING_CODE]  = src.[INTERNAL_PROCESSING_CODE],
    [NEXT_RUN_STATUS_CODE]      = src.[NEXT_RUN_STATUS_CODE],
    [EXECUTION_STATUS_CODE]     = src.[EXECUTION_STATUS_CODE],
    [EXECUTION_CONTEXT]         = src.[EXECUTION_CONTEXT],
    [ROWS_INPUT]                = src.[ROWS_INPUT],
    [ROWS_INSERTED]             = src.[ROWS_INSERTED],
    [ROWS_UPDATED]              = src.[ROWS_UPDATED],
    [ROWS_DELETED]              = src.[ROWS_DELETED],
    [ROWS_DISCARDED]            = src.[ROWS_DISCARDED],
    [ROWS_REJECTED]             = src.[ROWS_REJECTED],
    [EXECUTED_CODE_CHECKSUM]    = src.[EXECUTED_CODE_CHECKSUM]

WHEN NOT MATCHED THEN
  INSERT
  (
    [MODULE_INSTANCE_ID],
    [MODULE_ID],
    [BATCH_INSTANCE_ID],
    [START_TIMESTAMP],
    [END_TIMESTAMP],
    [INTERNAL_PROCESSING_CODE],
    [NEXT_RUN_STATUS_CODE],
    [EXECUTION_STATUS_CODE],
    [EXECUTION_CONTEXT],
    [ROWS_INPUT],
    [ROWS_INSERTED],
    [ROWS_UPDATED],
    [ROWS_DELETED],
    [ROWS_DISCARDED],
    [ROWS_REJECTED],
    [EXECUTED_CODE_CHECKSUM]
  )
  VALUES
  (
    [MODULE_INSTANCE_ID],
    [MODULE_ID],
    [BATCH_INSTANCE_ID],
    [START_TIMESTAMP],
    [END_TIMESTAMP],
    [INTERNAL_PROCESSING_CODE],
    [NEXT_RUN_STATUS_CODE],
    [EXECUTION_STATUS_CODE],
    [EXECUTION_CONTEXT],
    [ROWS_INPUT],
    [ROWS_INSERTED],
    [ROWS_UPDATED],
    [ROWS_DELETED],
    [ROWS_DISCARDED],
    [ROWS_REJECTED],
    [EXECUTED_CODE_CHECKSUM]
  );

SET IDENTITY_INSERT [omd].[MODULE_INSTANCE] OFF;

GO
