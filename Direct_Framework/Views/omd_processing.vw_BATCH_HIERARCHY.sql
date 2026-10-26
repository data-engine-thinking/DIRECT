/**
 * @view [omd_processing].[vw_BATCH_HIERARCHY]
 * @description
 *   The parent/child Batch relationships with their codes, in execution order.
 *   External orchestrators use this view to find the child Batches of a (project) Batch,
 *   so that each child can be run with the parent Batch Instance Id.
 *
 * @package DIRECT Framework
 * @version 2.2.0
 * @see https://github.com/data-engine-thinking/DIRECT
 *
 * @resultset Columns:
 *   - PARENT_BATCH_ID: The parent Batch identifier.
 *   - PARENT_BATCH_CODE: The parent Batch code.
 *   - BATCH_ID: The child Batch identifier.
 *   - BATCH_CODE: The child Batch code.
 *   - SEQUENCE: The position of the child Batch under the parent.
 *   - RELATIONSHIP_ACTIVE_INDICATOR: The Active Indicator of the hierarchy relationship.
 *   - BATCH_ACTIVE_INDICATOR: The Active Indicator of the child Batch.
 *   - FREQUENCY_CODE: The frequency of the child Batch.
 *
 * @lineage
 * - reads:
 *     table [omd].[BATCH]
 *     table [omd].[BATCH_HIERARCHY]
 *
 * @example
 * SELECT BATCH_CODE, [SEQUENCE]
 * FROM [omd_processing].[vw_BATCH_HIERARCHY]
 * WHERE PARENT_BATCH_CODE = N'b_PROJECT' AND RELATIONSHIP_ACTIVE_INDICATOR = 'Y' AND BATCH_ACTIVE_INDICATOR = 'Y'
 * ORDER BY [SEQUENCE], BATCH_CODE;
 */
CREATE VIEW [omd_processing].[vw_BATCH_HIERARCHY]
AS

SELECT
   parent_batch.BATCH_ID        AS PARENT_BATCH_ID
  ,parent_batch.BATCH_CODE      AS PARENT_BATCH_CODE
  ,child_batch.BATCH_ID         AS BATCH_ID
  ,child_batch.BATCH_CODE       AS BATCH_CODE
  ,bh.[SEQUENCE]                AS [SEQUENCE]
  ,bh.ACTIVE_INDICATOR          AS RELATIONSHIP_ACTIVE_INDICATOR
  ,child_batch.ACTIVE_INDICATOR AS BATCH_ACTIVE_INDICATOR
  ,child_batch.FREQUENCY_CODE   AS FREQUENCY_CODE
FROM [omd].[BATCH_HIERARCHY] bh
JOIN [omd].[BATCH] parent_batch ON bh.PARENT_BATCH_ID = parent_batch.BATCH_ID
JOIN [omd].[BATCH] child_batch  ON bh.BATCH_ID = child_batch.BATCH_ID;
