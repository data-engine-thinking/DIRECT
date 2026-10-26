/*
 * DIRECT Framework - Snowflake edition
 * Regression test 001: basic Module execution
 *
 * A Module that is not registered yet runs stand-alone with a query (auto-registration
 * on). The run succeeds, the Module Instance is closed with the right codes, the executed
 * code is stored by checksum, the load window is recorded and the reporting view shows the
 * run.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-001-basic-module-execution';
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
    CALL <% database %>.OMD.RUN_MODULE('test-001-m', 0, 'test-001 context', 'SELECT 1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_NUMBER := GET(V_RESULT, 'ROWS_INSERTED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_INTERNAL = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result internal processing status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_INTERNAL), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result rows inserted: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_ID IS NOT NULL), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'result holds no Module Instance Id' || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.MODULE WHERE MODULE_CODE = 'test-001-m';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module auto-registered: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT MAX(EXECUTION_STATUS_CODE), MAX(NEXT_RUN_STATUS_CODE), MAX(INTERNAL_PROCESSING_CODE) INTO :V_TEXT, :V_TEXT_2, :V_TEXT_3
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    SELECT MAX(ROWS_INSERTED), MAX(EXECUTION_CONTEXT), COUNT(END_TIMESTAMP) INTO :V_NUMBER, :V_TEXT_4, :V_COUNT
    FROM <% database %>.OMD.MODULE_INSTANCE WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance execution status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance next run status: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_3 = 'Proceed'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance internal processing code: expected Proceed, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance rows inserted: expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_4 = 'test-001 context'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance execution context: expected test-001 context, got ' || COALESCE(TO_VARCHAR(V_TEXT_4), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Module Instance end timestamp set: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT MAX(ec.EXECUTED_CODE) INTO :V_TEXT
    FROM <% database %>.OMD.MODULE_INSTANCE mi JOIN <% database %>.OMD.MODULE_INSTANCE_EXECUTED_CODE ec ON mi.EXECUTED_CODE_CHECKSUM = ec.CHECKSUM
    WHERE mi.MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT = 'SELECT 1'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'executed code stored: expected SELECT 1, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.SOURCE_CONTROL WHERE MODULE_INSTANCE_ID = :V_ID AND START_VALUE IS NOT NULL AND END_VALUE IS NOT NULL;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'load window recorded: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_REPORTING.VW_EXECUTION_LOG_MODULE_INSTANCE
    WHERE MODULE_INSTANCE_ID = :V_ID AND MODULE_CODE = 'test-001-m' AND EXECUTION_STATUS_CODE = 'Succeeded' AND EXECUTION_STATUS_DESCRIPTION IS NOT NULL;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'reporting view shows the run: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
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
