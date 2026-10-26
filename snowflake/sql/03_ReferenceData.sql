/*
 * DIRECT Framework - Snowflake edition
 * 03 Reference data and settings
 *
 * The reference data is merged, so the script can be run again. The settings
 * keep their value when they already exist; only new settings are added.
 */

MERGE INTO <% database %>.OMD_METADATA.LAYER AS tgt
USING (SELECT * FROM VALUES
    ('Integration',  'The Integration Layer'),
    ('Presentation', 'The Presentation Layer'),
    ('Staging',      'The Staging Layer'),
    ('Maintenance',  'Internal Data Solution')
  AS src (LAYER_CODE, LAYER_DESCRIPTION)) AS src
ON tgt.LAYER_CODE = src.LAYER_CODE
WHEN MATCHED THEN UPDATE SET LAYER_DESCRIPTION = src.LAYER_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (LAYER_CODE, LAYER_DESCRIPTION) VALUES (src.LAYER_CODE, src.LAYER_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.AREA AS tgt
USING (SELECT * FROM VALUES
    ('HELPER', 'Presentation', 'The Helper Area'),
    ('INT',    'Integration',  'The Base Integration Area'),
    ('INTPR',  'Integration',  'The Derived Integration Area'),
    ('LND',    'Staging',      'The Landing Area of the Staging Layer'),
    ('MAINT',  'Maintenance',  'Internal Data Solution'),
    ('PRES',   'Presentation', 'The Access Area'),
    ('PSA',    'Staging',      'The Persistent Staging Area'),
    ('STG',    'Staging',      'The Staging Area of the Staging Layer'),
    ('SYNC',   'Staging',      'Synchronization of the production History Area of the Staging Layer')
  AS src (AREA_CODE, LAYER_CODE, AREA_DESCRIPTION)) AS src
ON tgt.AREA_CODE = src.AREA_CODE
WHEN MATCHED THEN UPDATE SET LAYER_CODE = src.LAYER_CODE, AREA_DESCRIPTION = src.AREA_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (AREA_CODE, LAYER_CODE, AREA_DESCRIPTION) VALUES (src.AREA_CODE, src.LAYER_CODE, src.AREA_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.EVENT_TYPE AS tgt
USING (SELECT * FROM VALUES
    (1, 'Infrastructure error.'),
    (2, 'Internal data integration process error or system generated event.'),
    (3, 'Custom exception handling that has been implemented in code (Error Bitmaps).')
  AS src (EVENT_TYPE_CODE, EVENT_TYPE_DESCRIPTION)) AS src
ON tgt.EVENT_TYPE_CODE = src.EVENT_TYPE_CODE
WHEN MATCHED THEN UPDATE SET EVENT_TYPE_DESCRIPTION = src.EVENT_TYPE_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (EVENT_TYPE_CODE, EVENT_TYPE_DESCRIPTION) VALUES (src.EVENT_TYPE_CODE, src.EVENT_TYPE_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.EXECUTION_STATUS AS tgt
USING (SELECT * FROM VALUES
    ('Aborted',   'The instance was attempted but could not start, typically because another instance of the same Batch or Module is already running, or because the Module was run from a Batch it is not registered for. No data was processed.'),
    ('Cancelled', 'The instance was attempted but the framework found that it was not necessary to run it: the Batch, Module or Batch/Module relationship is inactive, or the Module completed successfully in an earlier run of a Batch that is being restarted.'),
    ('Executing', 'The instance is running. This is a transient state; it is replaced by an end state when the instance completes.'),
    ('Failed',    'The instance completed with failures.'),
    ('Succeeded', 'The instance completed successfully.')
  AS src (EXECUTION_STATUS_CODE, EXECUTION_STATUS_DESCRIPTION)) AS src
ON tgt.EXECUTION_STATUS_CODE = src.EXECUTION_STATUS_CODE
WHEN MATCHED THEN UPDATE SET EXECUTION_STATUS_DESCRIPTION = src.EXECUTION_STATUS_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (EXECUTION_STATUS_CODE, EXECUTION_STATUS_DESCRIPTION) VALUES (src.EXECUTION_STATUS_CODE, src.EXECUTION_STATUS_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.INTERNAL_PROCESSING_STATUS AS tgt
USING (SELECT * FROM VALUES
    ('Abort',    'Another instance of the same Batch or Module is already running, or the configuration is inconsistent. All further processing stops; the Execution Status becomes Aborted.'),
    ('Cancel',   'The evaluation found that it is not necessary to run this instance. All further processing stops; the Execution Status becomes Cancelled.'),
    ('Proceed',  'The instance can continue to the next step. This is the default value; every step continues only when the status is Proceed.'),
    ('Rollback', 'Set temporarily during the rollback of earlier failed instances. After the rollback the status is set to Proceed again.')
  AS src (INTERNAL_PROCESSING_STATUS_CODE, INTERNAL_PROCESSING_STATUS_DESCRIPTION)) AS src
ON tgt.INTERNAL_PROCESSING_STATUS_CODE = src.INTERNAL_PROCESSING_STATUS_CODE
WHEN MATCHED THEN UPDATE SET INTERNAL_PROCESSING_STATUS_DESCRIPTION = src.INTERNAL_PROCESSING_STATUS_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (INTERNAL_PROCESSING_STATUS_CODE, INTERNAL_PROCESSING_STATUS_DESCRIPTION) VALUES (src.INTERNAL_PROCESSING_STATUS_CODE, src.INTERNAL_PROCESSING_STATUS_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.NEXT_RUN_STATUS AS tgt
USING (SELECT * FROM VALUES
    ('Cancel',   'Set by an administrator to skip the next run of the Batch or Module once.'),
    ('Proceed',  'The next run continues normally. This is the default value.'),
    ('Rollback', 'Set when an instance fails, so that the next run rolls back the data of the failed instance before it continues. An administrator can set it to force a rollback.')
  AS src (NEXT_RUN_STATUS_CODE, NEXT_RUN_STATUS_DESCRIPTION)) AS src
ON tgt.NEXT_RUN_STATUS_CODE = src.NEXT_RUN_STATUS_CODE
WHEN MATCHED THEN UPDATE SET NEXT_RUN_STATUS_DESCRIPTION = src.NEXT_RUN_STATUS_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (NEXT_RUN_STATUS_CODE, NEXT_RUN_STATUS_DESCRIPTION) VALUES (src.NEXT_RUN_STATUS_CODE, src.NEXT_RUN_STATUS_DESCRIPTION);

MERGE INTO <% database %>.OMD_METADATA.FREQUENCY AS tgt
USING (SELECT * FROM VALUES
    ('Continuous', 'Continuously running integration processing unit.'),
    ('Triggered',  'Event triggered processing unit.'),
    ('On-demand',  'On-demand processing unit.'),
    ('Scheduled',  'Scheduled processing unit.')
  AS src (FREQUENCY_CODE, FREQUENCY_DESCRIPTION)) AS src
ON tgt.FREQUENCY_CODE = src.FREQUENCY_CODE
WHEN MATCHED THEN UPDATE SET FREQUENCY_DESCRIPTION = src.FREQUENCY_DESCRIPTION
WHEN NOT MATCHED THEN INSERT (FREQUENCY_CODE, FREQUENCY_DESCRIPTION) VALUES (src.FREQUENCY_CODE, src.FREQUENCY_DESCRIPTION);

-- Settings. Existing values are kept, except the version.
MERGE INTO <% database %>.OMD_METADATA.FRAMEWORK_METADATA AS tgt
USING (SELECT * FROM VALUES
    ('DIRECT_VERSION',                 '2.2.0',                      'SYSTEM_METADATA', 'The version of the DIRECT Framework this repository was deployed from.', 'Y'),
    ('DIRECT_EDITION',                 'Snowflake',                  'SYSTEM_METADATA', 'The edition of the DIRECT Framework this repository was deployed from.', 'Y'),
    ('LOG_TO_EVENT_LOG',               'Y',                          'SETTINGS', 'Write informational messages of the procedures to the event log (Y) or only errors (N).', 'Y'),
    ('THROW_ON_FAILURE',               'Y',                          'SETTINGS', 'Raise an error at the end of a top-level RUN_BATCH, or of a stand-alone RUN_MODULE, when a Module failed (Y), so that a Task run or a script stops, or return the result quietly (N). The bookkeeping is complete in both cases.', 'Y'),
    ('FAIL_BATCH_ON_MODULE_FAILURE',   'Y',                          'SETTINGS', 'Fail the Batch Instance when one of its Module Instances failed.', 'Y'),
    ('STOP_BATCH_ON_MODULE_FAILURE',   'Y',                          'SETTINGS', 'Stop running the remaining Modules and child Batches of a Batch after a Module failed (Y), or run them anyway (N).', 'Y'),
    ('AUTO_REGISTER_BATCHES',          'Y',                          'SETTINGS', 'Register a Batch that is run but not registered.', 'Y'),
    ('AUTO_REGISTER_MODULES',          'Y',                          'SETTINGS', 'Register a Module that is run but not registered.', 'Y'),
    ('AUTO_REGISTER_RELATIONSHIPS',    'Y',                          'SETTINGS', 'Register a Batch/Module or Batch/parent Batch relationship that is used but not registered.', 'Y'),
    ('MODULE_INSTANCE_ID_COLUMN_NAME', 'MODULE_INSTANCE_ID',         'SETTINGS', 'The column in the target data objects that holds the Module Instance Id of the run that inserted the row. The rollback deletes by this column.', 'Y'),
    ('DEFAULT_START_VALUE',            '1900-01-01 00:00:00.0000000', 'SETTINGS', 'The load window start value for a Module that has no load window recorded yet.', 'Y'),
    ('LOAD_WINDOW_ATTRIBUTE_NAME',     '',                           'SETTINGS', 'The attribute whose maximum value in the source data object ends the load window of a Module. Empty: the load window ends at the start of the Module Instance.', 'Y'),
    ('TIMESTAMP_FORMAT',               'YYYY-MM-DD HH24:MI:SS.FF7',  'SETTINGS', 'The format of timestamps in load window values and messages.', 'Y'),
    ('QUEUE_WAREHOUSE_SIZE',           'XSMALL',                     'SETTINGS', 'The initial warehouse size of the serverless Task that START_QUEUE creates.', 'Y')
  AS src (CODE, VALUE, "GROUP", DESCRIPTION, ACTIVE_INDICATOR)) AS src
ON tgt.CODE = src.CODE
WHEN MATCHED AND src.CODE IN ('DIRECT_VERSION', 'DIRECT_EDITION') THEN UPDATE SET VALUE = src.VALUE, DESCRIPTION = src.DESCRIPTION
WHEN NOT MATCHED THEN INSERT (CODE, VALUE, "GROUP", DESCRIPTION, ACTIVE_INDICATOR) VALUES (src.CODE, src.VALUE, src."GROUP", src.DESCRIPTION, src.ACTIVE_INDICATOR);

-- Placeholder rows for runs that are not connected to a Batch or Module.
MERGE INTO <% database %>.OMD.BATCH AS tgt
USING (SELECT 0 AS BATCH_ID, 'Default Batch' AS BATCH_CODE, 'Maintenance' AS BATCH_TYPE, 'On-demand' AS FREQUENCY_CODE, 'Y' AS ACTIVE_INDICATOR, 'Placeholder value for disconnected Batch runs' AS BATCH_DESCRIPTION) AS src
ON tgt.BATCH_ID = src.BATCH_ID
WHEN NOT MATCHED THEN INSERT (BATCH_ID, BATCH_CODE, BATCH_TYPE, FREQUENCY_CODE, ACTIVE_INDICATOR, BATCH_DESCRIPTION)
  VALUES (src.BATCH_ID, src.BATCH_CODE, src.BATCH_TYPE, src.FREQUENCY_CODE, src.ACTIVE_INDICATOR, src.BATCH_DESCRIPTION);

MERGE INTO <% database %>.OMD.BATCH_INSTANCE AS tgt
USING (SELECT 0 AS BATCH_INSTANCE_ID) AS src
ON tgt.BATCH_INSTANCE_ID = src.BATCH_INSTANCE_ID
WHEN NOT MATCHED THEN INSERT (BATCH_INSTANCE_ID, BATCH_ID, PARENT_BATCH_INSTANCE_ID, START_TIMESTAMP, END_TIMESTAMP, INTERNAL_PROCESSING_CODE, NEXT_RUN_STATUS_CODE, EXECUTION_STATUS_CODE, EXECUTION_CONTEXT)
  VALUES (0, 0, 0, '0001-01-01'::TIMESTAMP_NTZ, '9999-12-31'::TIMESTAMP_NTZ, 'Proceed', 'Proceed', 'Succeeded', '');

MERGE INTO <% database %>.OMD.MODULE AS tgt
USING (SELECT 0 AS MODULE_ID) AS src
ON tgt.MODULE_ID = src.MODULE_ID
WHEN NOT MATCHED THEN INSERT (MODULE_ID, MODULE_CODE, MODULE_TYPE, DATA_OBJECT_SOURCE, DATA_OBJECT_TARGET, AREA_CODE, FREQUENCY_CODE, ACTIVE_INDICATOR, MODULE_DESCRIPTION, EXECUTABLE)
  VALUES (0, 'Default Module', 'DataLogistics', 'N/A', 'N/A', 'MAINT', 'On-demand', 'Y', 'Placeholder value for disconnected Module runs', 'SELECT NULL');

MERGE INTO <% database %>.OMD.MODULE_INSTANCE_EXECUTED_CODE AS tgt
USING (SELECT REPEAT('0', 128) AS CHECKSUM) AS src
ON tgt.CHECKSUM = src.CHECKSUM
WHEN NOT MATCHED THEN INSERT (CHECKSUM, EXECUTED_CODE) VALUES (src.CHECKSUM, '');

MERGE INTO <% database %>.OMD.MODULE_INSTANCE AS tgt
USING (SELECT 0 AS MODULE_INSTANCE_ID) AS src
ON tgt.MODULE_INSTANCE_ID = src.MODULE_INSTANCE_ID
WHEN NOT MATCHED THEN INSERT (MODULE_INSTANCE_ID, MODULE_ID, BATCH_INSTANCE_ID, START_TIMESTAMP, END_TIMESTAMP, INTERNAL_PROCESSING_CODE, NEXT_RUN_STATUS_CODE, EXECUTION_STATUS_CODE, EXECUTION_CONTEXT, ROWS_INPUT, ROWS_INSERTED, ROWS_UPDATED, ROWS_DELETED, ROWS_DISCARDED, ROWS_REJECTED, EXECUTED_CODE_CHECKSUM)
  VALUES (0, 0, 0, '0001-01-01'::TIMESTAMP_NTZ, '9999-12-31'::TIMESTAMP_NTZ, 'Proceed', 'Proceed', 'Succeeded', 'N/A', 0, 0, 0, 0, 0, 0, REPEAT('0', 128));
