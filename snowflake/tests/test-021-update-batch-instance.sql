/*
 * DIRECT Framework - Snowflake edition
 * Regression test 021: UPDATE_BATCH_INSTANCE events
 *
 * Success closes the Batch Instance; Proceed afterwards keeps the end timestamp; Failure
 * sets Failed with next run status Proceed; Abort and Cancel set their statuses; an
 * unknown event is reported.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-021-update-batch-instance';
    V_ISSUES NUMBER DEFAULT 0;
    V_OUTPUT VARCHAR DEFAULT '';
    V_SKIP BOOLEAN DEFAULT FALSE;
    V_RESULT OBJECT;
    V_RESULT_2 OBJECT;
    V_STATUS VARCHAR;
    V_INTERNAL VARCHAR;
    V_MESSAGE VARCHAR;
    V_ID NUMBER;
    V_ID_2 NUMBER;
    V_ID_3 NUMBER;
    V_ID_4 NUMBER;
    V_BATCH_INSTANCE_ID NUMBER;
    V_BATCH_INSTANCE_ID_2 NUMBER;
    V_COUNT NUMBER;
    V_COUNT_2 NUMBER;
    V_COUNT_3 NUMBER;
    V_NUMBER NUMBER;
    V_NUMBER_2 NUMBER;
    V_TEXT VARCHAR;
    V_TEXT_2 VARCHAR;
    V_TEXT_3 VARCHAR;
    V_TEXT_4 VARCHAR;
    V_RAISED BOOLEAN DEFAULT FALSE;
    V_ERROR VARCHAR;
    V_WAREHOUSE VARCHAR;
BEGIN
    CALL <% database %>.OMD.REGISTER_BATCH('test-021-b') INTO :V_NUMBER;
    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE('test-021-b', 0, 'test-021') INTO :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_BATCH_INSTANCE_ID IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'no Batch Instance created' || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE), COUNT(END_TIMESTAMP), MAX(EXECUTION_CONTEXT) INTO :V_TEXT, :V_TEXT_2, :V_COUNT, :V_TEXT_3 FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Executing'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'new instance execution status: expected Executing, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Abort'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'new instance internal processing code: expected Abort, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'new instance has no end timestamp: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'test-021'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution context: expected test-021, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Success') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'Batch Instance ' || TO_VARCHAR(V_BATCH_INSTANCE_ID) || ' received event ''Success''.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Success message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(END_TIMESTAMP) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3 FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Success: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'next run status after Success: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'end timestamp not set after Success' || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Proceed') INTO :V_MESSAGE;
    SELECT MAX(INTERNAL_PROCESSING_CODE), MAX(END_TIMESTAMP) INTO :V_TEXT, :V_TEXT_4 FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'internal processing code after Proceed: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_4 = V_TEXT_3), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'end timestamp changed by Proceed' || '; ';
    END IF;

    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE('test-021-b', 0, 'test-021') INTO :V_BATCH_INSTANCE_ID_2;
    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID_2, 'Failure') INTO :V_MESSAGE;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Failure: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'next run status after Failure: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE('test-021-b', 0, 'test-021') INTO :V_BATCH_INSTANCE_ID_2;
    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID_2, 'Abort') INTO :V_MESSAGE;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Aborted'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Abort: expected Aborted, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Abort'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'internal processing code after Abort: expected Abort, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE('test-021-b', 0, 'test-021') INTO :V_BATCH_INSTANCE_ID_2;
    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID_2, 'Cancel') INTO :V_MESSAGE;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Cancelled'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Cancel: expected Cancelled, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Cancel'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'internal processing code after Cancel: expected Cancel, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID_2, 'Whatever') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'Unknown event code ''Whatever''.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'unknown event message: expected Unknown event code ''Whatever''., got ' || COALESCE(TO_VARCHAR(V_MESSAGE), 'NULL') || '; ';
    END IF;

    INSERT INTO <% database %>.OMD_TEST.TEST_RESULT (TEST_NAME, RESULT, OUTPUT)
    VALUES (:V_TEST, IFF(:V_SKIP, 'Skip', IFF(:V_ISSUES = 0, 'Pass', 'Fail')), LEFT(:V_OUTPUT, 4000));
    RETURN V_TEST || ': ' || IFF(V_SKIP, 'Skip', IFF(V_ISSUES = 0, 'Pass', 'Fail')) || IFF(V_OUTPUT = '', '', ' - ' || V_OUTPUT);
EXCEPTION
    WHEN OTHER THEN

        INSERT INTO <% database %>.OMD_TEST.TEST_RESULT (TEST_NAME, RESULT, OUTPUT)
        VALUES (:V_TEST, 'Fail', LEFT('Unexpected error: ' || SQLERRM || ' | ' || :V_OUTPUT, 4000));
        RETURN V_TEST || ': Fail - unexpected error: ' || SQLERRM;
END;
$$;
