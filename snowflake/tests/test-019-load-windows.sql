/*
 * DIRECT Framework - Snowflake edition
 * Regression test 019: load windows
 *
 * The first run of a Module starts at DEFAULT_START_VALUE; every next run starts where the
 * previous one ended. The end is the given P_END_VALUE, else the maximum of
 * LOAD_WINDOW_ATTRIBUTE_NAME in the source data object, else the current time. RUN_BATCH
 * passes its end value to every Module. The tokens :StartValue and :EndValue reach the
 * executable.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-019-load-windows';
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
    CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', '');
    SELECT MAX(VALUE) INTO :V_TEXT_4 FROM <% database %>.OMD_METADATA.FRAMEWORK_METADATA WHERE CODE = 'DEFAULT_START_VALUE';
    CALL <% database %>.OMD.REGISTER_MODULE('test-019-m', 'INSERT INTO <% database %>.OMD_TEST.TARGET (MODULE_INSTANCE_ID, VALUE) SELECT :ModuleInstanceId, :StartValue || ''|'' || :EndValue', 'MAINT', 'N/A', '<% database %>.OMD_TEST.TARGET') INTO :V_NUMBER;

    CALL <% database %>.OMD.RUN_MODULE('test-019-m', 0, 'test-019 run 1', NULL, 'test-019-end-1') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT := GET(V_RESULT, 'START_VALUE')::VARCHAR;
    V_TEXT_2 := GET(V_RESULT, 'END_VALUE')::VARCHAR;
    V_NUMBER := GET(V_RESULT, 'ROWS_INSERTED')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT = V_TEXT_4), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 start value is not DEFAULT_START_VALUE: ' || COALESCE(V_TEXT, 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'test-019-end-1'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 end value: expected test-019-end-1, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_NUMBER = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 rows inserted (INSERT row count): expected 1, got ' || COALESCE(TO_VARCHAR(V_NUMBER), 'NULL') || '; ';
    END IF;
    SELECT MAX(VALUE) INTO :V_TEXT_3 FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT_3 = V_TEXT_4 || '|test-019-end-1'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 1 tokens in the executable: ' || COALESCE(V_TEXT_3, 'NULL') || '; ';
    END IF;

    CALL <% database %>.OMD.RUN_MODULE('test-019-m', 0, 'test-019 run 2', NULL, 'test-019-end-2') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_ID := GET(V_RESULT, 'MODULE_INSTANCE_ID')::NUMBER;
    V_TEXT := GET(V_RESULT, 'START_VALUE')::VARCHAR;
    V_TEXT_2 := GET(V_RESULT, 'END_VALUE')::VARCHAR;
    IF (NOT COALESCE((V_TEXT = 'test-019-end-1'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 start value is the previous end: expected test-019-end-1, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'test-019-end-2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 end value: expected test-019-end-2, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    SELECT MAX(VALUE) INTO :V_TEXT_3 FROM <% database %>.OMD_TEST.TARGET WHERE MODULE_INSTANCE_ID = :V_ID;
    IF (NOT COALESCE((V_TEXT_3 = 'test-019-end-1|test-019-end-2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 2 tokens in the executable: expected test-019-end-1|test-019-end-2, got ' || COALESCE(TO_VARCHAR(V_TEXT_3), 'NULL') || '; ';
    END IF;

    V_ID_2 := <% database %>.OMD.GET_MODULE_ID_BY_CODE('test-019-m');
    V_TEXT := <% database %>.OMD.GET_MODULE_LOAD_WINDOW_VALUE(V_ID_2, 1);
    V_TEXT_2 := <% database %>.OMD.GET_MODULE_LOAD_WINDOW_VALUE(V_ID_2, 2);
    IF (NOT COALESCE((V_TEXT = 'test-019-end-1'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'last recorded start value: expected test-019-end-1, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = 'test-019-end-2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'last recorded end value: expected test-019-end-2, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD.SOURCE_CONTROL WHERE MODULE_ID = :V_ID_2;
    IF (NOT COALESCE((V_COUNT = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'two load windows recorded: expected 2, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT MAX(LAST_END_VALUE) INTO :V_TEXT FROM <% database %>.OMD_REPORTING.VW_LOAD_WINDOWS WHERE MODULE_CODE = 'test-019-m';
    IF (NOT COALESCE((V_TEXT = 'test-019-end-2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'load windows view: expected test-019-end-2, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;

    -- No end value given and no load window attribute: the end is the current time, in TIMESTAMP_FORMAT.
    CALL <% database %>.OMD.RUN_MODULE('test-019-m', 0, 'test-019 run 3') INTO :V_RESULT;
    V_TEXT := GET(V_RESULT, 'START_VALUE')::VARCHAR;
    V_TEXT_2 := GET(V_RESULT, 'END_VALUE')::VARCHAR;
    IF (NOT COALESCE((V_TEXT = 'test-019-end-2'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 3 start value: expected test-019-end-2, got ' || COALESCE(TO_VARCHAR(V_TEXT), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((TRY_TO_TIMESTAMP_NTZ(V_TEXT_2, 'YYYY-MM-DD HH24:MI:SS.FF7') IS NOT NULL AND TRY_TO_TIMESTAMP_NTZ(V_TEXT_2, 'YYYY-MM-DD HH24:MI:SS.FF7') > DATEADD(hour, -1, SYSDATE())), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'run 3 end value is not a recent timestamp: ' || COALESCE(V_TEXT_2, 'NULL') || '; ';
    END IF;

    -- The maximum of the load window attribute in the source data object.
    CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', 'LOAD_TIMESTAMP');
    CALL <% database %>.OMD.REGISTER_MODULE('test-019-ms', 'SELECT 1', 'MAINT', '<% database %>.OMD_TEST.SOURCE', 'N/A') INTO :V_NUMBER;
    CALL <% database %>.OMD.RUN_MODULE('test-019-ms', 0, 'test-019 source window') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_TEXT_2 := GET(V_RESULT, 'END_VALUE')::VARCHAR;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'source window run status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT_2 = '2026-01-02 11:00:00.0000000'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'end value from the source data object: expected 2026-01-02 11:00:00.0000000, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', '');

    -- RUN_BATCH passes its end value to the Modules.
    CALL <% database %>.OMD.REGISTER_BATCH('test-019-b') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_MODULE('test-019-mb', 'SELECT 1') INTO :V_NUMBER;
    CALL <% database %>.OMD.ADD_MODULE_TO_BATCH('test-019-mb', 'test-019-b') INTO :V_MESSAGE;
    CALL <% database %>.OMD.RUN_BATCH('test-019-b', 0, 'test-019 batch', 'test-019-batch-end') INTO :V_RESULT;
    V_STATUS := GET(V_RESULT, 'EXECUTION_STATUS_CODE')::VARCHAR;
    V_INTERNAL := GET(V_RESULT, 'INTERNAL_PROCESSING_STATUS_CODE')::VARCHAR;
    V_BATCH_INSTANCE_ID := GET(V_RESULT, 'BATCH_INSTANCE_ID')::NUMBER;
    IF (NOT COALESCE((V_STATUS = 'Succeeded'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch run status: expected Succeeded, got ' || COALESCE(TO_VARCHAR(V_STATUS), 'NULL') || '; ';
    END IF;
    SELECT MAX(sc.END_VALUE), MAX(sc.START_VALUE) INTO :V_TEXT_2, :V_TEXT
    FROM <% database %>.OMD.SOURCE_CONTROL sc JOIN <% database %>.OMD.MODULE_INSTANCE mi ON sc.MODULE_INSTANCE_ID = mi.MODULE_INSTANCE_ID
    WHERE mi.BATCH_INSTANCE_ID = :V_BATCH_INSTANCE_ID;
    IF (NOT COALESCE((V_TEXT_2 = 'test-019-batch-end'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch end value passed to the Module: expected test-019-batch-end, got ' || COALESCE(TO_VARCHAR(V_TEXT_2), 'NULL') || '; ';
    END IF;
    IF (NOT COALESCE((V_TEXT = V_TEXT_4), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'Batch Module start value is not DEFAULT_START_VALUE: ' || COALESCE(V_TEXT, 'NULL') || '; ';
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
