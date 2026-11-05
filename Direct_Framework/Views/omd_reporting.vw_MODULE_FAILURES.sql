/**
 * @view [omd_reporting].[vw_MODULE_FAILURES]
 * @description Aggregates module failures in the last 3 months with average execution minutes.
 *
 * @package DIRECT Framework
 * @version 2.1.0
 * @see https://github.com/data-solution-automation-engine/DIRECT
 *
 * @resultset Columns:
 *   - MODULE_CODE: Module code.
 *   - MODULE_DESCRIPTION: Description.
 *   - AVG_EXEC_MIN: Average execution time in minutes.
 *   - COUNT_ERRORS: Number of failed runs in the window.
 *
 * @lineage
 * - reads:
 *     table [omd].[MODULE]
 *     table [omd].[MODULE_INSTANCE]
 *
 * @example
 * SELECT TOP 100 * FROM [omd_reporting].[vw_MODULE_FAILURES];
 */
CREATE VIEW [omd_reporting].[vw_MODULE_FAILURES] AS

select     --TOP 40
           m.MODULE_CODE
          ,m.MODULE_DESCRIPTION
          ,AVG(datediff(MINUTE,mi.START_TIMESTAMP,mi.END_TIMESTAMP)) as AVG_EXEC_MIN
          ,SUM(case when mi.EXECUTION_STATUS_CODE = 'Failed' then 1 else 0 end) as COUNT_ERRORS
from      omd.MODULE m
JOIN      omd.MODULE_INSTANCE mi
ON            m.MODULE_ID = mi.MODULE_ID
WHERE         mi.START_TIMESTAMP > dateadd(MONTH,-3,SYSUTCDATETIME())
group by      m.MODULE_CODE, m.MODULE_DESCRIPTION
HAVING        SUM(case when mi.EXECUTION_STATUS_CODE = 'Failed' then 1 else 0 end) >0
