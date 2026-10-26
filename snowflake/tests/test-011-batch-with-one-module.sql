/*
 * DIRECT Framework - Snowflake edition
 * Regression test 011: Batch with one Module
 *
 * A Batch with one registered Module runs: the Batch Instance succeeds, the Module
 * Instance is bound to it and reports its rows, and the reporting views show both.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-011-batch-with-one-module';
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
    CALL <% database %>.OMD.REGISTER_BATCH('test-011-b', 'Batch', 'On-demand', 'Test 011') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-011-m', 'SELECT 5') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-011-m', 'test-011-b') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE LIKE '%was added to Batch%'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'ADD_MODULE_TO_BATCH message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.RUN_BATCH('test-011-b', 0, 'test-011') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'MODULES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'MODULES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch result status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_INTERNAL = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch result internal processing status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_INTERNAL), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Modules run: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Modules failed: expected 0, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;

    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Instance execution status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Instance next run status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Instance internal processing code: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-011-m' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_ID IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'no Module Instance bound to the Batch Instance' || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(ROWS_INSERTED) INTO :V_TEXT, :V_NUMBER FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance execution status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 5), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance rows inserted: expected 5, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_REPORTING.VW_EXECUTION_LOG_BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID AND BATCH_CODE = 'test-011-b';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'batch instance view: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_REPORTING.VW_EXECUTION_LOG_MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID AND BATCH_CODE = 'test-011-b';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'module instance view shows the Batch: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_PROCESSING.VW_BATCH_MODULE WHERE BATCH_CODE = 'test-011-b' AND MODULE_CODE = 'test-011-m' AND SEQUENCE = 1;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'batch module view: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
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
