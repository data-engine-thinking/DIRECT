/*******************************************************************************
https://github.com/data-solution-automation-engine/DIRECT
Reference data insert and update script

DIRECT Framework v2.2.0

Reference metadata table FRAMEWORK_METADATA stores metadata information.
This script is used to insert and update reference data on deployment.
Any bespoke metadata added manually to the target will be retained,
as long as the keys differ.
To maintain a clean CI/CD process, consider using this script to manage
all reference data for metadata.

[omd_metadata].[FRAMEWORK_METADATA]

*******************************************************************************/

SET NOCOUNT ON;

DECLARE @tblMerge TABLE(
  [CODE]             NVARCHAR (100)  NOT NULL PRIMARY KEY CLUSTERED,
  [VALUE]            NVARCHAR (4000) NULL,
  [GROUP]            NVARCHAR (100)  NOT NULL,
  [DESCRIPTION]      NVARCHAR (4000) NULL,
  [ACTIVE_INDICATOR] CHAR(1)         NOT NULL
);

INSERT INTO @tblMerge([CODE], [VALUE], [GROUP], [DESCRIPTION], [ACTIVE_INDICATOR])
VALUES
   (N'DIRECT_VERSION', N'2.2.0', N'SYSTEM_METADATA',
      N'The current version of the DIRECT Framework and database', 'Y')

  ,(N'LOG_TO_EVENT_LOG', N'Y', N'SETTINGS',
      N'Should the debug message log be logged to the event log', 'Y')

  ,(N'THROW_ON_FAILURE', N'N', N'SETTINGS',
      N'Should procedure failures throw engine errors or ' +
      N'report back to callers through the SuccessIndicator output', 'Y')

  ,(N'DISPLAY_TIMESTAMP_FORMAT', N'yyyy-MM-dd HH:mm:ss', N'SETTINGS',
      N'A valid SQL format string to use for timestamp string representation', 'Y')

  ,(N'DEFAULT_TIMEZONE', N'AUS Eastern Standard Time', N'SETTINGS',
      N'A valid SQL timezone string to use for local timestamp representation '+
      N'(see: `sys.time_zone_info` for valid options)', 'Y')

  ,(N'SP_PROCESS_MESSAGE_LOG', N'Y', N'SETTINGS',
      N'Should the stored procedures populate and process the message log. ' +
      N'The message log is used by the debug parameter, ' +
      N'setting parameter `@Debug = ''Y''` will override this, process messages to the log ' +
      N'and return the log to the client.', 'Y')

  ,(N'SP_PRINT_MESSAGES', N'Y', N'SETTINGS',
      N'Should the stored procedures print messages and the message log, ' +
      N'or just return the message log to the client. ' +
      N'For printing to happen, the @Debug parameter must be set to ''Y''.', 'Y')

  ,(N'FAIL_BATCH_ON_MODULE_FAILURE', N'Y', N'SETTINGS',
      N'Fail the parent Batch on end if any child module has failed', 'Y')

  ,(N'END_MODULE_ON_BATCH_END', N'Y', N'SETTINGS',
      N'End and fail all still running modules on batch end.', 'Y')

  ,(N'AUTO_REGISTER_BATCHES', N'Y', N'SETTINGS',
      N'Register any unregistered, new batches that are instantiated.', 'Y')

  ,(N'AUTO_REGISTER_MODULES', N'Y', N'SETTINGS',
      N'Register any unregistered, new modules that are instantiated.', 'Y')

  ,(N'AUTO_REGISTER_RELATIONSHIPS', N'Y', N'SETTINGS',
      N'Register any unregistered relationships if they are instantiated ' +
      N'as part of an instance run.', 'Y')


MERGE [omd_metadata].[FRAMEWORK_METADATA] AS TARGET
USING @tblMerge AS src
  ON  TARGET.[CODE] = src.[CODE]

WHEN MATCHED THEN UPDATE
  SET [VALUE] = src.[VALUE]
      ,[GROUP] = src.[GROUP]
      ,[DESCRIPTION] = src.[DESCRIPTION]
      ,[ACTIVE_INDICATOR] = src.[ACTIVE_INDICATOR]

WHEN NOT MATCHED THEN
  INSERT  ([CODE], [VALUE], [GROUP], [DESCRIPTION], [ACTIVE_INDICATOR])
  VALUES  ([CODE], [VALUE], [GROUP], [DESCRIPTION], [ACTIVE_INDICATOR]);

GO
