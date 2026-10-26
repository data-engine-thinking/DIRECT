/*
 * DIRECT Framework - Snowflake edition
 * Regression test 013: partial rollback of a failed Batch
 *
 * A Batch with two Modules fails on the second. On the rerun the Batch evaluation skips
 * the Module that succeeded (Cancelled) and the failed Module is rolled back and run
 * again; the target holds the first Module's row from run 1 and the second Module's row
 * from run 2 only.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-013-partial-rollback';
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
    CALL <% database %>.OMD.REGISTER_BATCH('test-013-b') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-013-m1', 'CALL <% database %>.OMD_TEST.INSERT_ROW(:ModuleInstanceId, ''m1'')', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-013-m2', 'CALL <% database %>.OMD_TEST.INSERT_THEN_FAIL(:ModuleInstanceId)', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-013-m1', 'test-013-b', 1) INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-013-m2', 'test-013-b', 2) INTO :V_MESSAGE;

    CALL <% database %>.OMD.RUN_BATCH('test-013-b', 0, 'test-013 run 1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 Batch status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-013-m1' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_2
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-013-m2' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID IN (:V_ID, :V_ID_2);
    IF (NOT COALESCE((V_COUNT = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 left two rows: expected 2, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.REGISTER_MODULE('test-013-m2', 'CALL <% database %>.OMD_TEST.INSERT_ROW(:ModuleInstanceId, ''m2'')', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;
    CALL <% database %>.OMD.RUN_BATCH('test-013-b', 0, 'test-013 run 2') INTO :V_RESULT;
    V_BATCH_INSTANCE_ID_2 := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_NUMBER := GET(V_RESULT, 'MODULES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'MODULES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 Batch status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 Modules run: expected 2, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 Modules failed: expected 0, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;

    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_3
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-013-m1' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_4
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-013-m2' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID_3;
    IF (NOT COALESCE((V_TEXT = 'Cancelled'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2: the Module that succeeded in run 1 is skipped: expected Cancelled, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID_4;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2: the failed Module ran again: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2: the failed Module internal processing code: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the first Module (run 1) kept: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the failed Module (run 1) rolled back: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_4;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'row of the second Module (run 2) loaded: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID_3;
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'the skipped Module loaded nothing: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2 AND EVENT_DETAIL LIKE 'Partial rollback:%';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'event log records the partial rollback: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 Batch Instance execution status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 Batch Instance internal processing code: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
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
