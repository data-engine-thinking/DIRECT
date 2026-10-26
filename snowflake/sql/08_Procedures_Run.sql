/*
 * DIRECT Framework - Snowflake edition
 * 08 Run procedures
 *
 * RUN_MODULE runs one Module: it creates and evaluates the Module Instance,
 * determines the load window, runs the executable and records the outcome.
 * RUN_BATCH runs a Batch: its Modules in sequence, then its child Batches in
 * sequence, and closes the Batch Instance.
 *
 * The executable contract. The EXECUTABLE of a Module is a SQL statement that
 * runs in the repository database through EXECUTE IMMEDIATE. Before it runs,
 * these tokens are replaced by values:
 *
 *   :ModuleInstanceId     the Module Instance Id of this run, as a number
 *   :StartValue           the end value of the previous load window, as a quoted string
 *   :EndValue             the end value of this load window, as a quoted string
 *   :ConsistencyDateTime  NULL (consistency timestamps are not part of this edition)
 *
 * For example: CALL MY_DB.DV.SP_SAT_CUSTOMER(:ModuleInstanceId, :EndValue)
 *
 * When the executable returns a single value (a procedure that returns a row
 * count, or an INSERT), that value is recorded as the number of rows inserted.
 */

CREATE OR REPLACE PROCEDURE <% database %>.OMD.RUN_MODULE
(
    P_MODULE_CODE        VARCHAR,
    P_BATCH_INSTANCE_ID  NUMBER DEFAULT 0,
    P_EXECUTION_CONTEXT  VARCHAR DEFAULT '',
    P_QUERY              VARCHAR DEFAULT NULL,
    P_END_VALUE          VARCHAR DEFAULT NULL
)
RETURNS OBJECT
LANGUAGE SQL
COMMENT = 'Runs a Module: creates and evaluates the Module Instance, runs the executable (or the given query) with the load window, and records the outcome. P_END_VALUE overrides the end of the load window. Returns an object with MODULE_INSTANCE_ID, INTERNAL_PROCESSING_STATUS_CODE, EXECUTION_STATUS_CODE, START_VALUE, END_VALUE, ROWS_INSERTED and EVENT_DETAIL. Raises an error after the bookkeeping when the Module failed, it runs stand-alone (no Batch Instance) and the setting THROW_ON_FAILURE is Y; inside a Batch the failure is returned to RUN_BATCH.'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_MODULE_INSTANCE_ID NUMBER;
    V_MODULE_ID NUMBER;
    V_STATUS VARCHAR;
    V_EXECUTABLE VARCHAR;
    V_DATA_OBJECT_SOURCE VARCHAR;
    V_START_VALUE VARCHAR;
    V_END_VALUE VARCHAR;
    V_LOAD_WINDOW_ATTRIBUTE VARCHAR;
    V_FORMAT VARCHAR;
    V_STATEMENT VARCHAR;
    V_RESULT RESULTSET;
    V_FIRST_VALUE VARCHAR;
    V_ROWS NUMBER DEFAULT 0;
    V_MESSAGE VARCHAR;
    V_RETURN_CODE VARCHAR;
    MODULE_FAILED EXCEPTION (-20002, 'The Module failed. The event log holds the error.');
BEGIN
    CALL <% database %>.OMD.CREATE_MODULE_INSTANCE(:P_MODULE_CODE, :P_BATCH_INSTANCE_ID, :P_EXECUTION_CONTEXT, :P_QUERY) INTO :V_MODULE_INSTANCE_ID;

    IF (V_MODULE_INSTANCE_ID IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('MODULE_CODE', P_MODULE_CODE, 'MODULE_INSTANCE_ID', NULL, 'INTERNAL_PROCESSING_STATUS_CODE', 'Abort', 'EXECUTION_STATUS_CODE', 'Aborted',
            'EVENT_DETAIL', 'The Module Instance could not be created; see the event log.');
    END IF;

    CALL <% database %>.OMD.MODULE_EVALUATION(:V_MODULE_INSTANCE_ID) INTO :V_STATUS;

    IF (V_STATUS <> 'Proceed') THEN
        RETURN OBJECT_CONSTRUCT('MODULE_CODE', P_MODULE_CODE, 'MODULE_INSTANCE_ID', V_MODULE_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', V_STATUS,
            'EXECUTION_STATUS_CODE', IFF(V_STATUS = 'Cancel', 'Cancelled', 'Aborted'), 'ROWS_INSERTED', 0);
    END IF;

    -- The executable and the source data object of the Module.
    V_MODULE_ID := <% database %>.OMD.GET_MODULE_ID_BY_MODULE_INSTANCE_ID(V_MODULE_INSTANCE_ID);
    SELECT MAX(EXECUTABLE), MAX(DATA_OBJECT_SOURCE) INTO :V_EXECUTABLE, :V_DATA_OBJECT_SOURCE FROM <% database %>.OMD.MODULE WHERE MODULE_ID = :V_MODULE_ID;
    IF (P_QUERY IS NOT NULL) THEN
        V_EXECUTABLE := P_QUERY;
    END IF;

    -- The load window: from the end of the previous window to now, or to the maximum of the load window attribute in the source.
    V_FORMAT := COALESCE(<% database %>.OMD_METADATA.GET_SETTING('TIMESTAMP_FORMAT'), 'YYYY-MM-DD HH24:MI:SS.FF7');
    V_START_VALUE := COALESCE(<% database %>.OMD.GET_MODULE_LOAD_WINDOW_VALUE(V_MODULE_ID, 2), <% database %>.OMD_METADATA.GET_SETTING('DEFAULT_START_VALUE'), '1900-01-01 00:00:00.0000000');
    V_END_VALUE := P_END_VALUE;

    IF (V_END_VALUE IS NULL) THEN
        V_LOAD_WINDOW_ATTRIBUTE := NULLIF(TRIM(COALESCE(<% database %>.OMD_METADATA.GET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME'), '')), '');
        IF (V_LOAD_WINDOW_ATTRIBUTE IS NOT NULL AND V_DATA_OBJECT_SOURCE IS NOT NULL AND V_DATA_OBJECT_SOURCE <> 'N/A') THEN
            BEGIN
                V_STATEMENT := 'SELECT TO_VARCHAR(MAX(' || V_LOAD_WINDOW_ATTRIBUTE || '), ''' || V_FORMAT || ''') FROM ' || V_DATA_OBJECT_SOURCE;
                V_RESULT := (EXECUTE IMMEDIATE :V_STATEMENT);
                LET V_WINDOW_CURSOR CURSOR FOR V_RESULT;
                OPEN V_WINDOW_CURSOR;
                FETCH V_WINDOW_CURSOR INTO V_END_VALUE;
                CLOSE V_WINDOW_CURSOR;
            EXCEPTION
                WHEN OTHER THEN
                    V_END_VALUE := NULL;
            END;
        END IF;
        IF (V_END_VALUE IS NULL) THEN
            V_END_VALUE := TO_VARCHAR(SYSDATE(), V_FORMAT);
        END IF;
    END IF;

    -- Run the executable with the tokens replaced.
    V_STATEMENT := COALESCE(V_EXECUTABLE, 'SELECT NULL');
    V_STATEMENT := REPLACE(V_STATEMENT, ':ModuleInstanceId', TO_VARCHAR(V_MODULE_INSTANCE_ID));
    V_STATEMENT := REPLACE(V_STATEMENT, ':StartValue', '''' || REPLACE(V_START_VALUE, '''', '''''') || '''');
    V_STATEMENT := REPLACE(V_STATEMENT, ':EndValue', '''' || REPLACE(V_END_VALUE, '''', '''''') || '''');
    V_STATEMENT := REPLACE(V_STATEMENT, ':ConsistencyDateTime', 'NULL');

    BEGIN
        V_RESULT := (EXECUTE IMMEDIATE :V_STATEMENT);
        LET V_CURSOR CURSOR FOR V_RESULT;
        OPEN V_CURSOR;
        FETCH V_CURSOR INTO V_FIRST_VALUE;
        CLOSE V_CURSOR;
        V_ROWS := COALESCE(TRY_TO_NUMBER(V_FIRST_VALUE), 0);
    EXCEPTION
        WHEN OTHER THEN
            V_MESSAGE := LEFT('Error running Module ''' || P_MODULE_CODE || ''' (Module Instance ' || TO_VARCHAR(V_MODULE_INSTANCE_ID) || '): ' || SQLERRM || ' Statement: ' || V_STATEMENT, 4000);
            V_RETURN_CODE := TO_VARCHAR(SQLCODE);
            CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, :V_MODULE_INSTANCE_ID, :P_BATCH_INSTANCE_ID, 2, :V_RETURN_CODE);
            CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_MODULE_INSTANCE_ID, 'Failure');
            IF (COALESCE(P_BATCH_INSTANCE_ID, 0) = 0 AND <% database %>.OMD_METADATA.GET_SETTING_FLAG('THROW_ON_FAILURE') = 'Y') THEN
                RAISE MODULE_FAILED;
            END IF;
            RETURN OBJECT_CONSTRUCT('MODULE_CODE', P_MODULE_CODE, 'MODULE_INSTANCE_ID', V_MODULE_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', 'Proceed', 'EXECUTION_STATUS_CODE', 'Failed',
                'START_VALUE', V_START_VALUE, 'END_VALUE', V_END_VALUE, 'ROWS_INSERTED', 0, 'EVENT_DETAIL', V_MESSAGE);
    END;

    CALL <% database %>.OMD.SET_SOURCE_CONTROL_VALUES(:V_MODULE_INSTANCE_ID, :V_START_VALUE, :V_END_VALUE);
    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_MODULE_INSTANCE_ID, 'Success', 0, :V_ROWS);

    RETURN OBJECT_CONSTRUCT('MODULE_CODE', P_MODULE_CODE, 'MODULE_INSTANCE_ID', V_MODULE_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', 'Proceed', 'EXECUTION_STATUS_CODE', 'Succeeded',
        'START_VALUE', V_START_VALUE, 'END_VALUE', V_END_VALUE, 'ROWS_INSERTED', V_ROWS);
EXCEPTION
    WHEN MODULE_FAILED THEN
        RAISE;
    WHEN OTHER THEN
        V_MESSAGE := LEFT('Error in RUN_MODULE for Module ''' || COALESCE(P_MODULE_CODE, '') || ''': ' || SQLERRM, 4000);
        V_RETURN_CODE := TO_VARCHAR(SQLCODE);
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, COALESCE(:V_MODULE_INSTANCE_ID, 0), :P_BATCH_INSTANCE_ID, 1, :V_RETURN_CODE);
        IF (V_MODULE_INSTANCE_ID IS NOT NULL) THEN
            CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_MODULE_INSTANCE_ID, 'Failure');
        END IF;
        IF (COALESCE(P_BATCH_INSTANCE_ID, 0) = 0 AND <% database %>.OMD_METADATA.GET_SETTING_FLAG('THROW_ON_FAILURE') = 'Y') THEN
            RAISE MODULE_FAILED;
        END IF;
        RETURN OBJECT_CONSTRUCT('MODULE_CODE', P_MODULE_CODE, 'MODULE_INSTANCE_ID', V_MODULE_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', 'Proceed', 'EXECUTION_STATUS_CODE', 'Failed',
            'ROWS_INSERTED', 0, 'EVENT_DETAIL', V_MESSAGE);
END;
$$;

CREATE OR REPLACE PROCEDURE <% database %>.OMD.RUN_BATCH
(
    P_BATCH_CODE                VARCHAR,
    P_PARENT_BATCH_INSTANCE_ID  NUMBER DEFAULT 0,
    P_EXECUTION_CONTEXT         VARCHAR DEFAULT '',
    P_END_VALUE                 VARCHAR DEFAULT NULL
)
RETURNS OBJECT
LANGUAGE SQL
COMMENT = 'Runs a Batch: creates and evaluates the Batch Instance, runs the active Modules of the Batch in sequence and then the active child Batches in sequence, and closes the Batch Instance. P_END_VALUE is passed to every Module as the end of its load window. Returns an object with BATCH_INSTANCE_ID, INTERNAL_PROCESSING_STATUS_CODE, EXECUTION_STATUS_CODE, MODULES, MODULES_FAILED, CHILD_BATCHES and CHILD_BATCHES_FAILED. Raises an error at the end when a Module failed and the setting THROW_ON_FAILURE is Y (top-level Batch only).'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_BATCH_INSTANCE_ID NUMBER;
    V_BATCH_ID NUMBER;
    V_STATUS VARCHAR;
    V_MODULE_RESULT OBJECT;
    V_BATCH_RESULT OBJECT;
    V_MODULES NUMBER DEFAULT 0;
    V_MODULES_FAILED NUMBER DEFAULT 0;
    V_CHILD_BATCHES NUMBER DEFAULT 0;
    V_CHILD_BATCHES_FAILED NUMBER DEFAULT 0;
    V_STOP VARCHAR DEFAULT 'N';
    V_STOP_ON_FAILURE VARCHAR;
    V_EXECUTION_STATUS_CODE VARCHAR;
    V_MODULE_LIST RESULTSET;
    V_CHILD_LIST RESULTSET;
    V_MODULE_CODE VARCHAR;
    V_CHILD_BATCH_CODE VARCHAR;
    V_MESSAGE VARCHAR;
    V_RETURN_CODE VARCHAR;
    BATCH_FAILED EXCEPTION (-20001, 'The Batch ended with failures.');
BEGIN
    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE(:P_BATCH_CODE, :P_PARENT_BATCH_INSTANCE_ID, :P_EXECUTION_CONTEXT) INTO :V_BATCH_INSTANCE_ID;

    IF (V_BATCH_INSTANCE_ID IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('BATCH_CODE', P_BATCH_CODE, 'BATCH_INSTANCE_ID', NULL, 'INTERNAL_PROCESSING_STATUS_CODE', 'Abort', 'EXECUTION_STATUS_CODE', 'Aborted',
            'EVENT_DETAIL', 'The Batch Instance could not be created; see the event log.');
    END IF;

    CALL <% database %>.OMD.BATCH_EVALUATION(:V_BATCH_INSTANCE_ID) INTO :V_STATUS;

    IF (V_STATUS <> 'Proceed') THEN
        RETURN OBJECT_CONSTRUCT('BATCH_CODE', P_BATCH_CODE, 'BATCH_INSTANCE_ID', V_BATCH_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', V_STATUS,
            'EXECUTION_STATUS_CODE', IFF(V_STATUS = 'Cancel', 'Cancelled', 'Aborted'), 'MODULES', 0, 'MODULES_FAILED', 0, 'CHILD_BATCHES', 0, 'CHILD_BATCHES_FAILED', 0);
    END IF;

    V_BATCH_ID := <% database %>.OMD.GET_BATCH_ID_BY_BATCH_INSTANCE_ID(V_BATCH_INSTANCE_ID);
    V_STOP_ON_FAILURE := <% database %>.OMD_METADATA.GET_SETTING_FLAG('STOP_BATCH_ON_MODULE_FAILURE');

    -- The Modules of the Batch, in sequence.
    V_MODULE_LIST := (
        SELECT m.MODULE_CODE
        FROM <% database %>.OMD.BATCH_MODULE bm
        JOIN <% database %>.OMD.MODULE m ON bm.MODULE_ID = m.MODULE_ID
        WHERE bm.BATCH_ID = :V_BATCH_ID AND bm.ACTIVE_INDICATOR = 'Y'
        ORDER BY bm.SEQUENCE, m.MODULE_CODE
    );

    LET V_MODULE_CURSOR CURSOR FOR V_MODULE_LIST;
    FOR V_MODULE IN V_MODULE_CURSOR DO
        IF (V_STOP = 'Y') THEN
            BREAK;
        END IF;
        V_MODULES := V_MODULES + 1;
        V_MODULE_CODE := V_MODULE.MODULE_CODE;
        CALL <% database %>.OMD.RUN_MODULE(:V_MODULE_CODE, :V_BATCH_INSTANCE_ID, :P_EXECUTION_CONTEXT, NULL, :P_END_VALUE) INTO :V_MODULE_RESULT;
        IF (GET(V_MODULE_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR = 'Failed') THEN
            V_MODULES_FAILED := V_MODULES_FAILED + 1;
            IF (V_STOP_ON_FAILURE = 'Y') THEN
                V_STOP := 'Y';
            END IF;
        END IF;
    END FOR;

    -- The child Batches, in sequence, with this Batch Instance as parent.
    IF (V_STOP = 'N') THEN
        V_CHILD_LIST := (
            SELECT b.BATCH_CODE
            FROM <% database %>.OMD.BATCH_HIERARCHY bh
            JOIN <% database %>.OMD.BATCH b ON bh.BATCH_ID = b.BATCH_ID
            WHERE bh.PARENT_BATCH_ID = :V_BATCH_ID AND bh.ACTIVE_INDICATOR = 'Y'
            ORDER BY bh.SEQUENCE, b.BATCH_CODE
        );

        LET V_CHILD_CURSOR CURSOR FOR V_CHILD_LIST;
        FOR V_CHILD IN V_CHILD_CURSOR DO
            IF (V_STOP = 'Y') THEN
                BREAK;
            END IF;
            V_CHILD_BATCHES := V_CHILD_BATCHES + 1;
            V_CHILD_BATCH_CODE := V_CHILD.BATCH_CODE;
            CALL <% database %>.OMD.RUN_BATCH(:V_CHILD_BATCH_CODE, :V_BATCH_INSTANCE_ID, :P_EXECUTION_CONTEXT, :P_END_VALUE) INTO :V_BATCH_RESULT;
            IF (GET(V_BATCH_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR = 'Failed') THEN
                V_CHILD_BATCHES_FAILED := V_CHILD_BATCHES_FAILED + 1;
                IF (V_STOP_ON_FAILURE = 'Y') THEN
                    V_STOP := 'Y';
                END IF;
            END IF;
        END FOR;
    END IF;

    -- Close the Batch Instance.
    IF ((V_MODULES_FAILED > 0 OR V_CHILD_BATCHES_FAILED > 0) AND <% database %>.OMD_METADATA.GET_SETTING_FLAG('FAIL_BATCH_ON_MODULE_FAILURE') = 'Y') THEN
        V_EXECUTION_STATUS_CODE := 'Failed';
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Failure');
    ELSE
        V_EXECUTION_STATUS_CODE := 'Succeeded';
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Success');
    END IF;

    IF (V_EXECUTION_STATUS_CODE = 'Failed' AND COALESCE(P_PARENT_BATCH_INSTANCE_ID, 0) = 0 AND <% database %>.OMD_METADATA.GET_SETTING_FLAG('THROW_ON_FAILURE') = 'Y') THEN
        RAISE BATCH_FAILED;
    END IF;

    RETURN OBJECT_CONSTRUCT('BATCH_CODE', P_BATCH_CODE, 'BATCH_INSTANCE_ID', V_BATCH_INSTANCE_ID, 'INTERNAL_PROCESSING_STATUS_CODE', 'Proceed', 'EXECUTION_STATUS_CODE', V_EXECUTION_STATUS_CODE,
        'MODULES', V_MODULES, 'MODULES_FAILED', V_MODULES_FAILED, 'CHILD_BATCHES', V_CHILD_BATCHES, 'CHILD_BATCHES_FAILED', V_CHILD_BATCHES_FAILED);
EXCEPTION
    WHEN BATCH_FAILED THEN
        RAISE;
    WHEN OTHER THEN
        V_MESSAGE := LEFT('Error in RUN_BATCH for Batch ''' || COALESCE(P_BATCH_CODE, '') || ''': ' || SQLERRM, 4000);
        V_RETURN_CODE := TO_VARCHAR(SQLCODE);
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, 0, COALESCE(:V_BATCH_INSTANCE_ID, 0), 1, :V_RETURN_CODE);
        IF (V_BATCH_INSTANCE_ID IS NOT NULL) THEN
            CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Failure');
        END IF;
        RAISE;
END;
$$;
