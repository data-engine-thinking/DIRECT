/*
 * DIRECT Framework - Snowflake edition
 * Regression test 007: rollback of a failed stand-alone Module
 *
 * A Module loads a row into OMD_TEST.TARGET and then fails. The next run of the Module
 * rolls that row back (DELETE by MODULE_INSTANCE_ID) before it loads its own row, and the
 * event log records the rollback.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-007-rollback-after-failure';
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
    CALL <% database %>.OMD.SET_SETTING('THROW_ON_FAILURE', 'N');
    CALL <% database %>.OMD.REGISTER_MODULE('test-007-m', 'CALL <% database %>.OMD_TEST.INSERT_THEN_FAIL(:ModuleInstanceId)', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;

    CALL <% database %>.OMD.RUN_MODULE('test-007-m', 0, 'test-007 run 1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'first run status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the failed run is in the target: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.REGISTER_MODULE('test-007-m', 'CALL <% database %>.OMD_TEST.INSERT_ROW(:ModuleInstanceId)', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;
    CALL <% database %>.OMD.RUN_MODULE('test-007-m', 0, 'test-007 run 2') INTO :V_RESULT_2;
    V_STATUS := GET(V_RESULT_2, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_ID_2 := GET(V_RESULT_2, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second run status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the failed run rolled back: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the second run loaded: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'failed instance keeps its execution status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'failed instance next run status settled: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second instance execution status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second instance internal processing code: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE MODULE_INSTANCE_ID = :V_ID_2 AND EVENT_DETAIL LIKE 'Rollback of Module Instance(s) ' || TO_VARCHAR(:V_ID) || ':%';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'event log records the rollback: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    -- Restore the settings the test relies on.
    CALL <% database %>.OMD.SET_SETTING('THROW_ON_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('FAIL_BATCH_ON_MODULE_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_MODULES', 'Y');
    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_RELATIONSHIPS', 'Y');
    CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', '');
    INSERT INTO <% database %>.OMD_TEST.TEST_RESULT (TEST_NAME, RESULT, OUTPUT)
    VALUES (:V_TEST, IFF(:V_SKIP, 'Skip', IFF(:V_ISSUES = 0, 'Pass', 'Fail')), LEFT(:V_OUTPUT, 4000));
    RETURN V_TEST || ': ' || IFF(V_SKIP, 'Skip', IFF(V_ISSUES = 0, 'Pass', 'Fail')) || IFF(V_OUTPUT = '', '', ' - ' || V_OUTPUT);
EXCEPTION
    WHEN OTHER THEN

    -- Restore the settings the test relies on.
    CALL <% database %>.OMD.SET_SETTING('THROW_ON_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('FAIL_BATCH_ON_MODULE_FAILURE', 'Y');
    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_MODULES', 'Y');
    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_RELATIONSHIPS', 'Y');
    CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', '');
        INSERT INTO <% database %>.OMD_TEST.TEST_RESULT (TEST_NAME, RESULT, OUTPUT)
        VALUES (:V_TEST, 'Fail', LEFT('Unexpected error: ' || SQLERRM || ' | ' || :V_OUTPUT, 4000));
        RETURN V_TEST || ': Fail - unexpected error: ' || SQLERRM;
END;
$$;
