/*
 * DIRECT Framework - Snowflake edition
 * Regression tests: setup
 *
 * Creates the test schema OMD_TEST in the database the tests run against, with the
 * result table, a target table for the rollback tests, a source table for the load
 * window test and two helper procedures. Sets the framework settings to their defaults. Run by scripts/Run-DirectSnowflakeTests.ps1.
 */

CREATE SCHEMA IF NOT EXISTS <% database %>.OMD_TEST;

CREATE OR REPLACE TABLE <% database %>.OMD_TEST.TEST_RESULT
(
    TEST_NAME       VARCHAR(200)   NOT NULL,
    RESULT          VARCHAR(10)    NOT NULL,
    OUTPUT          VARCHAR(4000),
    RUN_TIMESTAMP   TIMESTAMP_NTZ  NOT NULL DEFAULT SYSDATE()
);

-- A target data object for the rollback tests: the audit trail column is MODULE_INSTANCE_ID.
CREATE OR REPLACE TABLE <% database %>.OMD_TEST.TARGET
(
    MODULE_INSTANCE_ID  NUMBER(38,0)  NOT NULL,
    VALUE               VARCHAR(400)
);

-- A source data object for the load window test: the load window attribute is LOAD_TIMESTAMP.
CREATE OR REPLACE TABLE <% database %>.OMD_TEST.SOURCE
(
    ID              NUMBER(38,0)   NOT NULL,
    LOAD_TIMESTAMP  TIMESTAMP_NTZ  NOT NULL
);

INSERT INTO <% database %>.OMD_TEST.SOURCE (ID, LOAD_TIMESTAMP)
VALUES (1, '2026-01-01 10:00:00'), (2, '2026-01-02 11:00:00');

-- An executable that loads one row and reports it.
CREATE OR REPLACE PROCEDURE <% database %>.OMD_TEST.INSERT_ROW(P_MODULE_INSTANCE_ID NUMBER, P_VALUE VARCHAR DEFAULT 'row')
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
    INSERT INTO <% database %>.OMD_TEST.TARGET (MODULE_INSTANCE_ID, VALUE) VALUES (:P_MODULE_INSTANCE_ID, :P_VALUE);
    RETURN 1;
END;
$$;

-- An executable that loads one row and then fails, leaving the row behind for the rollback.
CREATE OR REPLACE PROCEDURE <% database %>.OMD_TEST.INSERT_THEN_FAIL(P_MODULE_INSTANCE_ID NUMBER)
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    FORCED_FAILURE EXCEPTION (-20100, 'Forced failure after loading a row.');
BEGIN
    INSERT INTO <% database %>.OMD_TEST.TARGET (MODULE_INSTANCE_ID, VALUE) VALUES (:P_MODULE_INSTANCE_ID, 'loaded before the failure');
    RAISE FORCED_FAILURE;
END;
$$;

-- The settings the tests rely on, at their defaults.
CALL <% database %>.OMD.SET_SETTING('THROW_ON_FAILURE', 'Y');
CALL <% database %>.OMD.SET_SETTING('FAIL_BATCH_ON_MODULE_FAILURE', 'Y');
CALL <% database %>.OMD.SET_SETTING('STOP_BATCH_ON_MODULE_FAILURE', 'Y');
CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_BATCHES', 'Y');
CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_MODULES', 'Y');
CALL <% database %>.OMD.SET_SETTING('AUTO_REGISTER_RELATIONSHIPS', 'Y');
CALL <% database %>.OMD.SET_SETTING('MODULE_INSTANCE_ID_COLUMN_NAME', 'MODULE_INSTANCE_ID');
CALL <% database %>.OMD.SET_SETTING('LOAD_WINDOW_ATTRIBUTE_NAME', '');
