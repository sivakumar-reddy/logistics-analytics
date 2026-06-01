-- ============================================================
-- File 4 of 6: 03_data_quality_tests.sql
-- Purpose:    Automated data-quality test suite.
--             Each test returns PASS/FAIL + a count of bad rows.
-- Pattern:    Trust-but-verify. Run after every load.
-- ============================================================
-- The "expected_failures" column encodes the SEEDED failures
-- (so the test still PASSES when the framework catches what it should).
-- A failing test with bad_rows != expected indicates a real,
-- unexpected data-quality issue.
-- ============================================================

WITH tests AS (

    -- =====================================================
    -- TEST 1: Referential integrity - orphan stage events.
    -- Every stage_events.shipment_id should point to a real shipment.
    -- We SEEDED 8 orphans, so expected bad count = 8.
    -- =====================================================
    SELECT 'T1' AS test_id,
           'No orphan stage events (events without a parent shipment)' AS rule,
           (SELECT COUNT(*)
              FROM stage_events se
              LEFT JOIN shipments s ON se.shipment_id = s.shipment_id
             WHERE s.shipment_id IS NULL) AS bad_rows,
           8 AS expected_failures

    UNION ALL

    -- =====================================================
    -- TEST 2: Stage-order logic - DELIVERED must come AFTER SHIPPED.
    -- We SEEDED 10 out-of-order rows, so expected = 10.
    -- =====================================================
    SELECT 'T2',
           'No out-of-order stages (DELIVERED before SHIPPED)',
           (SELECT COUNT(DISTINCT se1.shipment_id)
              FROM stage_events se1
              JOIN stage_events se2
                ON se1.shipment_id = se2.shipment_id
             WHERE se1.stage = 'DELIVERED'
               AND se2.stage = 'SHIPPED'
               AND se1.event_ts < se2.event_ts),
           10

    UNION ALL

    -- =====================================================
    -- TEST 3: Physical impossibility - delivery before order.
    -- We SEEDED 6 negative-transit rows, so expected = 6.
    -- =====================================================
    SELECT 'T3',
           'No negative transit (actual_delivery_ts before order_ts)',
           (SELECT COUNT(*)
              FROM shipments s
              JOIN orders o ON s.order_id = o.order_id
             WHERE s.actual_delivery_ts < o.order_ts),
           6

    UNION ALL

    -- =====================================================
    -- TEST 4: Completeness - every shipment must have a carrier.
    -- We SEEDED 12 NULL-carrier rows, so expected = 12.
    -- =====================================================
    SELECT 'T4',
           'No shipments missing a carrier_id (NULL not allowed)',
           (SELECT COUNT(*) FROM shipments WHERE carrier_id IS NULL),
           12

    UNION ALL

    -- =====================================================
    -- TEST 5: Uniqueness - no duplicate orders in the orders table.
    -- The duplicates existed in the raw CSV (15 of them) but the
    -- load pipeline (DISTINCT ON) filtered them.
    -- =====================================================
    SELECT 'T5',
           'No duplicate order_ids in the orders table (PK enforced)',
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders),
           0

    UNION ALL

    -- =====================================================
    -- TEST 6: Logical consistency - on_time_flag must match dates.
    -- This test CAUGHT an unexpected inconsistency: 5 rows where
    -- the seeded negative-transit injection didn't update the flag.
    -- The 03b_dq_remediation.sql file patches these rows.
    -- =====================================================
    SELECT 'T6',
           'on_time_flag matches actual_delivery_ts vs promised_delivery_ts',
           (SELECT COUNT(*)
              FROM shipments
             WHERE (on_time_flag = 1 AND actual_delivery_ts >  promised_delivery_ts)
                OR (on_time_flag = 0 AND actual_delivery_ts <= promised_delivery_ts)),
           0

    UNION ALL

    -- =====================================================
    -- TEST 7: Business rule - late shipments should have a penalty.
    -- =====================================================
    SELECT 'T7',
           'Late shipments have a non-zero penalty cost',
           (SELECT COUNT(*)
              FROM shipments
             WHERE on_time_flag = 0 AND late_penalty_cost = 0),
           0
)

-- Final result: a PASS/FAIL report card for every rule.
SELECT
    test_id,
    rule,
    bad_rows,
    expected_failures,
    CASE
        WHEN bad_rows = expected_failures THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM tests
ORDER BY test_id;
