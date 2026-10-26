# Release Notes

## Release 2.2.0

This release adds support for external orchestration: an orchestrator outside the repository database (for example a Microsoft Fabric Data Factory pipeline) opens and closes the instances of a whole Batch with two calls, and runs the code on the target engine itself. The repository database schema is unchanged, so no migration is needed.

Changes:

* New procedure `omd.CreateBatchModuleInstances`: creates and evaluates a Batch Instance and the Module Instances of all active Modules in the Batch, in sequence, and returns one row per Module with the Module Instance Id, the executable, the previous load window end value, the Internal Processing Status Code, the rollback statement to run on the target engine (when applicable) and, for configurable Module Types, a consistency timestamp. Nothing is executed. With `@ReturnResultSet = 'N'` the rows are returned as a JSON array in the output parameter `@ResultJson` instead of a result set. With `@IncludeChildBatches = 'Y'` the active child Batches are opened as well, recursively and in sequence after the Modules of the Batch itself (the order of `omd.RunBatch`); the output parameter `@BatchInstancesJson` lists the Batch Instances that were created. A Batch that cannot be fully opened fails the Module and Batch Instances it did open.
* New procedure `omd.EndBatchModuleInstances` (with `@IncludeChildBatches = 'Y'` it also closes the child Batch Instances from the deepest level up; a failed Module or child Batch Instance fails its Batch Instance, the output parameter `@FailedBatchCount` reports the failed child Batch Instances): closes the Module Instances of a Batch Instance from a JSON array of results reported by the orchestrator (event, load window, row counts, failure detail), fails Module Instances that were left executing without a result, and closes the Batch Instance with `Success` or `Failure`.
* New view `omd_processing.vw_BATCH_HIERARCHY`: parent and child Batch codes with their sequence, for orchestrators that run the child Batches of a parent Batch.
* `omd.ModuleEvaluation` has a new parameter `@ExecuteRollbackIndicator` (default `Y`). With `N` the rollback statement for the target data object is not executed but returned in the new output parameter `@RollbackStatement`, for execution on the engine that holds the data. The Source Control rollback still happens in the repository.
* `omd.GetConsistencyTimestamp` has a new parameter `@SourceDataLookupIndicator` (default `Y`). With `N` the procedure uses repository information only and does not query the source tables, which allows it to run when the data lives in another database or engine.
* New `fabric` folder with the standard Microsoft Fabric pipelines `DIRECT Run Batch` (a Batch with all its child Batches, in three activity runs) and `DIRECT Run Module`, a Variable Library definition, deployment scripts and a README. The pipelines use the procedures above against a DIRECT repository in a SQL database in Fabric and run the Module executables on a Fabric Warehouse.
* New `snowflake` folder with the Snowflake edition of the framework: the repository schemas, tables, views and procedures in Snowflake Scripting (`Direct_Snowflake.sql`, built from the files in `snowflake/sql`), Batch and Module registration, instance creation and evaluation, `RUN_MODULE` and `RUN_BATCH` for running registered executables in sequence with the child Batches, a serverless Task per Batch as queue, deployment and run scripts, a regression test suite and a README.
* Fixed: `omd.BatchEvaluation` built an invalid `IN ((1,2))` list in the partial rollback branch, which failed every Batch run after two failed Batch Instances.
* Fixed: the post-deployment seed of `omd.MODULE_INSTANCE` merged on `BATCH_INSTANCE_ID` instead of `MODULE_INSTANCE_ID`, which overwrote every Module Instance that ran outside a Batch on each deployment.
* Fixed: `omd.ModuleEvaluation` quoted an already quoted `DATA_OBJECT_TARGET` in the rollback statement.
* The framework version is 2.2.0 (`DIRECT_VERSION` in `omd_metadata.FRAMEWORK_METADATA`).

## Release 2.1.0

Changes:

* `BATCH_CODE`, `MODULE_CODE` and `PARAMETER_CODE` has changed data type to `NVARCHAR(500)` to allow indexing.
* SOURCE_CONTROL code has been aligned with the agnostic string format  
  Values are stored as `NVARCHAR(100)` in the table
* Several tables have had their column names updated to adhere to the naming convention
  * tba is called tba
  * and so on
* stored procedures `omd.CreateBatchInstance` and `omd.CreateModuleInstance` now returns the start time inserted into the database as well as the instance id. This can be used in external orchestration scenarios to align the data processing with the batch start timestamp
* `omd.FRAMEWORK_METADATA` column `ACTIVE_INDICATOR` is non-nullable, migration is defaulting any existing null values to `N`
* `omd.FRAMEWORK_METADATA` has some extra helpers, used in the stored procedures:  
  * tba
  