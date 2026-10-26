/*
 * DIRECT Framework - Snowflake edition
 * Regression test 010: unregistered Module with and without auto-registration
 *
 * With AUTO_REGISTER_MODULES N a run of an unknown Module creates no instance and logs
 * why. With Y the Module is registered from the query and runs.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-010-unregistered-module';
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
    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_MODULES', 'N');
    CALL <% database %>.OMD.RUN_MODULE('test-010-m', 0, 'test-010', 'SELECT 3') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Aborted'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result status without auto-registration: expected Aborted, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_ID IS NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'a Module Instance was created for an unregistered Module' || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.MODULE WHERE MODULE_CODE = 'test-010-m';
    IF (NOT COALESCE((V_COUNT = 0), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module not registered: expected 0, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.EVENT_LOG WHERE EVENT_DETAIL = 'The Module ''test-010-m'' is not registered and automatic registration is off.';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'event log explains the abort: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_MODULES', 'Y');
    CALL <% database %>.OMD.RUN_MODULE('test-010-m', 0, 'test-010', 'SELECT 3') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'ROWS_INSERTED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result status with auto-registration: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 3), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'rows inserted: expected 3, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*), MAX(EXECUTABLE) INTO :V_COUNT, :V_TEXT FROM <% database %>.OMD.MODULE WHERE MODULE_CODE = 'test-010-m';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module registered: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT = 'SELECT 3'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'registered executable is the query: expected SELECT 3, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
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
