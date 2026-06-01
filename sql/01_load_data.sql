-- ============================================================
-- File 2 of 6: 01_load_data.sql
-- Purpose:    Load raw CSVs into the tables created by file 00.
-- Pattern:    Load dimensions first, facts second (FK order).
-- Note:       CSVs must be in C:/pgdata/ (a postgres-readable folder).
--             We use server-side COPY for speed; the C:/pgdata path
--             avoids the Windows user-profile permission issue that
--             prevents COPY from reading OneDrive/Documents folders.
-- ============================================================

-- Clean slate
TRUNCATE TABLE stage_events, shipments, orders, lanes, carriers, warehouses CASCADE;

-- Dimension tables (no FK dependencies)
COPY warehouses(warehouse_id, warehouse_name, region, state)
FROM 'C:/pgdata/warehouses.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY carriers(carrier_id, carrier_name, service_level, sla_days, base_cost)
FROM 'C:/pgdata/carriers.csv' WITH (FORMAT CSV, HEADER TRUE);

COPY lanes(lane_id, origin_warehouse_id, dest_region, baseline_transit_days)
FROM 'C:/pgdata/lanes.csv' WITH (FORMAT CSV, HEADER TRUE);

-- Orders: stage first (because of 15 seeded duplicate rows), then dedupe.
-- The PRIMARY KEY on orders.order_id would block the duplicates, so we
-- land them in a temp table with no constraints, then INSERT DISTINCT.
CREATE TEMP TABLE _stg_orders (LIKE orders INCLUDING DEFAULTS);

COPY _stg_orders(order_id, order_ts, warehouse_id, dest_region, product_category, order_value, units)
FROM 'C:/pgdata/orders.csv' WITH (FORMAT CSV, HEADER TRUE);

INSERT INTO orders
SELECT DISTINCT ON (order_id) *
FROM _stg_orders
ORDER BY order_id, order_ts;

DROP TABLE _stg_orders;

-- Shipments: 12 rows have NULL carrier_id (a seeded DQ issue).
-- This is permitted because shipments.carrier_id is nullable.
COPY shipments(shipment_id, order_id, carrier_id, lane_id,
               promised_delivery_ts, actual_delivery_ts,
               shipping_cost, late_penalty_cost, on_time_flag)
FROM 'C:/pgdata/shipments.csv' WITH (FORMAT CSV, HEADER TRUE);

-- stage_events: loads everything including 8 orphan events
-- (no FK on this table by design - see file 00).
COPY stage_events(event_id, shipment_id, stage, event_ts)
FROM 'C:/pgdata/stage_events.csv' WITH (FORMAT CSV, HEADER TRUE);

-- ------------------------------------------------------------
-- Verify row counts so we know the load worked.
-- Expected: warehouses=5, carriers=4, lanes=25, orders=12000,
--           shipments=12000, stage_events=72008
-- ------------------------------------------------------------
SELECT 'warehouses'   AS table_name, COUNT(*) AS row_count FROM warehouses
UNION ALL SELECT 'carriers',     COUNT(*) FROM carriers
UNION ALL SELECT 'lanes',        COUNT(*) FROM lanes
UNION ALL SELECT 'orders',       COUNT(*) FROM orders
UNION ALL SELECT 'shipments',    COUNT(*) FROM shipments
UNION ALL SELECT 'stage_events', COUNT(*) FROM stage_events
ORDER BY table_name;
