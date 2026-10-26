/*
 * DIRECT Framework - Snowflake edition
 * Regression test 016: disabled Module
 *
 * A Module registered with active indicator N is cancelled when it runs stand-alone, and
 * runs after it is enabled.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-016-disabled-module';
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
    CALL <% database %>.OMD.REGISTER_MODULE('test-016-m', 'SELECT 1', 'MAINT', 'N/A', 'N/A', '', 'DataLogistics', 'On-demand', 'N') INTO :V_NUMBER;
    CALL <% database %>.OMD.RUN_MODULE('test-016-m', 0, 'test-016') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Cancelled'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result status of a disabled Module: expected Cancelled, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_INTERNAL = 'Cancel'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result internal processing status: expected Cancel, got ' || COALESCE(TO_VARCHAR(V_INTERNAL), 'NULL') || '; ';
    END IF;
    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Cancelled'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance execution status: expected Cancelled, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance next run status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Cancel'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance internal processing code: expected Cancel, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    UPDATE <% database %>.OMD.MODULE SET ACTIVE_INDICATOR = 'Y' WHERE MODULE_CODE = 'test-016-m';
    CALL <% database %>.OMD.RUN_MODULE('test-016-m', 0, 'test-016') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result status after enabling the Module: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
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
