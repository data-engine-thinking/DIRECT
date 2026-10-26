/*
 * DIRECT Framework - Snowflake edition
 * 09 Queue procedures
 *
 * The queue is a Snowflake Task per Batch that calls RUN_BATCH on a schedule:
 * the trickle feed. START_QUEUE creates (or replaces) and resumes the Task,
 * STOP_QUEUE suspends it, REMOVE_QUEUE drops it. The Task is serverless unless
 * a warehouse is given. A run that starts while the previous one is still
 * running is skipped by Snowflake (tasks do not overlap by default), and the
 * Batch evaluation aborts a second instance in any case.
 *
 * The owner of these procedures needs CREATE TASK on the OMD schema and, for
 * serverless Tasks, EXECUTE MANAGED TASK on the account; EXECUTE TASK on the
 * account is needed to resume a Task.
 */

CREATE OR REPLACE FUNCTION <% database %>.OMD.GET_QUEUE_TASK_NAME(P_BATCH_CODE VARCHAR)
RETURNS VARCHAR
AS
$$
    'QUEUE_' || UPPER(REGEXP_REPLACE(P_BATCH_CODE, '[^A-Za-z0-9_]', '_'))
$$;

CREATE OR REPLACE PROCEDURE <% database %>.OMD.START_QUEUE
(
    P_BATCH_CODE        VARCHAR,
    P_INTERVAL_MINUTES  NUMBER DEFAULT 15,
    P_WAREHOUSE         VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Creates or replaces the Task that runs the Batch every P_INTERVAL_MINUTES minutes (serverless, or on P_WAREHOUSE when given) and resumes it.'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_TASK VARCHAR;
    V_STATEMENT VARCHAR;
    V_SIZE VARCHAR;
BEGIN
    IF (<% database %>.OMD.GET_BATCH_ID_BY_CODE(P_BATCH_CODE) IS NULL) THEN
        RETURN 'The Batch ''' || COALESCE(P_BATCH_CODE, '') || ''' is not registered.';
    END IF;
    IF (P_INTERVAL_MINUTES IS NULL OR P_INTERVAL_MINUTES < 1) THEN
        RETURN 'The interval must be at least 1 minute.';
    END IF;

    V_TASK := '<% database %>.OMD.' || <% database %>.OMD.GET_QUEUE_TASK_NAME(P_BATCH_CODE);
    V_SIZE := COALESCE(<% database %>.OMD_METADATA.GET_SETTING('QUEUE_WAREHOUSE_SIZE'), 'XSMALL');

    V_STATEMENT := 'CREATE OR REPLACE TASK ' || V_TASK
        || IFF(P_WAREHOUSE IS NULL, ' USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = ''' || V_SIZE || '''', ' WAREHOUSE = ' || P_WAREHOUSE)
        || ' SCHEDULE = ''' || TO_VARCHAR(P_INTERVAL_MINUTES) || ' MINUTE'''
        || ' ALLOW_OVERLAPPING_EXECUTION = FALSE'
        || ' COMMENT = ''DIRECT queue for Batch ' || REPLACE(P_BATCH_CODE, '''', '''''') || ''''
        || ' AS CALL <% database %>.OMD.RUN_BATCH(''' || REPLACE(P_BATCH_CODE, '''', '''''') || ''', 0, ''Task ' || <% database %>.OMD.GET_QUEUE_TASK_NAME(P_BATCH_CODE) || ''')';
    EXECUTE IMMEDIATE :V_STATEMENT;

    V_STATEMENT := 'ALTER TASK ' || V_TASK || ' RESUME';
    EXECUTE IMMEDIATE :V_STATEMENT;

    RETURN 'Task ' || V_TASK || ' runs Batch ''' || P_BATCH_CODE || ''' every ' || TO_VARCHAR(P_INTERVAL_MINUTES) || ' minute(s).';
END;
$$;

CREATE OR REPLACE PROCEDURE <% database %>.OMD.STOP_QUEUE
(
    P_BATCH_CODE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Suspends the Task of the Batch. A run that is in progress completes.'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_TASK VARCHAR;
    V_STATEMENT VARCHAR;
BEGIN
    V_TASK := '<% database %>.OMD.' || <% database %>.OMD.GET_QUEUE_TASK_NAME(P_BATCH_CODE);
    V_STATEMENT := 'ALTER TASK IF EXISTS ' || V_TASK || ' SUSPEND';
    EXECUTE IMMEDIATE :V_STATEMENT;
    RETURN 'Task ' || V_TASK || ' is suspended.';
END;
$$;

CREATE OR REPLACE PROCEDURE <% database %>.OMD.REMOVE_QUEUE
(
    P_BATCH_CODE VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Drops the Task of the Batch.'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_TASK VARCHAR;
    V_STATEMENT VARCHAR;
BEGIN
    V_TASK := '<% database %>.OMD.' || <% database %>.OMD.GET_QUEUE_TASK_NAME(P_BATCH_CODE);
    V_STATEMENT := 'DROP TASK IF EXISTS ' || V_TASK;
    EXECUTE IMMEDIATE :V_STATEMENT;
    RETURN 'Task ' || V_TASK || ' is removed.';
END;
$$;
