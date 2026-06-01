-- ============================================================
-- File 5 of 6: 04_kpi_marts.sql
-- Purpose:    Build the GOLD-layer aggregated tables that Power BI
--             plugs into directly. Each mart answers one dashboard
--             question with pre-computed numbers.
-- Pattern:    Materialize as tables (not views) so Power BI queries
--             are sub-second even on large datasets.
-- ============================================================

DROP TABLE IF EXISTS mart_kpi_daily              CASCADE;
DROP TABLE IF EXISTS mart_carrier_performance    CASCADE;
DROP TABLE IF EXISTS mart_warehouse_performance  CASCADE;
DROP TABLE IF EXISTS mart_lane_performance       CASCADE;


-- ------------------------------------------------------------
-- MART 1: Daily KPI trend
-- Grain: one row per calendar day.
-- Used for: Page 1 headline cards + trend line charts.
-- ------------------------------------------------------------
CREATE TABLE mart_kpi_daily AS
SELECT
    DATE(order_ts)                                              AS order_date,
    COUNT(*)                                                    AS shipments,
    SUM(on_time_flag)                                           AS on_time_shipments,
    ROUND(AVG(on_time_flag)::numeric * 100, 2)                  AS on_time_pct,
    ROUND(AVG(transit_days)::numeric, 2)                        AS avg_transit_days,
    ROUND(AVG(warehouse_dwell_hours)::numeric, 2)               AS avg_dwell_hours,
    ROUND(SUM(shipping_cost)::numeric, 2)                       AS daily_shipping_cost,
    ROUND(SUM(late_penalty_cost)::numeric, 2)                   AS daily_penalty_cost,
    ROUND(SUM(total_shipment_cost)::numeric, 2)                 AS daily_total_cost,
    SUM(units)                                                  AS units_shipped,
    ROUND(SUM(order_value)::numeric, 2)                         AS revenue_shipped
FROM order_lifecycle
GROUP BY DATE(order_ts);

CREATE INDEX idx_mart_kpi_daily_date ON mart_kpi_daily(order_date);


-- ------------------------------------------------------------
-- MART 2: Carrier performance scorecard
-- Grain: one row per carrier.
-- Used for: Page 3 carrier comparison.
-- ------------------------------------------------------------
CREATE TABLE mart_carrier_performance AS
SELECT
    carrier_id,
    carrier_name,
    service_level,
    sla_days,
    COUNT(*)                                                    AS shipments,
    SUM(on_time_flag)                                           AS on_time_shipments,
    ROUND(AVG(on_time_flag)::numeric * 100, 2)                  AS on_time_pct,
    ROUND(AVG(transit_days)::numeric, 2)                        AS avg_transit_days,
    ROUND(AVG(sla_breach_days)::numeric, 2)                     AS avg_breach_days,
    ROUND(AVG(shipping_cost)::numeric, 2)                       AS avg_shipping_cost,
    ROUND(SUM(shipping_cost)::numeric, 0)                       AS total_shipping_spend,
    ROUND(SUM(late_penalty_cost)::numeric, 0)                   AS total_penalty_paid,
    ROUND(
      SUM(late_penalty_cost)::numeric
      / NULLIF(SUM(shipping_cost), 0) * 100, 2
    )                                                           AS penalty_pct_of_spend
FROM order_lifecycle
WHERE carrier_id IS NOT NULL
GROUP BY carrier_id, carrier_name, service_level, sla_days;


-- ------------------------------------------------------------
-- MART 3: Warehouse performance scorecard
-- Grain: one row per warehouse.
-- Used for: surfacing the Atlanta-bottleneck finding.
-- ------------------------------------------------------------
CREATE TABLE mart_warehouse_performance AS
SELECT
    warehouse_id,
    warehouse_name,
    origin_region                                               AS region,
    COUNT(*)                                                    AS shipments,
    ROUND(AVG(warehouse_dwell_hours)::numeric, 2)               AS avg_dwell_hours,
    ROUND(AVG(transit_days)::numeric, 2)                        AS avg_transit_days,
    ROUND(AVG(total_fulfilment_days)::numeric, 2)               AS avg_total_fulfilment_days,
    ROUND(AVG(on_time_flag)::numeric * 100, 2)                  AS on_time_pct,
    ROUND(SUM(late_penalty_cost)::numeric, 0)                   AS total_penalty_paid
FROM order_lifecycle
GROUP BY warehouse_id, warehouse_name, origin_region;


-- ------------------------------------------------------------
-- MART 4: Lane performance scorecard
-- Grain: one row per origin warehouse -> destination region.
-- Used for: lane-level drill-down on Page 3.
-- ------------------------------------------------------------
CREATE TABLE mart_lane_performance AS
SELECT
    lane_id,
    warehouse_id                                                AS origin_warehouse_id,
    warehouse_name                                              AS origin_warehouse,
    dest_region,
    baseline_transit_days,
    COUNT(*)                                                    AS shipments,
    ROUND(AVG(transit_days)::numeric, 2)                        AS avg_transit_days,
    ROUND(AVG(transit_days - baseline_transit_days)::numeric, 2) AS transit_drag_days,
    ROUND(AVG(on_time_flag)::numeric * 100, 2)                  AS on_time_pct,
    ROUND(SUM(late_penalty_cost)::numeric, 0)                   AS total_penalty_paid
FROM order_lifecycle
GROUP BY lane_id, warehouse_id, warehouse_name, dest_region, baseline_transit_days;


-- ------------------------------------------------------------
-- Verify: row counts for each mart
-- ------------------------------------------------------------
SELECT 'mart_kpi_daily'              AS mart, COUNT(*) AS rows FROM mart_kpi_daily
UNION ALL SELECT 'mart_carrier_performance',   COUNT(*) FROM mart_carrier_performance
UNION ALL SELECT 'mart_warehouse_performance', COUNT(*) FROM mart_warehouse_performance
UNION ALL SELECT 'mart_lane_performance',      COUNT(*) FROM mart_lane_performance
ORDER BY mart;
