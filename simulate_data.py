#!/usr/bin/env python3
"""
Logistics / Supply Chain Performance Analytics
Synthetic data simulation pipeline.

Generates a realistic order-to-delivery dataset for a multi-warehouse,
multi-carrier e-commerce fulfilment operation, with deliberately seeded
data-quality issues for the SQL test suite to catch.

All randomness seeded (np.random.seed(42)) so results reproduce exactly.

Output (data/raw/):
    warehouses.csv    - dim: fulfilment centers
    carriers.csv      - dim: shipping carriers + their SLA promises
    lanes.csv         - dim: origin->destination shipping lanes
    orders.csv        - fact: one row per customer order
    shipments.csv     - fact: one row per shipment (1 per order here)
    stage_events.csv  - fact: one row per status change per shipment
                        (the order-to-delivery journey, time-stamped)
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import os

np.random.seed(42)

OUT = "data/raw"
os.makedirs(OUT, exist_ok=True)

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------
N_ORDERS       = 12000
START_DATE     = datetime(2024, 1, 1)
END_DATE       = datetime(2025, 12, 31)
DATE_SPAN_DAYS = (END_DATE - START_DATE).days

# ---------------------------------------------------------------------------
# 1. DIMENSION: Warehouses (fulfilment centers)
# ---------------------------------------------------------------------------
warehouses = pd.DataFrame([
    {"warehouse_id": "WH-CHI", "warehouse_name": "Chicago FC",     "region": "Midwest",  "state": "IL"},
    {"warehouse_id": "WH-DAL", "warehouse_name": "Dallas FC",      "region": "South",    "state": "TX"},
    {"warehouse_id": "WH-ATL", "warehouse_name": "Atlanta FC",     "region": "Southeast","state": "GA"},
    {"warehouse_id": "WH-LAX", "warehouse_name": "Los Angeles FC", "region": "West",     "state": "CA"},
    {"warehouse_id": "WH-NJ",  "warehouse_name": "New Jersey FC",  "region": "Northeast","state": "NJ"},
])

# ---------------------------------------------------------------------------
# 2. DIMENSION: Carriers (each with an SLA promise in days + base cost)
# ---------------------------------------------------------------------------
carriers = pd.DataFrame([
    {"carrier_id": "CR-EXP", "carrier_name": "ExpressShip",   "service_level": "Express",  "sla_days": 2, "base_cost": 18.50},
    {"carrier_id": "CR-STD", "carrier_name": "StandardFreight","service_level": "Standard", "sla_days": 5, "base_cost": 8.75},
    {"carrier_id": "CR-ECO", "carrier_name": "EconoPost",      "service_level": "Economy",  "sla_days": 8, "base_cost": 4.25},
    {"carrier_id": "CR-REG", "carrier_name": "RegionalCarrier","service_level": "Standard", "sla_days": 4, "base_cost": 9.90},
])

# ---------------------------------------------------------------------------
# 3. DIMENSION: Lanes (origin warehouse -> destination region)
# ---------------------------------------------------------------------------
dest_regions = ["Midwest", "South", "Southeast", "West", "Northeast"]
lane_rows = []
lane_id = 1
for _, wh in warehouses.iterrows():
    for dreg in dest_regions:
        # baseline transit difficulty: same region = easy, cross-country = hard
        same = wh["region"] == dreg
        base_transit = np.random.uniform(1.0, 2.0) if same else np.random.uniform(2.5, 6.0)
        lane_rows.append({
            "lane_id": f"LN-{lane_id:03d}",
            "origin_warehouse_id": wh["warehouse_id"],
            "dest_region": dreg,
            "baseline_transit_days": round(base_transit, 2),
        })
        lane_id += 1
lanes = pd.DataFrame(lane_rows)

# ---------------------------------------------------------------------------
# 4. FACT: Orders
# ---------------------------------------------------------------------------
categories = ["Electronics", "Apparel", "Home", "Beauty", "Sports", "Grocery"]
order_rows = []
for i in range(1, N_ORDERS + 1):
    order_dt = START_DATE + timedelta(
        days=int(np.random.randint(0, DATE_SPAN_DAYS)),
        hours=int(np.random.randint(0, 24)),
        minutes=int(np.random.randint(0, 60)),
    )
    wh = warehouses.sample(1).iloc[0]
    dreg = np.random.choice(dest_regions, p=[0.22, 0.20, 0.18, 0.22, 0.18])
    order_rows.append({
        "order_id": f"ORD-{i:06d}",
        "order_ts": order_dt,
        "warehouse_id": wh["warehouse_id"],
        "dest_region": dreg,
        "product_category": np.random.choice(categories),
        "order_value": round(float(np.random.gamma(2.0, 35.0) + 5), 2),
        "units": int(np.random.randint(1, 6)),
    })
orders = pd.DataFrame(order_rows)

# ---------------------------------------------------------------------------
# 5. FACT: Shipments + Stage Events (the journey)
# ---------------------------------------------------------------------------
# Journey stages in order:
#   ORDERED -> PICKED -> PACKED -> SHIPPED -> IN_TRANSIT -> DELIVERED
STAGES = ["ORDERED", "PICKED", "PACKED", "SHIPPED", "IN_TRANSIT", "DELIVERED"]

shipment_rows = []
event_rows = []
event_id = 1

for _, o in orders.iterrows():
    ship_id = o["order_id"].replace("ORD", "SHP")
    carrier = carriers.sample(1).iloc[0]

    # find the matching lane baseline
    lane_match = lanes[(lanes["origin_warehouse_id"] == o["warehouse_id"]) &
                       (lanes["dest_region"] == o["dest_region"])].iloc[0]
    baseline = lane_match["baseline_transit_days"]

    t = o["order_ts"]
    events_for_ship = {}
    events_for_ship["ORDERED"] = t

    # warehouse handling: pick (hours), pack (hours)
    # Atlanta FC is a deliberately weak warehouse -> longer dwell (a finding!)
    dwell_mult = 1.8 if o["warehouse_id"] == "WH-ATL" else 1.0
    t = t + timedelta(hours=float(np.random.uniform(2, 10) * dwell_mult))
    events_for_ship["PICKED"] = t
    t = t + timedelta(hours=float(np.random.uniform(1, 6) * dwell_mult))
    events_for_ship["PACKED"] = t
    t = t + timedelta(hours=float(np.random.uniform(2, 12)))
    events_for_ship["SHIPPED"] = t
    # in-transit handoff happens shortly after shipped
    t = t + timedelta(hours=float(np.random.uniform(1, 4)))
    events_for_ship["IN_TRANSIT"] = t

    # transit time: baseline lane time, inflated by carrier economy & noise
    carrier_drag = {"Express": 0.7, "Standard": 1.0, "Economy": 1.5}[carrier["service_level"]]
    transit_days = baseline * carrier_drag * float(np.random.uniform(0.8, 1.6))
    t = t + timedelta(days=transit_days)
    events_for_ship["DELIVERED"] = t

    delivered_ts = events_for_ship["DELIVERED"]
    promised_ts = o["order_ts"] + timedelta(days=int(carrier["sla_days"]))
    on_time = delivered_ts <= promised_ts

    # shipping cost: base + weight-ish noise + distance proxy
    cost = carrier["base_cost"] + float(np.random.uniform(0, 6)) + baseline * 0.8
    # late penalty cost accrues if late
    penalty = 0.0
    if not on_time:
        days_late = (delivered_ts - promised_ts).total_seconds() / 86400.0
        penalty = round(min(days_late, 10) * 3.5 + 5, 2)

    shipment_rows.append({
        "shipment_id": ship_id,
        "order_id": o["order_id"],
        "carrier_id": carrier["carrier_id"],
        "lane_id": lane_match["lane_id"],
        "promised_delivery_ts": promised_ts,
        "actual_delivery_ts": delivered_ts,
        "shipping_cost": round(cost, 2),
        "late_penalty_cost": penalty,
        "on_time_flag": int(on_time),
    })

    for stage in STAGES:
        event_rows.append({
            "event_id": f"EVT-{event_id:07d}",
            "shipment_id": ship_id,
            "stage": stage,
            "event_ts": events_for_ship[stage],
        })
        event_id += 1

shipments = pd.DataFrame(shipment_rows)
stage_events = pd.DataFrame(event_rows)

# ---------------------------------------------------------------------------
# 6. SEED DELIBERATE DATA-QUALITY ISSUES (for the SQL test suite to catch)
# ---------------------------------------------------------------------------
# Track what we inject so we can document exact expected counts in the README.
dq_log = {}

# (a) Duplicate orders: 15 exact-duplicate order rows
dup_orders = orders.sample(15, random_state=1).copy()
orders = pd.concat([orders, dup_orders], ignore_index=True)
dq_log["duplicate_orders"] = 15

# (b) Orphan stage events: 8 events pointing to a shipment that doesn't exist
orphan_events = []
for k in range(8):
    orphan_events.append({
        "event_id": f"EVT-ORPHAN-{k:03d}",
        "shipment_id": "SHP-999999",   # no such shipment
        "stage": "IN_TRANSIT",
        "event_ts": START_DATE + timedelta(days=int(np.random.randint(0, DATE_SPAN_DAYS))),
    })
stage_events = pd.concat([stage_events, pd.DataFrame(orphan_events)], ignore_index=True)
dq_log["orphan_stage_events"] = 8

# (c) Out-of-order timestamps: 10 shipments where DELIVERED occurs BEFORE SHIPPED
bad_ship_ids = shipments.sample(10, random_state=2)["shipment_id"].tolist()
for sid in bad_ship_ids:
    mask = (stage_events["shipment_id"] == sid) & (stage_events["stage"] == "DELIVERED")
    # push delivered timestamp to BEFORE the shipped timestamp
    shipped_ts = stage_events[(stage_events["shipment_id"] == sid) &
                              (stage_events["stage"] == "SHIPPED")]["event_ts"].iloc[0]
    stage_events.loc[mask, "event_ts"] = shipped_ts - timedelta(days=1)
dq_log["out_of_order_delivered"] = 10

# (d) Negative / impossible transit: 6 shipments with actual_delivery_ts < order_ts
neg_ship_ids = shipments.sample(6, random_state=3)["shipment_id"].tolist()
for sid in neg_ship_ids:
    oid = shipments[shipments["shipment_id"] == sid]["order_id"].iloc[0]
    order_ts = orders[orders["order_id"] == oid]["order_ts"].iloc[0]
    shipments.loc[shipments["shipment_id"] == sid, "actual_delivery_ts"] = order_ts - timedelta(hours=6)
dq_log["negative_transit"] = 6

# (e) Missing carrier: 12 shipments with a null carrier_id
null_carrier_ids = shipments.sample(12, random_state=4)["shipment_id"].tolist()
shipments.loc[shipments["shipment_id"].isin(null_carrier_ids), "carrier_id"] = np.nan
dq_log["missing_carrier"] = 12

# ---------------------------------------------------------------------------
# 7. WRITE OUT
# ---------------------------------------------------------------------------
def ts(df, cols):
    for c in cols:
        df[c] = pd.to_datetime(df[c]).dt.strftime("%Y-%m-%dT%H:%M:%S")
    return df

warehouses.to_csv(f"{OUT}/warehouses.csv", index=False)
carriers.to_csv(f"{OUT}/carriers.csv", index=False)
lanes.to_csv(f"{OUT}/lanes.csv", index=False)
ts(orders, ["order_ts"]).to_csv(f"{OUT}/orders.csv", index=False)
ts(shipments, ["promised_delivery_ts", "actual_delivery_ts"]).to_csv(f"{OUT}/shipments.csv", index=False)
ts(stage_events, ["event_ts"]).to_csv(f"{OUT}/stage_events.csv", index=False)

# ---------------------------------------------------------------------------
# 8. SUMMARY
# ---------------------------------------------------------------------------
print("=" * 60)
print("LOGISTICS DATASET GENERATED")
print("=" * 60)
print(f"warehouses.csv   : {len(warehouses):>7} rows")
print(f"carriers.csv     : {len(carriers):>7} rows")
print(f"lanes.csv        : {len(lanes):>7} rows")
print(f"orders.csv       : {len(orders):>7} rows  (incl. {dq_log['duplicate_orders']} dup rows)")
print(f"shipments.csv    : {len(shipments):>7} rows")
print(f"stage_events.csv : {len(stage_events):>7} rows  (incl. {dq_log['orphan_stage_events']} orphans)")
print("-" * 60)
print("SEEDED DATA-QUALITY ISSUES (for SQL test suite):")
for k, v in dq_log.items():
    print(f"   {k:<26}: {v}")
print("-" * 60)
otd = shipments[shipments['carrier_id'].notna()]['on_time_flag'].mean()
print(f"Overall on-time delivery rate : {otd*100:.1f}%")
print(f"Total shipping cost           : ${shipments['shipping_cost'].sum():,.0f}")
print(f"Total late-penalty cost       : ${shipments['late_penalty_cost'].sum():,.0f}")
print("=" * 60)
