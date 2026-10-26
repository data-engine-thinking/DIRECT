/*
 * DIRECT Framework - Snowflake edition
 * Regression test 022: abort of a concurrent instance
 *
 * While an instance of a Module or a Batch is still Executing, a new run of the same
 * Module or Batch is aborted (and logged). Once the first instance is closed, the next run
 * proceeds.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-022-concurrency-abort';
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
    CALL <% database %>.OMD.REGISTER_MODULE('test-022-m', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.CREATE_MODULE_INSTANCE('test-022-m', 0, 'test-022 open') INTO :V_ID;
    CALL <% database %>.OMD.RUN_MODULE('test-022-m', 0, 'test-022 concurrent') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_ID_2 := V_ID;
    IF (NOT COALESCE((V_STATUS = 'Aborted'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'concurrent Module run status: expected Aborted, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_INTERNAL = 'Abort'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'concurrent Module run internal processing status: expected Abort, got ' || COALESCE(TO_VARCHAR(V_INTERNAL), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE MODULE_INSTANCE_ID = :V_ID_2 AND EVENT_DETAIL LIKE 'Another instance of Module%is still executing%';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'event log explains the Module abort: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT MIN(mi.MODULE_INSTANCE_ID) INTO :V_ID FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID WHERE m.MODULE_CODE = 'test-022-m';
    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:V_ID, 'Success') INTO :V_MESSAGE;
    CALL <% database %>.OMD.RUN_MODULE('test-022-m', 0, 'test-022 after close') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module run after the first instance closed: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.REGISTER_BATCH('test-022-b') INTO :V_NUMBER;
    CALL <% database %>.OMD.CREATE_BATCH_INSTANCE('test-022-b', 0, 'test-022 open') INTO :V_BATCH_INSTANCE_ID;
    CALL <% database %>.OMD.RUN_BATCH('test-022-b', 0, 'test-022 concurrent') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID_2 := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Aborted'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'concurrent Batch run status: expected Aborted, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_INTERNAL = 'Abort'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'concurrent Batch run internal processing status: expected Abort, got ' || COALESCE(TO_VARCHAR(V_INTERNAL), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2 AND EVENT_DETAIL LIKE 'Another instance of Batch%is still executing%';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'event log explains the Batch abort: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:V_BATCH_INSTANCE_ID, 'Success') INTO :V_MESSAGE;
    CALL <% database %>.OMD.RUN_BATCH('test-022-b', 0, 'test-022 after close') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch run after the first instance closed: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_REPORTING.VW_EXCEPTIONS_LONG_RUNNING_PROCESSES WHERE CODE IN ('test-022-m', 'test-022-b');
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'nothing left executing: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
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
