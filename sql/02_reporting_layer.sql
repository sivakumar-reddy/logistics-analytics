-- ============================================================
-- File 3 of 6: 02_reporting_layer.sql
-- Purpose:    Create the order_lifecycle view (silver layer).
-- Pattern:    Pivot row-based stage_events into one row per shipment,
--             joined with order + carrier + lane + warehouse dimensions,
--             with derived journey-time metrics pre-computed.
-- ============================================================

DROP VIEW IF EXISTS order_lifecycle CASCADE;

CREATE VIEW order_lifecycle AS
WITH

-- 1. Pivot stage_events: one row per shipment, one column per stage.
--    Uses conditional aggregation (MAX with FILTER) which is the
--    standard SQL trick for turning long rows into wide columns.
event_pivot AS (
    SELECT
        shipment_id,
        MAX(event_ts) FILTER (WHERE stage = 'ORDERED')    AS ordered_ts,
        MAX(event_ts) FILTER (WHERE stage = 'PICKED')     AS picked_ts,
        MAX(event_ts) FILTER (WHERE stage = 'PACKED')     AS packed_ts,
        MAX(event_ts) FILTER (WHERE stage = 'SHIPPED')    AS shipped_ts,
        MAX(event_ts) FILTER (WHERE stage = 'IN_TRANSIT') AS in_transit_ts,
        MAX(event_ts) FILTER (WHERE stage = 'DELIVERED')  AS delivered_ts,
        COUNT(*)                                           AS event_count
    FROM stage_events
    WHERE shipment_id IN (SELECT shipment_id FROM shipments)  -- drop orphans
    GROUP BY shipment_id
)

-- 2. Final SELECT joins the pivoted events with all reference data
--    and computes the derived metrics analysts actually want.
SELECT
    s.shipment_id,
    s.order_id,
    o.order_ts,
    o.product_category,
    o.order_value,
    o.units,

    -- Warehouse
    o.warehouse_id,
    w.warehouse_name,
    w.region            AS origin_region,

    -- Carrier
    s.carrier_id,
    c.carrier_name,
    c.service_level,
    c.sla_days,

    -- Lane
    s.lane_id,
    l.dest_region,
    l.baseline_transit_days,

    -- Stage timestamps (pivoted)
    ep.ordered_ts,
    ep.picked_ts,
    ep.packed_ts,
    ep.shipped_ts,
    ep.in_transit_ts,
    ep.delivered_ts,

    -- Promised vs actual
    s.promised_delivery_ts,
    s.actual_delivery_ts,
    s.on_time_flag,
    s.shipping_cost,
    s.late_penalty_cost,

    -- ====== DERIVED METRICS (the analytical payoff) ======

    -- Warehouse dwell: hours from ordered to shipped (handling time)
    EXTRACT(EPOCH FROM (ep.shipped_ts - ep.ordered_ts)) / 3600.0
        AS warehouse_dwell_hours,

    -- Pure transit: days from shipped to delivered
    EXTRACT(EPOCH FROM (ep.delivered_ts - ep.shipped_ts)) / 86400.0
        AS transit_days,

    -- Total fulfilment time: days from ordered to delivered
    EXTRACT(EPOCH FROM (ep.delivered_ts - ep.ordered_ts)) / 86400.0
        AS total_fulfilment_days,

    -- SLA breach: positive = late by N days, negative = early by N days
    EXTRACT(EPOCH FROM (s.actual_delivery_ts - s.promised_delivery_ts)) / 86400.0
        AS sla_breach_days,

    -- Total landed cost per shipment (cost + any late penalty)
    s.shipping_cost + s.late_penalty_cost AS total_shipment_cost

FROM shipments s
JOIN orders        o  ON s.order_id      = o.order_id
JOIN event_pivot   ep ON s.shipment_id   = ep.shipment_id
JOIN lanes         l  ON s.lane_id       = l.lane_id
JOIN warehouses    w  ON o.warehouse_id  = w.warehouse_id
LEFT JOIN carriers c  ON s.carrier_id    = c.carrier_id  -- LEFT JOIN: keep shipments with null carrier
-- Filter out impossible/seeded-bad rows so the silver layer stays clean
WHERE ep.event_count = 6                          -- only complete journeys
  AND ep.delivered_ts > ep.shipped_ts             -- no out-of-order
  AND s.actual_delivery_ts > o.order_ts;          -- no negative transit


-- ============================================================
-- Verify the view: row count + a quick sanity check
-- Expected: ~11,984 clean shipments (16 seeded-bad rows excluded)
-- ============================================================
SELECT
    COUNT(*)                                            AS total_shipments_clean,
    ROUND(AVG(on_time_flag)::numeric * 100, 1)          AS on_time_pct,
    ROUND(AVG(transit_days)::numeric, 2)                AS avg_transit_days,
    ROUND(AVG(warehouse_dwell_hours)::numeric, 1)       AS avg_warehouse_dwell_hours,
    ROUND(SUM(total_shipment_cost)::numeric, 0)         AS total_logistics_spend,
    ROUND(SUM(late_penalty_cost)::numeric, 0)           AS total_late_penalties
FROM order_lifecycle;
