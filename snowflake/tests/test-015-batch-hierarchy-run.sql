/*
 * DIRECT Framework - Snowflake edition
 * Regression test 015: run of a Batch hierarchy
 *
 * A parent Batch without Modules runs its child Batches in sequence, a child runs its own
 * child: four linked Batch Instances, the Module Instances bound to the leaf Batch
 * Instances. A failure in a child Batch travels up to the parent (THROW_ON_FAILURE N).
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-015-batch-hierarchy-run';
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
    CALL <% database %>.OMD.REGISTER_BATCH('test-015-p', 'Project') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_BATCH('test-015-c1', 'Layer') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_BATCH('test-015-c2', 'Layer') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_BATCH('test-015-g', 'Batch') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-015-c1', 'test-015-p', 1) INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-015-c2', 'test-015-p', 2) INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-015-g', 'test-015-c1', 1) INTO :V_MESSAGE;
    CALL <% database %>.OMD.REGISTER_MODULE('test-015-mg', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-015-mc2', 'SELECT 2') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-015-mg', 'test-015-g') INTO :V_MESSAGE;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-015-mc2', 'test-015-c2') INTO :V_MESSAGE;

    CALL <% database %>.OMD.RUN_BATCH('test-015-p', 0, 'test-015 run 1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'CHILD_BATCHES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'CHILD_BATCHES_FAILED')::NUMBER;
    V_COUNT := GET(V_RESULT, 'MODULES')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'parent result status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'child Batches run: expected 2, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'child Batches failed: expected 0, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Modules of the parent itself: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.BATCH_INSTANCE WHERE PARENT_BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID AND EXECUTION_STATUS_CODE = 'Succeeded';
    IF (NOT COALESCE((V_COUNT = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'two child Batch Instances under the parent: expected 2, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT MAX(bi.BATCH_INSTANCE_ID) INTO :V_ID FROM <% database %>.OMD.BATCH_INSTANCE bi JOIN <% database %>.OMD.BATCH b ON bi.BATCH_ID = b.BATCH_ID WHERE b.BATCH_CODE = 'test-015-c1' AND bi.PARENT_BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(bi.BATCH_INSTANCE_ID) INTO :V_ID_2 FROM <% database %>.OMD.BATCH_INSTANCE bi JOIN <% database %>.OMD.BATCH b ON bi.BATCH_ID = b.BATCH_ID WHERE b.BATCH_CODE = 'test-015-c2' AND bi.PARENT_BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    SELECT MAX(bi.BATCH_INSTANCE_ID) INTO :V_ID_3 FROM <% database %>.OMD.BATCH_INSTANCE bi JOIN <% database %>.OMD.BATCH b ON bi.BATCH_ID = b.BATCH_ID WHERE b.BATCH_CODE = 'test-015-g' AND bi.PARENT_BATCH_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_ID IS NOT NULL AND V_ID_2 IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'child Batch Instances missing' || '; ';
    END IF;
    IF (NOT COALESCE((V_ID < V_ID_2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'child Batches did not run in sequence' || '; ';
    END IF;
    IF (NOT COALESCE((V_ID_3 IS NOT NULL AND V_ID_3 > V_ID AND V_ID_3 < V_ID_2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'grandchild did not run under the first child, before the second child' || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID IN (:V_BATCH_INSTANCE_ID, :V_ID, :V_ID_2, :V_ID_3) AND EXECUTION_STATUS_CODE = 'Succeeded' AND END_TIMESTAMP IS NOT NULL;
    IF (NOT COALESCE((V_COUNT = 4), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'all four Batch Instances succeeded and are closed: expected 4, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_4
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-015-mg' AND mi.BATCH_INSTANCE_ID = :V_ID_3;
    IF (NOT COALESCE((V_ID_4 IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'the grandchild Module Instance is not bound to the grandchild Batch Instance' || '; ';
    END IF;
    SELECT MAX(mi.MODULE_INSTANCE_ID) INTO :V_ID_4
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE m ON mi.MODULE_ID = m.MODULE_ID
    WHERE m.MODULE_CODE = 'test-015-mc2' AND mi.BATCH_INSTANCE_ID = :V_ID_2;
    IF (NOT COALESCE((V_ID_4 IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'the second child Module Instance is not bound to its Batch Instance' || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_REPORTING.VW_EXECUTION_LOG_BATCH_INSTANCE WHERE BATCH_INSTANCE_ID IN (:V_BATCH_INSTANCE_ID, :V_ID, :V_ID_2, :V_ID_3);
    IF (NOT COALESCE((V_COUNT = 4), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'batch instance view shows the hierarchy run: expected 4, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    -- A failing third child: the failure travels up to the parent.
    CALL <% database %>.OMD.REGISTER_BATCH('test-015-c3', 'Layer') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-015-c3', 'test-015-p', 3) INTO :V_MESSAGE;
    CALL <% database %>.OMD.REGISTER_MODULE('test-015-mf', 'SELECT 1/0') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-015-mf', 'test-015-c3') INTO :V_MESSAGE;
    CALL <% database %>.OMD.RUN_BATCH('test-015-p', 0, 'test-015 run 2') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'CHILD_BATCHES')::NUMBER;
    V_NUMBER_2 := GET(V_RESULT, 'CHILD_BATCHES_FAILED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 parent result status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 3), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 child Batches run: expected 3, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER_2 = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 child Batches failed: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER_2), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.BATCH_INSTANCE WHERE PARENT_BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID AND EXECUTION_STATUS_CODE = 'Failed';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2: one failed child Batch Instance: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.BATCH_INSTANCE WHERE BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT = 'Failed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 parent Batch Instance execution status: expected Failed, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
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
