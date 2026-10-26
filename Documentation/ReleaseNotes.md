# Release Notes

## Release 2.2.0

This release adds support for external orchestration: an orchestrator outside the repository database (for example a Microsoft Fabric Data Factory pipeline) opens and closes the instances of a whole Batch with two calls, and runs the code on the target engine itself. The repository database schema is unchanged, so no migration is needed.

Changes:

* New procedure `omd.CreateBatchModuleInstances`: creates and evaluates a Batch Instance and the Module Instances of all active Modules in the Batch, in sequence, and returns one row per Module with the Module Instance Id, the executable, the previous load window end value, the Internal Processing Status Code, the rollback statement to run on the target engine (when applicable) and, for configurable Module Types, a consistency timestamp. Nothing is executed.
* New procedure `omd.EndBatchModuleInstances`: closes the Module Instances of a Batch Instance from a JSON array of results reported by the orchestrator (event, load window, row counts, failure detail), fails Module Instances that were left executing without a result, and closes the Batch Instance with `Success` or `Failure`.
* New view `omd_processing.vw_BATCH_HIERARCHY`: parent and child Batch codes with their sequence, for orchestrators that run the child Batches of a parent Batch.
* `omd.ModuleEvaluation` has a new parameter `@ExecuteRollbackIndicator` (default `Y`). With `N` the rollback statement for the target data object is not executed but returned in the new output parameter `@RollbackStatement`, for execution on the engine that holds the data. The Source Control rollback still happens in the repository.
* `omd.GetConsistencyTimestamp` has a new parameter `@SourceDataLookupIndicator` (default `Y`). With `N` the procedure uses repository information only and does not query the source tables, which allows it to run when the data lives in another database or engine.
* New `fabric` folder with the standard Microsoft Fabric pipelines `DIRECT Run Project`, `DIRECT Run Batch` and `DIRECT Run Module`, a Variable Library definition, deployment scripts and a README. The pipelines use the procedures above against a DIRECT repository in a SQL database in Fabric and run the Module executables on a Fabric Warehouse.
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
  