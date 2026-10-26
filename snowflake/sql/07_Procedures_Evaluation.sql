/*
 * DIRECT Framework - Snowflake edition
 * 07 Evaluation procedures
 *
 * BATCH_EVALUATION and MODULE_EVALUATION decide whether a new instance may run
 * (Proceed), is skipped (Cancel) or must not run (Abort), and roll back the data
 * of earlier failed instances before a new run proceeds. They return the
 * Internal Processing Status Code and leave the instance updated accordingly.
 */

CREATE OR REPLACE PROCEDURE <% database %>.OMD.BATCH_EVALUATION
(
    P_BATCH_INSTANCE_ID NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Evaluates a new Batch Instance: Abort when another instance of the Batch is executing, Cancel when the Batch is inactive or its previous instance was set to Cancel, otherwise Proceed after marking the Module Instances of earlier failed runs for rollback or skipping.'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_BATCH_ID NUMBER;
    V_ACTIVE_INDICATOR VARCHAR;
    V_OTHER_EXECUTING NUMBER;
    V_PREVIOUS_EXECUTION_STATUS_CODE VARCHAR;
    V_PREVIOUS_NEXT_RUN_STATUS_CODE VARCHAR;
    V_LAST_GOOD_BATCH_INSTANCE_ID NUMBER;
    V_MESSAGE VARCHAR;
BEGIN
    V_BATCH_ID := <% database %>.OMD.GET_BATCH_ID_BY_BATCH_INSTANCE_ID(P_BATCH_INSTANCE_ID);

    IF (V_BATCH_ID IS NULL) THEN
        V_MESSAGE := 'The Batch Instance ' || COALESCE(TO_VARCHAR(P_BATCH_INSTANCE_ID), 'NULL') || ' does not exist.';
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, 0, :P_BATCH_INSTANCE_ID);
        RETURN 'Abort';
    END IF;

    -- Another instance of the same Batch that started earlier and is still executing: this one must not run.
    SELECT COUNT(*) INTO :V_OTHER_EXECUTING
    FROM <% database %>.OMD.BATCH_INSTANCE
    WHERE BATCH_ID = :V_BATCH_ID AND EXECUTION_STATUS_CODE = 'Executing' AND BATCH_INSTANCE_ID < :P_BATCH_INSTANCE_ID;

    IF (V_OTHER_EXECUTING > 0) THEN
        V_MESSAGE := 'Another instance of Batch ' || TO_VARCHAR(V_BATCH_ID) || ' is still executing. Batch Instance ' || TO_VARCHAR(P_BATCH_INSTANCE_ID) || ' is aborted.';
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, 0, :P_BATCH_INSTANCE_ID);
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Abort');
        RETURN 'Abort';
    END IF;

    -- An inactive Batch is skipped.
    SELECT MAX(ACTIVE_INDICATOR) INTO :V_ACTIVE_INDICATOR FROM <% database %>.OMD.BATCH WHERE BATCH_ID = :V_BATCH_ID;
    IF (V_ACTIVE_INDICATOR = 'N') THEN
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Cancel');
        RETURN 'Cancel';
    END IF;

    -- The previous instance of the Batch decides whether a rollback is needed.
    SELECT COALESCE(MAX_BY(EXECUTION_STATUS_CODE, BATCH_INSTANCE_ID), 'Succeeded'), COALESCE(MAX_BY(NEXT_RUN_STATUS_CODE, BATCH_INSTANCE_ID), 'Proceed')
    INTO :V_PREVIOUS_EXECUTION_STATUS_CODE, :V_PREVIOUS_NEXT_RUN_STATUS_CODE
    FROM <% database %>.OMD.BATCH_INSTANCE
    WHERE BATCH_ID = :V_BATCH_ID AND BATCH_INSTANCE_ID <> :P_BATCH_INSTANCE_ID AND EXECUTION_STATUS_CODE <> 'Executing';

    IF (V_PREVIOUS_NEXT_RUN_STATUS_CODE = 'Cancel') THEN
        -- A one-off skip, set by an administrator on the previous instance.
        UPDATE <% database %>.OMD.BATCH_INSTANCE SET NEXT_RUN_STATUS_CODE = 'Proceed' WHERE BATCH_ID = :V_BATCH_ID AND NEXT_RUN_STATUS_CODE = 'Cancel' AND BATCH_INSTANCE_ID <> :P_BATCH_INSTANCE_ID;
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Cancel');
        RETURN 'Cancel';
    END IF;

    IF (V_PREVIOUS_EXECUTION_STATUS_CODE <> 'Failed' AND V_PREVIOUS_NEXT_RUN_STATUS_CODE <> 'Rollback') THEN
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Proceed');
        RETURN 'Proceed';
    END IF;

    -- Rollback. The Batch Instances since the last successful one are the failed runs.
    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Rollback');

    SELECT COALESCE(MAX(BATCH_INSTANCE_ID), 0) INTO :V_LAST_GOOD_BATCH_INSTANCE_ID
    FROM <% database %>.OMD.BATCH_INSTANCE
    WHERE BATCH_ID = :V_BATCH_ID AND EXECUTION_STATUS_CODE = 'Succeeded' AND NEXT_RUN_STATUS_CODE = 'Proceed' AND BATCH_INSTANCE_ID <> :P_BATCH_INSTANCE_ID;

    IF (V_PREVIOUS_NEXT_RUN_STATUS_CODE = 'Rollback') THEN
        -- Full rollback: every Module Instance of the failed runs is rolled back by the Module evaluation.
        UPDATE <% database %>.OMD.MODULE_INSTANCE
        SET NEXT_RUN_STATUS_CODE = 'Rollback'
        WHERE BATCH_INSTANCE_ID IN
        (
            SELECT BATCH_INSTANCE_ID FROM <% database %>.OMD.BATCH_INSTANCE
            WHERE BATCH_ID = :V_BATCH_ID AND BATCH_INSTANCE_ID > :V_LAST_GOOD_BATCH_INSTANCE_ID AND BATCH_INSTANCE_ID <> :P_BATCH_INSTANCE_ID AND EXECUTION_STATUS_CODE <> 'Executing'
        );
        V_MESSAGE := 'Full rollback: the Module Instances of the failed runs of Batch ' || TO_VARCHAR(V_BATCH_ID) || ' are marked for rollback.';
    ELSE
        -- Partial rollback: the Modules that succeeded in the failed runs are skipped, the failed ones are rolled back by the Module evaluation.
        UPDATE <% database %>.OMD.MODULE_INSTANCE
        SET NEXT_RUN_STATUS_CODE = 'Cancel'
        WHERE EXECUTION_STATUS_CODE <> 'Failed'
          AND BATCH_INSTANCE_ID IN
        (
            SELECT BATCH_INSTANCE_ID FROM <% database %>.OMD.BATCH_INSTANCE
            WHERE BATCH_ID = :V_BATCH_ID AND BATCH_INSTANCE_ID > :V_LAST_GOOD_BATCH_INSTANCE_ID AND BATCH_INSTANCE_ID <> :P_BATCH_INSTANCE_ID AND EXECUTION_STATUS_CODE <> 'Executing'
        );
        V_MESSAGE := 'Partial rollback: the Modules that succeeded in the failed runs of Batch ' || TO_VARCHAR(V_BATCH_ID) || ' are skipped, the failed ones are rolled back.';
    END IF;

    IF (<% database %>.OMD_METADATA.GET_SETTING_FLAG('LOG_TO_EVENT_LOG') = 'Y') THEN
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, 0, :P_BATCH_INSTANCE_ID);
    END IF;

    CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Proceed');
    RETURN 'Proceed';
EXCEPTION
    WHEN OTHER THEN
        V_MESSAGE := 'Error in BATCH_EVALUATION: ' || SQLERRM;
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, 0, :P_BATCH_INSTANCE_ID, 1, TO_VARCHAR(:SQLCODE));
        CALL <% database %>.OMD.UPDATE_BATCH_INSTANCE(:P_BATCH_INSTANCE_ID, 'Failure');
        RETURN 'Abort';
END;
$$;

CREATE OR REPLACE PROCEDURE <% database %>.OMD.MODULE_EVALUATION
(
    P_MODULE_INSTANCE_ID NUMBER
)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT = 'Evaluates a new Module Instance: Abort when another instance of the Module is executing or the Batch/Module relationship is missing, Cancel when the Module or the relationship is inactive or the previous run was set to Cancel, otherwise Proceed after rolling back the data of earlier failed instances (DELETE on the target data object by the Module Instance Id column).'
EXECUTE AS OWNER
AS
$$
DECLARE
    V_MODULE_ID NUMBER;
    V_BATCH_ID NUMBER;
    V_MINIMUM_EXECUTING NUMBER;
    V_BATCH_MODULE_ACTIVE_INDICATOR VARCHAR;
    V_MODULE_ACTIVE_INDICATOR VARCHAR;
    V_LAST_MODULE_INSTANCE_ID NUMBER;
    V_LAST_EXECUTION_STATUS_CODE VARCHAR;
    V_LAST_NEXT_RUN_STATUS_CODE VARCHAR;
    V_LAST_GOOD_MODULE_INSTANCE_ID NUMBER;
    V_ROLLBACK_LIST VARCHAR;
    V_DATA_OBJECT_TARGET VARCHAR;
    V_COLUMN_NAME VARCHAR;
    V_STATEMENT VARCHAR;
    V_MESSAGE VARCHAR;
BEGIN
    V_MODULE_ID := <% database %>.OMD.GET_MODULE_ID_BY_MODULE_INSTANCE_ID(P_MODULE_INSTANCE_ID);

    IF (V_MODULE_ID IS NULL) THEN
        V_MESSAGE := 'The Module Instance ' || COALESCE(TO_VARCHAR(P_MODULE_INSTANCE_ID), 'NULL') || ' does not exist.';
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE);
        RETURN 'Abort';
    END IF;

    -- Only the first of several executing instances of the same Module may continue.
    SELECT MIN(MODULE_INSTANCE_ID) INTO :V_MINIMUM_EXECUTING
    FROM <% database %>.OMD.MODULE_INSTANCE
    WHERE MODULE_ID = :V_MODULE_ID AND EXECUTION_STATUS_CODE = 'Executing';

    IF (V_MINIMUM_EXECUTING <> P_MODULE_INSTANCE_ID) THEN
        V_MESSAGE := 'Another instance of Module ' || TO_VARCHAR(V_MODULE_ID) || ' is still executing. Module Instance ' || TO_VARCHAR(P_MODULE_INSTANCE_ID) || ' is aborted.';
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, :P_MODULE_INSTANCE_ID);
        CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Abort');
        RETURN 'Abort';
    END IF;

    -- A Module that runs from a Batch must be active for that Batch.
    V_BATCH_ID := <% database %>.OMD.GET_BATCH_ID_BY_MODULE_INSTANCE_ID(P_MODULE_INSTANCE_ID);

    IF (V_BATCH_ID <> 0) THEN
        V_BATCH_MODULE_ACTIVE_INDICATOR := <% database %>.OMD.GET_BATCH_MODULE_ACTIVE_INDICATOR_VALUE(V_BATCH_ID, V_MODULE_ID);
        IF (V_BATCH_MODULE_ACTIVE_INDICATOR = 'N') THEN
            CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Cancel');
            RETURN 'Cancel';
        END IF;
        IF (V_BATCH_MODULE_ACTIVE_INDICATOR = 'U') THEN
            V_MESSAGE := 'Module ' || TO_VARCHAR(V_MODULE_ID) || ' is not registered for Batch ' || TO_VARCHAR(V_BATCH_ID) || '. Module Instance ' || TO_VARCHAR(P_MODULE_INSTANCE_ID) || ' is aborted.';
            CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, :P_MODULE_INSTANCE_ID);
            CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Abort');
            RETURN 'Abort';
        END IF;
    END IF;

    -- An inactive Module is skipped.
    SELECT MAX(ACTIVE_INDICATOR) INTO :V_MODULE_ACTIVE_INDICATOR FROM <% database %>.OMD.MODULE WHERE MODULE_ID = :V_MODULE_ID;
    IF (V_MODULE_ACTIVE_INDICATOR = 'N') THEN
        CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Cancel');
        RETURN 'Cancel';
    END IF;

    -- The previous instance of the Module, in the same Batch (or stand-alone), decides whether a rollback is needed.
    SELECT COALESCE(MAX(mi.MODULE_INSTANCE_ID), 0) INTO :V_LAST_MODULE_INSTANCE_ID
    FROM <% database %>.OMD.MODULE_INSTANCE mi
    LEFT JOIN <% database %>.OMD.BATCH_INSTANCE bi ON mi.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID
    WHERE mi.MODULE_ID = :V_MODULE_ID
      AND mi.MODULE_INSTANCE_ID <> :P_MODULE_INSTANCE_ID
      AND mi.EXECUTION_STATUS_CODE NOT IN ('Executing', 'Aborted')
      AND COALESCE(bi.BATCH_ID, 0) = :V_BATCH_ID;

    SELECT COALESCE(MAX(EXECUTION_STATUS_CODE), 'Succeeded'), COALESCE(MAX(NEXT_RUN_STATUS_CODE), 'Proceed')
    INTO :V_LAST_EXECUTION_STATUS_CODE, :V_LAST_NEXT_RUN_STATUS_CODE
    FROM <% database %>.OMD.MODULE_INSTANCE
    WHERE MODULE_INSTANCE_ID = :V_LAST_MODULE_INSTANCE_ID AND :V_LAST_MODULE_INSTANCE_ID <> 0;

    IF (V_LAST_NEXT_RUN_STATUS_CODE = 'Cancel') THEN
        -- A one-off skip: the previous instance succeeded in a Batch that failed, or an administrator set it.
        UPDATE <% database %>.OMD.MODULE_INSTANCE SET NEXT_RUN_STATUS_CODE = 'Proceed' WHERE MODULE_INSTANCE_ID = :V_LAST_MODULE_INSTANCE_ID;
        CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Cancel');
        RETURN 'Cancel';
    END IF;

    IF (V_LAST_EXECUTION_STATUS_CODE <> 'Failed' AND V_LAST_NEXT_RUN_STATUS_CODE <> 'Rollback') THEN
        CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Proceed');
        RETURN 'Proceed';
    END IF;

    -- Rollback: remove the rows of the instances since the last good one from the target data object.
    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Rollback');

    IF (V_BATCH_ID = 0) THEN
        SELECT COALESCE(MAX(mi.MODULE_INSTANCE_ID), 0) INTO :V_LAST_GOOD_MODULE_INSTANCE_ID
        FROM <% database %>.OMD.MODULE_INSTANCE mi
        LEFT JOIN <% database %>.OMD.BATCH_INSTANCE bi ON mi.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID
        WHERE mi.MODULE_ID = :V_MODULE_ID AND COALESCE(bi.BATCH_ID, 0) = 0
          AND mi.EXECUTION_STATUS_CODE = 'Succeeded' AND mi.NEXT_RUN_STATUS_CODE = 'Proceed';
    ELSE
        SELECT COALESCE(MAX(mi.MODULE_INSTANCE_ID), 0) INTO :V_LAST_GOOD_MODULE_INSTANCE_ID
        FROM <% database %>.OMD.MODULE_INSTANCE mi
        JOIN <% database %>.OMD.BATCH_INSTANCE bi ON mi.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID
        WHERE mi.MODULE_ID = :V_MODULE_ID AND bi.BATCH_ID = :V_BATCH_ID
          AND bi.EXECUTION_STATUS_CODE = 'Succeeded';
    END IF;

    SELECT LISTAGG(mi.MODULE_INSTANCE_ID, ',') WITHIN GROUP (ORDER BY mi.MODULE_INSTANCE_ID) INTO :V_ROLLBACK_LIST
    FROM <% database %>.OMD.MODULE_INSTANCE mi
    LEFT JOIN <% database %>.OMD.BATCH_INSTANCE bi ON mi.BATCH_INSTANCE_ID = bi.BATCH_INSTANCE_ID
    WHERE mi.MODULE_ID = :V_MODULE_ID
      AND COALESCE(bi.BATCH_ID, 0) = :V_BATCH_ID
      AND mi.MODULE_INSTANCE_ID > :V_LAST_GOOD_MODULE_INSTANCE_ID
      AND mi.MODULE_INSTANCE_ID <> :P_MODULE_INSTANCE_ID
      AND mi.EXECUTION_STATUS_CODE NOT IN ('Executing', 'Aborted');

    IF (V_ROLLBACK_LIST IS NOT NULL AND V_ROLLBACK_LIST <> '') THEN
        SELECT MAX(DATA_OBJECT_TARGET) INTO :V_DATA_OBJECT_TARGET FROM <% database %>.OMD.MODULE WHERE MODULE_ID = :V_MODULE_ID;
        V_COLUMN_NAME := COALESCE(NULLIF(<% database %>.OMD_METADATA.GET_SETTING('MODULE_INSTANCE_ID_COLUMN_NAME'), ''), 'MODULE_INSTANCE_ID');

        IF (V_DATA_OBJECT_TARGET IS NOT NULL AND V_DATA_OBJECT_TARGET <> 'N/A') THEN
            V_STATEMENT := 'DELETE FROM ' || V_DATA_OBJECT_TARGET || ' WHERE ' || V_COLUMN_NAME || ' IN (' || V_ROLLBACK_LIST || ')';
            EXECUTE IMMEDIATE :V_STATEMENT;
            V_MESSAGE := 'Rollback of Module Instance(s) ' || V_ROLLBACK_LIST || ': ' || V_STATEMENT;
        ELSE
            V_MESSAGE := 'Rollback of Module Instance(s) ' || V_ROLLBACK_LIST || ': the Module has no target data object, only the load windows are removed.';
        END IF;

        -- The load windows of the rolled back instances no longer count.
        V_STATEMENT := 'DELETE FROM <% database %>.OMD.SOURCE_CONTROL WHERE MODULE_INSTANCE_ID IN (' || V_ROLLBACK_LIST || ')';
        EXECUTE IMMEDIATE :V_STATEMENT;

        -- The rolled back instances keep their execution status; their next run status is settled.
        V_STATEMENT := 'UPDATE <% database %>.OMD.MODULE_INSTANCE SET NEXT_RUN_STATUS_CODE = ''Proceed'' WHERE MODULE_INSTANCE_ID IN (' || V_ROLLBACK_LIST || ')';
        EXECUTE IMMEDIATE :V_STATEMENT;

        IF (<% database %>.OMD_METADATA.GET_SETTING_FLAG('LOG_TO_EVENT_LOG') = 'Y') THEN
            CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, :P_MODULE_INSTANCE_ID);
        END IF;
    END IF;

    CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Proceed');
    RETURN 'Proceed';
EXCEPTION
    WHEN OTHER THEN
        V_MESSAGE := 'Error in MODULE_EVALUATION: ' || SQLERRM;
        CALL <% database %>.OMD.INSERT_INTO_EVENT_LOG(:V_MESSAGE, :P_MODULE_INSTANCE_ID, 0, 1, TO_VARCHAR(:SQLCODE));
        CALL <% database %>.OMD.UPDATE_MODULE_INSTANCE(:P_MODULE_INSTANCE_ID, 'Failure');
        RETURN 'Abort';
END;
$$;
