/*
 * DIRECT Framework - Snowflake edition
 * Regression test 020: UPDATE_MODULE_INSTANCE events
 *
 * Success stores the row counts and closes the instance; Proceed afterwards keeps the
 * counts and the end timestamp; Failure sets Failed with next run status Rollback; an
 * unknown event is reported.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-020-update-module-instance';
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
    CALL <% database %>.OMD.REGISTER_MODULE('test-020-m', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.CREATE_MODULE_INSTANCE('test-020-m', 0, 'test-020') INTO :V_ID;
    IF (NOT COALESCE((V_ID IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'no Module Instance created' || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE), COUNT(END_TIMESTAMP) INTO :V_TEXT, :V_TEXT_2, :V_COUNT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
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

    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_ID, 'Success', 25, 10, 5, 2, 0, 0) INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'Module Instance ' || TO_VARCHAR(V_ID) || ' received event ''Success''.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Success message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(ROWS_INPUT) || ',' || MAX(ROWS_INSERTED) || ',' || MAX(ROWS_UPDATED) || ',' || MAX(ROWS_DELETED), COUNT(END_TIMESTAMP)
    INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3, :V_COUNT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Success: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'next run status after Success: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = '25,10,5,2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row counts after Success: expected 25,10,5,2, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'end timestamp set after Success: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_ID, 'Proceed') INTO :V_MESSAGE;
    SELECT MAX(INTERNAL_PROCESSING_CODE), MAX(ROWS_INPUT) || ',' || MAX(ROWS_INSERTED) || ',' || MAX(ROWS_UPDATED) || ',' || MAX(ROWS_DELETED), COUNT(END_TIMESTAMP)
    INTO :V_TEXT, :V_TEXT_3, :V_COUNT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'internal processing code after Proceed: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = '25,10,5,2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row counts kept after Proceed: expected 25,10,5,2, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'end timestamp kept after Proceed: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.CREATE_MODULE_INSTANCE('test-020-m', 0, 'test-020') INTO :V_ID_2;
    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_ID_2, 'Failure') INTO :V_MESSAGE;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'execution status after Failure: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Rollback'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'next run status after Failure: expected Rollback, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_ID_2, 'Whatever') INTO :V_MESSAGE;
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
