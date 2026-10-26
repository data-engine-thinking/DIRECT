/*
 * DIRECT Framework - Snowflake edition
 * Regression test 009: three failures in a row, then a recovery
 *
 * A Module fails three times in a row; every run first rolls back the row of the previous
 * failed run. After the executable is fixed, the fourth run rolls back the third run's row
 * and loads its own, so the target holds exactly one row.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-009-repeated-failures-then-recovery';
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
    CALL <% database %>.OMD.REGISTER_MODULE('test-009-m', 'CALL <% database %>.OMD_TEST.INSERT_THEN_FAIL(:ModuleInstanceId)', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;

    CALL <% database %>.OMD.RUN_MODULE('test-009-m', 0, 'test-009 run 1') INTO :V_RESULT;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    CALL <% database %>.OMD.RUN_MODULE('test-009-m', 0, 'test-009 run 2') INTO :V_RESULT;
    V_ID_2 := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT_2 := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    CALL <% database %>.OMD.RUN_MODULE('test-009-m', 0, 'test-009 run 3') INTO :V_RESULT;
    V_ID_3 := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT_3 := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 3 status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID IN (:V_ID, :V_ID_2);
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'rows of runs 1 and 2 rolled back: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_3;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of run 3 still there: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.REGISTER_MODULE('test-009-m', 'CALL <% database %>.OMD_TEST.INSERT_ROW(:ModuleInstanceId)', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;
    CALL <% database %>.OMD.RUN_MODULE('test-009-m', 0, 'test-009 run 4') INTO :V_RESULT;
    V_ID_4 := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT_4 := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    IF (NOT COALESCE((V_TEXT_4 = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 4 status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT_4), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID IN (:V_ID, :V_ID_2, :V_ID_3, :V_ID_4);
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'exactly one row for the Module: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_4;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'the remaining row belongs to run 4: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID IN (:V_ID, :V_ID_2, :V_ID_3) AND EXECUTION_STATUS_CODE = 'Failed' AND NEXT_RUN_STATUS_CODE = 'Proceed';
    IF (NOT COALESCE((V_COUNT = 3), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'failed instances keep Failed and are settled: expected 3, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE MODULE_INSTANCE_ID IN (:V_ID_2, :V_ID_3, :V_ID_4) AND EVENT_DETAIL LIKE 'Rollback of Module Instance(s)%';
    IF (NOT COALESCE((V_COUNT = 3), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'three rollback events: expected 3, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
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
