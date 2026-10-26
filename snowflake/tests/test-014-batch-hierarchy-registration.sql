/*
 * DIRECT Framework - Snowflake edition
 * Regression test 014: Batch hierarchy registration
 *
 * ADD_BATCH_TO_PARENT_BATCH adds a child once, reports a duplicate, refuses a cycle and
 * refuses a Batch as its own parent; the hierarchy view shows the relationship with its
 * sequence.
 *
 * Writes one row to <% database %>.OMD_TEST.TEST_RESULT (Pass, Fail or Skip) and returns the
 * outcome. Run by scripts/Run-DirectSnowflakeTests.ps1 after tests/00_Setup.sql.
 */

EXECUTE IMMEDIATE $$
DECLARE
    V_TEST VARCHAR DEFAULT 'test-014-batch-hierarchy-registration';
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
    CALL <% database %>.OMD.REGISTER_BATCH('test-014-p', 'Project') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_BATCH('test-014-c', 'Batch') INTO :V_NUMBER;
    CALL <% database %>.OMD.REGISTER_BATCH('test-014-g', 'Batch') INTO :V_NUMBER;

    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-c', 'test-014-p') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The Batch ''test-014-c'' was added to ''test-014-p'' at position 1.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'add message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-c', 'test-014-p') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The Batch ''test-014-c'' is already a child of ''test-014-p''.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'duplicate message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-g', 'test-014-c', 5) INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The Batch ''test-014-g'' was added to ''test-014-c'' at position 5.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'grandchild message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-p', 'test-014-g') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'Adding Batch ''test-014-p'' under ''test-014-g'' would create a cycle.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'cycle message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-p', 'test-014-p') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'A Batch cannot be its own parent.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'own parent message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;
    CALL <% database %>.OMD.ADD_BATCH_TO_PARENT_BATCH('test-014-x', 'test-014-p') INTO :V_MESSAGE;
    IF (NOT COALESCE((V_MESSAGE = 'The Batch ''test-014-x'' is not registered.'), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'unregistered message: ' || COALESCE(V_MESSAGE, 'NULL') || '; ';
    END IF;

    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_PROCESSING.VW_BATCH_HIERARCHY WHERE PARENT_BATCH_CODE = 'test-014-p' AND BATCH_CODE = 'test-014-c' AND SEQUENCE = 1 AND ACTIVE_INDICATOR = 'Y';
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'hierarchy view shows parent and child: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_PROCESSING.VW_BATCH_HIERARCHY WHERE PARENT_BATCH_CODE = 'test-014-c' AND BATCH_CODE = 'test-014-g' AND SEQUENCE = 5;
    IF (NOT COALESCE((V_COUNT = 1), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'hierarchy view shows child and grandchild: expected 1, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
    END IF;
    SELECT COUNT(*) INTO :V_COUNT FROM <% database %>.OMD_PROCESSING.VW_BATCH_HIERARCHY WHERE PARENT_BATCH_CODE IN ('test-014-p', 'test-014-c', 'test-014-g');
    IF (NOT COALESCE((V_COUNT = 2), FALSE)) THEN
        V_ISSUES := V_ISSUES + 1;
        V_OUTPUT := V_OUTPUT || 'no other relationships were added: expected 2, got ' || COALESCE(TO_VARCHAR(V_COUNT), 'NULL') || '; ';
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
