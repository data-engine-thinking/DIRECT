/*
 * DIRECT Framework - Snowflake edition
 * Regression test 012: Batch with a failing Module
 *
 * In a Batch of two Modules the second fails: the Batch is Failed with the counts in the
 * result (THROW_ON_FAILURE N). With STOP_BATCH_ON_MODULE_FAILURE Y a failure stops the
 * Batch before the next Module, with N the remaining Modules still run. With
 * THROW_ON_FAILURE Y a top-level RUN_BATCH raises after the bookkeeping.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-012-batch-module-failure';
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
    CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'Y');
    CALL <% database %>.OMD.REGISTER_BATCH('test-012-b') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-012-m1', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-012-m2', 'SELECT 1/0') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-012-m1', 'test-012-b', 1) INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-012-m2', 'test-012-b', 2) INTO :V_MESSAGE;

    CALL <% database %>.OMD.RUN_BATCH('test-012-b', 0, 'test-012 run 1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'MODULES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'MODULES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch result status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Modules run: expected 2, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Modules failed: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Instance execution status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Instance next run status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-012-m1' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_2
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-012-m2' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(EXECUTION_STATUS_CODE) INTO :V_TEXT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE) INTO :V_TEXT_2, :V_TEXT_3 FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'first Module instance: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second Module instance: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Rollback'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second Module instance next run status: expected Rollback, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    -- The failing Module first: with STOP_BATCH_ON_MODULE_FAILURE Y the second Module does not run.
    CALL <% database %>.OMD.REGISTER_BATCH('test-012-b2') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-012-m3', 'SELECT 1/0') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-012-m4', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-012-m3', 'test-012-b2', 1) INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-012-m4', 'test-012-b2', 2) INTO :V_MESSAGE;
    CALL <% database %>.OMD.RUN_BATCH('test-012-b2', 0, 'test-012 stop') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'MODULES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'MODULES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'stop: Batch result status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'stop: Modules run (stopped after the failure): expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'stop: Modules failed: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID WHERE m.MODULE_CODE = 'test-012-m4';
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'stop: the Module after the failure did not run: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    -- With STOP_BATCH_ON_MODULE_FAILURE N the second Module runs (the failed one is rolled back first).
    CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'N');
    CALL <% database %>.OMD.RUN_BATCH('test-012-b2', 0, 'test-012 continue') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'MODULES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'MODULES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'continue: Batch result status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'continue: Modules run: expected 2, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'continue: Modules failed: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-012-m4' AND mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(EXECUTION_STATUS_CODE) INTO :V_TEXT FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'continue: the Module after the failure ran: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'Y');

    -- With THROW_ON_FAILURE Y the top-level Batch raises after the bookkeeping.
    CALL <% database %>.OMD.SET_SETTING('THROW_ON_FAILURE', 'Y');
    V_RAISED := FALSE;
    V_ERROR := NULL;
    BEGIN
        CALL <% database %>.OMD.RUN_BATCH('test-012-b', 0, 'test-012 run 2') INTO :V_RESULT;
    EXCEPTION
        WHEN OTHER THEN
            V_RAISED := TRUE;
            V_ERROR := SQLERRM;
    END;
    IF (NOT COALESCE((V_RAISED), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'RUN_BATCH did not raise although a Module failed and THROW_ON_FAILURE is Y' || '; ';
    END IF;
    SELECT MAX(bi.BATCH_INSTANCE_ID) INTO :V_BATCH_INSTANCE_ID_2 FROM <% database %>.OMD.BATCH_INSTANCE bi JOIN <% database %>.OMD.BATCH b ON bi.BATCH_ID = b.BATCH_ID WHERE b.BATCH_CODE = 'test-012-b';
    IF (NOT COALESCE((V_BATCH_INSTANCE_ID_2 > V_BATCH_INSTANCE_ID), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'no new Batch Instance for the second run' || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID_2;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second run Batch Instance execution status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 IS NOT NULL AND V_TEXT_3 IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'second run Batch Instance not closed' || '; ';
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
