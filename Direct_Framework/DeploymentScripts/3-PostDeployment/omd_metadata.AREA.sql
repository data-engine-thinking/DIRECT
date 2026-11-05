/**
 * @postprocess omd_metadata.AREA.sql
 * @description
 *   DACPAC Post-Deployment Script, insert and update script for reference data
 *   This reference metadata table stores area codes and descriptions.
 *   This script is used to insert and update system reference data on
 *   deployment. Any bespoke area codes added manually to the target will be
 *   retained. To maintain a clean CI/CD process, consider using this or a
 *   similar script to manage all reference data for area codes.
 *
 * @package DIRECT Framework
 * @version 2.1.0
 * @see https://github.com/data-solution-automation-engine/DIRECT
 *
 * @lineage
 * - writes:
 *     table [omd_metadata].[AREA]
 */

BEGIN TRY
  BEGIN TRANSACTION
    SET NOCOUNT ON;

    -- temporary merge source table
    DECLARE @tblMerge TABLE(
      [AREA_CODE]             NVARCHAR (100)  NOT NULL PRIMARY KEY CLUSTERED,
      [LAYER_CODE]            NVARCHAR (100)  NOT NULL,
      [AREA_DESCRIPTION]      NVARCHAR (4000) NULL
    );

    -- populate temporary table with framework reference data
    INSERT INTO @tblMerge([AREA_CODE], [LAYER_CODE], [AREA_DESCRIPTION])
    VALUES
      (N'HELPER',   N'Presentation',  N'The Helper Area'),
      (N'INT',      N'Integration',   N'The Base Integration Area'),
      (N'INTPR',    N'Integration',   N'The Derived Integration Area'),
      (N'LDA',      N'Staging',       N'The Landing Area of the Staging Layer'),
      (N'LND',      N'Staging',       N'The Landing Area of the Staging Layer'),
      (N'MAINT',    N'Maintenance',   N'Internal Data Solution'),
      (N'PRES',     N'Presentation',  N'The Access Area'),
      (N'PSA',      N'Staging',       N'The Persistent Staging Area'),
      (N'STG',      N'Staging',       N'The Staging Area of the Staging Layer'),
      (N'SYNC',     N'Staging',
        CONCAT(N'Synchronization of the production History Area of the ',
        'Staging Layer for build and test')
      );

    -- add new or update existing reference data into the omd_metadata.AREA table
    MERGE [omd_metadata].[AREA] AS tgt
      USING @tblMerge AS src
          ON  tgt.[AREA_CODE] = src.[AREA_CODE]
      WHEN MATCHED THEN
          UPDATE
          SET      [LAYER_CODE] = src.[LAYER_CODE],
                   [AREA_DESCRIPTION] = src.[AREA_DESCRIPTION]
      WHEN NOT MATCHED THEN
          INSERT  ([AREA_CODE]
                  ,[LAYER_CODE]
                  ,[AREA_DESCRIPTION])
          VALUES  ([AREA_CODE]
                  ,[LAYER_CODE]
                  ,[AREA_DESCRIPTION]);

  -- commit or rollback based on transaction state
  IF XACT_STATE() = 1
  BEGIN
    -- file processing completed successfully
    COMMIT TRANSACTION;
  END
  ELSE
  BEGIN
    -- post-processing failed
    PRINT FORMATMESSAGE(CONCAT(
      'Post-deployment of file ''omd_metadata.AREA.sql'' failed: ',
      'Error during merge operation, rolling back transaction.'
    ));
    ROLLBACK TRANSACTION;
  END;
END TRY
BEGIN CATCH
  IF XACT_STATE() <> 0
  BEGIN
    ROLLBACK TRANSACTION;
  END;
  PRINT FORMATMESSAGE(
    CONCAT('Post-deployment of ''omd_metadata.AREA.sql'' failed.',
    ' Error %d, Severity %d, State %d: %s'),
    ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_MESSAGE()
  );
  THROW; -- Rethrow original error with full context
END CATCH

GO
