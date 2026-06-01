-- ============================================================
-- File 1 of 6: 00_create_tables.sql
-- Purpose:    Create the schema for the logistics analytics DB.
-- Pattern:    Star schema  (dim_* tables + fact_* tables)
-- ============================================================

-- Drop tables if they already exist, so this script is RE-RUNNABLE.
DROP TABLE IF EXISTS stage_events CASCADE;
DROP TABLE IF EXISTS shipments    CASCADE;
DROP TABLE IF EXISTS orders       CASCADE;
DROP TABLE IF EXISTS lanes        CASCADE;
DROP TABLE IF EXISTS carriers     CASCADE;
DROP TABLE IF EXISTS warehouses   CASCADE;

-- ------------------------------------------------------------
-- DIMENSION TABLES (slowly-changing reference data)
-- ------------------------------------------------------------

-- dim: Fulfilment centers
CREATE TABLE warehouses (
    warehouse_id    VARCHAR(10)  PRIMARY KEY,
    warehouse_name  VARCHAR(50)  NOT NULL,
    region          VARCHAR(20)  NOT NULL,
    state           VARCHAR(2)   NOT NULL
);

-- dim: Shipping carriers + their SLA promise
CREATE TABLE carriers (
    carrier_id      VARCHAR(10)  PRIMARY KEY,
    carrier_name    VARCHAR(50)  NOT NULL,
    service_level   VARCHAR(20)  NOT NULL,   -- Express / Standard / Economy
    sla_days        INTEGER      NOT NULL,   -- promised delivery window in days
    base_cost       NUMERIC(8,2) NOT NULL    -- baseline shipping cost in USD
);

-- dim: Origin warehouse  ->  destination region shipping lanes
CREATE TABLE lanes (
    lane_id                 VARCHAR(10)  PRIMARY KEY,
    origin_warehouse_id     VARCHAR(10)  NOT NULL REFERENCES warehouses(warehouse_id),
    dest_region             VARCHAR(20)  NOT NULL,
    baseline_transit_days   NUMERIC(5,2) NOT NULL
);

-- ------------------------------------------------------------
-- FACT TABLES (the events that happen day to day)
-- ------------------------------------------------------------

-- fact: One row per customer order
CREATE TABLE orders (
    order_id           VARCHAR(15)   PRIMARY KEY,
    order_ts           TIMESTAMP     NOT NULL,
    warehouse_id       VARCHAR(10)   NOT NULL REFERENCES warehouses(warehouse_id),
    dest_region        VARCHAR(20)   NOT NULL,
    product_category   VARCHAR(30)   NOT NULL,
    order_value        NUMERIC(10,2) NOT NULL,
    units              INTEGER       NOT NULL
);

-- fact: One row per shipment (1 per order in this dataset)
CREATE TABLE shipments (
    shipment_id           VARCHAR(15)  PRIMARY KEY,
    order_id              VARCHAR(15)  NOT NULL REFERENCES orders(order_id),
    carrier_id            VARCHAR(10)            REFERENCES carriers(carrier_id),  -- nullable on purpose (DQ test)
    lane_id               VARCHAR(10)  NOT NULL REFERENCES lanes(lane_id),
    promised_delivery_ts  TIMESTAMP    NOT NULL,
    actual_delivery_ts    TIMESTAMP    NOT NULL,
    shipping_cost         NUMERIC(8,2) NOT NULL,
    late_penalty_cost     NUMERIC(8,2) NOT NULL,
    on_time_flag          INTEGER      NOT NULL
);

-- fact: The order-to-delivery JOURNEY (one row per status change)
CREATE TABLE stage_events (
    event_id     VARCHAR(20)  PRIMARY KEY,
    shipment_id  VARCHAR(15)  NOT NULL,   -- NOTE: no FK here, on purpose
    stage        VARCHAR(20)  NOT NULL,   -- ORDERED / PICKED / PACKED / SHIPPED / IN_TRANSIT / DELIVERED
    event_ts     TIMESTAMP    NOT NULL
);
-- Why no foreign key on shipment_id?
-- Because we WANT orphan events to land here (the seeded DQ issue).
-- The 03_data_quality_tests.sql file will catch them. This mirrors how
-- raw data actually arrives in production: messy first, validated after.

-- ------------------------------------------------------------
-- Indexes that speed up the queries we know we'll write
-- ------------------------------------------------------------
CREATE INDEX idx_orders_ts          ON orders(order_ts);
CREATE INDEX idx_orders_wh          ON orders(warehouse_id);
CREATE INDEX idx_shipments_order    ON shipments(order_id);
CREATE INDEX idx_shipments_carrier  ON shipments(carrier_id);
CREATE INDEX idx_shipments_lane     ON shipments(lane_id);
CREATE INDEX idx_events_ship        ON stage_events(shipment_id);
CREATE INDEX idx_events_stage       ON stage_events(stage);
