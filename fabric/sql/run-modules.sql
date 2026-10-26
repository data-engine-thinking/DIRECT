-- DIRECT Run Batch / Run Module, activity 'Run Modules' (target engine, Fabric Warehouse).
-- Runs the Modules in @Modules (JSON array with the rows of omd.CreateBatchModuleInstances) in order.
-- Per Module: rollback statement (if any), load window end from the source data object, the executable through
-- sp_executesql with the parameters @ModuleInstanceId, @StartValue, @EndValue and @ConsistencyDateTime, and the
-- target row count before and after. One result row per Module, in the shape omd.EndBatchModuleInstances expects.
-- Parameters: @Modules (string, JSON), @LoadWindowAttributeName (string).
CREATE TABLE #modules
(
   [SEQ]                            INT
  ,[MODULE_INSTANCE_ID]             BIGINT
  ,[MODULE_CODE]                    VARCHAR(500)
  ,[EXECUTABLE]                     VARCHAR(8000)
  ,[DATA_OBJECT_SOURCE]             VARCHAR(1000)
  ,[DATA_OBJECT_TARGET]             VARCHAR(1000)
  ,[PREVIOUS_END_VALUE]             VARCHAR(100)
  ,[INTERNAL_PROCESSING_STATUS_CODE] VARCHAR(100)
  ,[ROLLBACK_STATEMENT]             VARCHAR(8000)
  ,[CONSISTENCY_DATETIME]           VARCHAR(100)
);

INSERT INTO #modules
SELECT
   ROW_NUMBER() OVER (ORDER BY [SEQUENCE], [MODULE_CODE])
  ,[MODULE_INSTANCE_ID], [MODULE_CODE], [EXECUTABLE], [DATA_OBJECT_SOURCE], [DATA_OBJECT_TARGET], [PREVIOUS_END_VALUE]
  ,[INTERNAL_PROCESSING_STATUS_CODE], [ROLLBACK_STATEMENT], [CONSISTENCY_DATETIME]
FROM OPENJSON(@Modules)
WITH
(
   [SEQUENCE]                       INT
  ,[MODULE_INSTANCE_ID]             BIGINT
  ,[MODULE_CODE]                    VARCHAR(500)
  ,[EXECUTABLE]                     VARCHAR(8000)
  ,[DATA_OBJECT_SOURCE]             VARCHAR(1000)
  ,[DATA_OBJECT_TARGET]             VARCHAR(1000)
  ,[PREVIOUS_END_VALUE]             VARCHAR(100)
  ,[INTERNAL_PROCESSING_STATUS_CODE] VARCHAR(100)
  ,[ROLLBACK_STATEMENT]             VARCHAR(8000)
  ,[CONSISTENCY_DATETIME]           VARCHAR(100)
)
WHERE [INTERNAL_PROCESSING_STATUS_CODE] = 'Proceed';

CREATE TABLE #results
(
   [Seq]              INT
  ,[ModuleInstanceId] BIGINT
  ,[ModuleCode]       VARCHAR(500)
  ,[EventCode]        VARCHAR(100)
  ,[StartValue]       VARCHAR(100)
  ,[EndValue]         VARCHAR(100)
  ,[RowCountInsert]   BIGINT
  ,[EventDetail]      VARCHAR(4000)
  ,[DurationMs]       INT
);

DECLARE @i INT = 0;
DECLARE @n INT = (SELECT COUNT(*) FROM #modules);
DECLARE @WindowColumn VARCHAR(128) = COALESCE(NULLIF(TRIM(@LoadWindowAttributeName), ''), 'INSCRIPTION_TIMESTAMP');
DECLARE @ParameterDefinition NVARCHAR(500) = N'@ModuleInstanceId BIGINT, @StartValue VARCHAR(100), @EndValue VARCHAR(100), @ConsistencyDateTime VARCHAR(100)';

DECLARE @ModuleInstanceId BIGINT, @ModuleCode VARCHAR(500), @Executable NVARCHAR(MAX), @Source VARCHAR(1000), @Target VARCHAR(1000);
DECLARE @StartValue VARCHAR(100), @EndValue VARCHAR(100), @Rollback NVARCHAR(MAX), @ConsistencyDateTime VARCHAR(100);
DECLARE @Sql NVARCHAR(MAX), @Before BIGINT, @After BIGINT, @T0 DATETIME2(6), @Step VARCHAR(50);

WHILE @i < @n
BEGIN
  SET @i = @i + 1;

  SELECT
     @ModuleInstanceId = [MODULE_INSTANCE_ID], @ModuleCode = [MODULE_CODE], @Executable = [EXECUTABLE]
    ,@Source = [DATA_OBJECT_SOURCE], @Target = [DATA_OBJECT_TARGET], @StartValue = [PREVIOUS_END_VALUE]
    ,@Rollback = [ROLLBACK_STATEMENT], @ConsistencyDateTime = [CONSISTENCY_DATETIME]
  FROM #modules
  WHERE [SEQ] = @i;

  SET @T0 = SYSDATETIME();
  SET @EndValue = NULL;
  SET @Before = NULL;
  SET @After = NULL;
  SET @Step = 'rollback';

  BEGIN TRY
    -- Rollback of earlier failed instances, decided by the Module evaluation in the repository
    IF @Rollback IS NOT NULL AND TRIM(@Rollback) <> ''
    BEGIN
      EXEC sp_executesql @Rollback;
    END;

    -- Load window end: the latest load window attribute value in the source data object.
    -- When the source has no such attribute (for example an operational source), the current time is used.
    SET @Step = 'load window';
    IF @Source IS NOT NULL AND TRIM(@Source) <> ''
    BEGIN
      BEGIN TRY
        SET @Sql = N'SELECT @e = CONVERT(VARCHAR(27), MAX(' + QUOTENAME(@WindowColumn) + N'), 121) FROM ' + @Source;
        EXEC sp_executesql @Sql, N'@e VARCHAR(27) OUTPUT', @e = @EndValue OUTPUT;
      END TRY
      BEGIN CATCH
        SET @EndValue = NULL;
      END CATCH;
    END;
    IF @EndValue IS NULL SET @EndValue = CONVERT(VARCHAR(27), SYSDATETIME(), 121);

    -- Target row count before
    SET @Step = 'row count';
    IF @Target IS NOT NULL AND TRIM(@Target) <> ''
    BEGIN
      BEGIN TRY
        SET @Sql = N'SELECT @c = COUNT_BIG(*) FROM ' + @Target;
        EXEC sp_executesql @Sql, N'@c BIGINT OUTPUT', @c = @Before OUTPUT;
      END TRY
      BEGIN CATCH
        SET @Before = NULL;
      END CATCH;
    END;

    -- The executable
    SET @Step = 'executable';
    EXEC sp_executesql @Executable, @ParameterDefinition
      ,@ModuleInstanceId = @ModuleInstanceId, @StartValue = @StartValue, @EndValue = @EndValue, @ConsistencyDateTime = @ConsistencyDateTime;

    -- Target row count after
    SET @Step = 'row count';
    IF @Before IS NOT NULL
    BEGIN
      BEGIN TRY
        SET @Sql = N'SELECT @c = COUNT_BIG(*) FROM ' + @Target;
        EXEC sp_executesql @Sql, N'@c BIGINT OUTPUT', @c = @After OUTPUT;
      END TRY
      BEGIN CATCH
        SET @After = NULL;
      END CATCH;
    END;

    INSERT INTO #results VALUES (@i, @ModuleInstanceId, @ModuleCode, 'Success', @StartValue, @EndValue, @After - @Before, NULL, DATEDIFF(MILLISECOND, @T0, SYSDATETIME()));
  END TRY
  BEGIN CATCH
    INSERT INTO #results VALUES (@i, @ModuleInstanceId, @ModuleCode, 'Failure', @StartValue, @EndValue, NULL,
      LEFT('Error in ' + @Step + ' (' + CONVERT(VARCHAR(20), ERROR_NUMBER()) + '): ' + ERROR_MESSAGE(), 4000), DATEDIFF(MILLISECOND, @T0, SYSDATETIME()));
  END CATCH;
END;

SELECT [Seq], [ModuleInstanceId], [ModuleCode], [EventCode], [StartValue], [EndValue], [RowCountInsert], [EventDetail], [DurationMs]
FROM #results
ORDER BY [Seq];
