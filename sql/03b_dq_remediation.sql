-- ============================================================
-- File 4a: 03b_dq_remediation.sql
-- Purpose:   Patch the 5 rows flagged by Test T6.
--            Root cause: the data-generator seeded "negative transit"
--            (delivered before ordered) but didn't update on_time_flag
--            to reflect the new delivery timestamp. These 5 rows had
--            on_time_flag values inconsistent with their dates.
-- Action:    Recompute on_time_flag from the actual date comparison.
--            This is what the flag SHOULD be by definition.
-- Note:      Run AFTER 03_data_quality_tests.sql discovers the issue.
-- ============================================================

-- Show what's about to change (always do this first in real work)
SELECT shipment_id,
       on_time_flag AS current_flag,
       CASE WHEN actual_delivery_ts <= promised_delivery_ts THEN 1 ELSE 0 END AS correct_flag,
       order_id, actual_delivery_ts, promised_delivery_ts
FROM   shipments
WHERE  (on_time_flag = 1 AND actual_delivery_ts >  promised_delivery_ts)
   OR  (on_time_flag = 0 AND actual_delivery_ts <= promised_delivery_ts);

-- Apply the fix: recompute on_time_flag from the dates
UPDATE shipments
SET    on_time_flag = CASE
                        WHEN actual_delivery_ts <= promised_delivery_ts THEN 1
                        ELSE 0
                      END
WHERE  (on_time_flag = 1 AND actual_delivery_ts >  promised_delivery_ts)
   OR  (on_time_flag = 0 AND actual_delivery_ts <= promised_delivery_ts);

-- Re-run Test T6 to confirm it now passes
SELECT 'T6' AS test_id,
       'on_time_flag matches actual_delivery_ts vs promised_delivery_ts' AS rule,
       (SELECT COUNT(*)
          FROM shipments
         WHERE (on_time_flag = 1 AND actual_delivery_ts >  promised_delivery_ts)
            OR (on_time_flag = 0 AND actual_delivery_ts <= promised_delivery_ts)) AS bad_rows,
       CASE
         WHEN (SELECT COUNT(*)
                 FROM shipments
                WHERE (on_time_flag = 1 AND actual_delivery_ts >  promised_delivery_ts)
                   OR (on_time_flag = 0 AND actual_delivery_ts <= promised_delivery_ts)) = 0
         THEN 'PASS'
         ELSE 'FAIL'
       END AS status;
