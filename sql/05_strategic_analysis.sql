-- ============================================================
-- File 6 of 6: 05_strategic_analysis.sql
-- Purpose:    Curated analysis queries whose results become the
--             README's "Key Findings" section.
-- Each query stands alone and answers one stakeholder question.
-- ============================================================


-- ============================================================
-- FINDING 1: Carrier scorecard
-- Q: Which carrier delivers value, and which is a money pit?
-- ============================================================
SELECT carrier_name,
       service_level,
       shipments,
       on_time_pct                                          AS otd_pct,
       avg_breach_days                                      AS avg_days_late,
       total_penalty_paid                                   AS penalty_usd,
       penalty_pct_of_spend                                 AS penalty_pct
FROM   mart_carrier_performance
ORDER  BY on_time_pct DESC;


-- ============================================================
-- FINDING 2: Warehouse bottleneck (the operations finding)
-- Q: Which warehouse is dragging total fulfilment time?
-- ============================================================
SELECT warehouse_name,
       region,
       shipments,
       avg_dwell_hours,
       avg_transit_days,
       avg_total_fulfilment_days,
       on_time_pct,
       total_penalty_paid
FROM   mart_warehouse_performance
ORDER  BY avg_dwell_hours DESC;


-- ============================================================
-- FINDING 3: Service-level paradox
-- Q: Does paying for premium service actually buy reliability?
-- Compare avg cost-per-shipment vs OTD by service level.
-- ============================================================
SELECT service_level,
       COUNT(*)                                             AS carriers,
       SUM(shipments)                                       AS total_shipments,
       ROUND(AVG(on_time_pct)::numeric, 2)                  AS avg_otd_pct,
       ROUND(AVG(avg_shipping_cost)::numeric, 2)            AS avg_cost_per_shipment,
       SUM(total_penalty_paid)                              AS total_penalty_paid
FROM   mart_carrier_performance
GROUP  BY service_level
ORDER  BY avg_otd_pct DESC;


-- ============================================================
-- FINDING 4: Lane risk concentration (top 5 worst)
-- Q: Are late penalties spread evenly across lanes, or concentrated?
-- Returns the top 5 worst lanes by penalty dollars.
-- ============================================================
SELECT origin_warehouse,
       dest_region,
       shipments,
       avg_transit_days,
       transit_drag_days       AS days_over_baseline,
       on_time_pct,
       total_penalty_paid      AS penalty_usd,
       ROUND(
         total_penalty_paid::numeric
         / NULLIF(SUM(total_penalty_paid) OVER (), 0) * 100,
         2
       )                       AS pct_of_total_penalty
FROM   mart_lane_performance
ORDER  BY total_penalty_paid DESC
LIMIT  5;


-- ============================================================
-- FINDING 4b: Pareto summary  (top 20% of lanes = X% of penalties?)
-- ============================================================
WITH ranked AS (
    SELECT  total_penalty_paid,
            NTILE(5) OVER (ORDER BY total_penalty_paid DESC) AS quintile
    FROM    mart_lane_performance
)
SELECT  CASE WHEN quintile = 1 THEN 'Top 20% of lanes (worst)'
             ELSE 'Other 80% of lanes' END                          AS lane_group,
        COUNT(*)                                                    AS lane_count,
        SUM(total_penalty_paid)                                     AS penalty_usd,
        ROUND(
          SUM(total_penalty_paid)::numeric
          / NULLIF(SUM(SUM(total_penalty_paid)) OVER (), 0) * 100, 1
        )                                                           AS pct_of_total
FROM    ranked
GROUP   BY CASE WHEN quintile = 1 THEN 'Top 20% of lanes (worst)'
                ELSE 'Other 80% of lanes' END
ORDER   BY penalty_usd DESC;


-- ============================================================
-- FINDING 5: Temporal pattern - monthly OTD trend
-- Q: Is on-time performance stable, improving, or worsening?
-- ============================================================
SELECT  TO_CHAR(DATE_TRUNC('month', order_date), 'YYYY-MM')  AS year_month,
        SUM(shipments)                                       AS shipments,
        ROUND(
          SUM(on_time_shipments)::numeric
          / NULLIF(SUM(shipments), 0) * 100, 2
        )                                                    AS otd_pct,
        ROUND(SUM(daily_penalty_cost)::numeric, 0)           AS monthly_penalty
FROM    mart_kpi_daily
GROUP   BY DATE_TRUNC('month', order_date)
ORDER   BY year_month;


-- ============================================================
-- FINDING 6: Headline business-impact number for the README
-- Q: What's the single dollar figure that anchors the story?
-- ============================================================
SELECT
    COUNT(*)                                             AS total_shipments,
    ROUND(AVG(on_time_flag)::numeric * 100, 1)           AS overall_otd_pct,
    ROUND(SUM(shipping_cost)::numeric, 0)                AS total_shipping_spend,
    ROUND(SUM(late_penalty_cost)::numeric, 0)            AS total_late_penalties,
    ROUND(
      SUM(late_penalty_cost)::numeric
      / NULLIF(SUM(shipping_cost), 0) * 100, 1
    )                                                     AS penalty_pct_of_spend,
    ROUND(
      SUM(late_penalty_cost)::numeric * 12.0
      / NULLIF(
          EXTRACT(EPOCH FROM (MAX(order_ts) - MIN(order_ts)))
          / 2629800.0,   -- seconds in an avg month
          0
        ),
      0
    )                                                     AS annualized_penalty_run_rate
FROM    order_lifecycle;
