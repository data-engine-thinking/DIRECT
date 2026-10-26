/*
 * DIRECT Framework - Snowflake edition
 * Regression test 023: queue Task
 *
 * START_QUEUE creates and resumes the Task of a Batch, STOP_QUEUE suspends it and
 * REMOVE_QUEUE drops it. The test is skipped (Skip) when the role lacks the privilege to
 * create or resume the Task (EXECUTE MANAGED TASK for a serverless Task, EXECUTE TASK to
 * resume); pass -Warehouse to the runner to use a warehouse Task instead of a serverless
 * one.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-023-queue-task';
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
    V_WAREHOUSE := NULLIF(NULLIF('<% warehouse %>', ''), 'NONE');
    CALL <% database %>.OMD.REGISTER_BATCH('test-023-b') INTO :V_NUMBER;
    V_TEXT_4 := <% database %>.OMD.GET_QUEUE_TASK_NAME('test-023-b');
    IF (NOT COALESCE((V_TEXT_4 = 'QUEUE_TEST_023_B'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'task name: expected QUEUE_TEST_023_B, got ' || COALESCE(TO_VARCHAR(V_TEXT_4), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.START_QUEUE('test-023-x', 15) INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The Batch ''test-023-x'' is not registered.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'unregistered Batch message: expected The Batch ''test-023-x'' is not registered., got ' || COALESCE(TO_VARCHAR(V_MESSAGE), 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.START_QUEUE('test-023-b', 0) INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The interval must be at least 1 minute.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'interval message: expected The interval must be at least 1 minute., got ' || COALESCE(TO_VARCHAR(V_MESSAGE), 'NULL') || '; ';
    END IF;

    V_RAISED := FALSE;
    V_ERROR := NULL;
    BEGIN
        CALL <% database %>.OMD.START_QUEUE('test-023-b', 15, :V_WAREHOUSE) INTO :V_MESSAGE;
    EXCEPTION
        WHEN OTHER THEN
            V_RAISED := TRUE;
            V_ERROR := SQLERRM;
    END;
    IF (V_RAISED) THEN
        -- Clean up a Task that was created but could not be resumed.
        CALL <% database %>.OMD.REMOVE_QUEUE('test-023-b') INTO :V_TEXT;
        IF (V_ERROR ILIKE '%privilege%' OR V_ERROR ILIKE '%not authorized%' OR V_ERROR ILIKE '%EXECUTE MANAGED TASK%' OR V_ERROR ILIKE '%EXECUTE TASK%' OR V_ERROR ILIKE '%Insufficient%') THEN
            V_SKIP := TRUE;
            V_OUTPUT := 'Skipped: the role cannot create or resume the Task (' || V_ERROR || ')';
        ELSE
            V_ISSUES := V_ISSUES + 1;
            V_OUTPUT := V_OUTPUT || 'START_QUEUE raised: ' || V_ERROR || '; ';
        END IF;
    ELSE
    IF (NOT COALESCE((V_MESSAGE LIKE 'Task %QUEUE_TEST_023_B runs Batch ''test-023-b'' every 15 minute(s).'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'START_QUEUE message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
        SHOW TASKS LIKE 'QUEUE_TEST_023_B' IN SCHEMA <% database %>.OMD;
        SELECT COUNT(*), MAX("state"), MAX("schedule") INTO :V_COUNT, :V_TEXT, :V_TEXT_2 FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task exists after START_QUEUE: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT = 'started'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task state after START_QUEUE: expected started, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = '15 MINUTE'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task schedule: expected 15 MINUTE, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
        SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_PROCESSING.VW_QUEUE_BATCH_PROCESSING WHERE BATCH_CODE = 'test-023-b';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'queue view shows the Batch: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

        CALL <% database %>.OMD.STOP_QUEUE('test-023-b') INTO :V_MESSAGE;
        SHOW TASKS LIKE 'QUEUE_TEST_023_B' IN SCHEMA <% database %>.OMD;
        SELECT COUNT(*), MAX("state") INTO :V_COUNT, :V_TEXT FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task exists after STOP_QUEUE: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT = 'suspended'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task state after STOP_QUEUE: expected suspended, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;

        CALL <% database %>.OMD.REMOVE_QUEUE('test-023-b') INTO :V_MESSAGE;
        SHOW TASKS LIKE 'QUEUE_TEST_023_B' IN SCHEMA <% database %>.OMD;
        SELECT COUNT(*) INTO :V_COUNT FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Task removed after REMOVE_QUEUE: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
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
