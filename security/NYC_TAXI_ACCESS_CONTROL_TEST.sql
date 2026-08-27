-- NYC Taxi file-based access control verification
--
-- Run each section in a separate Trino session authenticated as the user named
-- in the section heading. Do not run this entire file in a single session.
-- The runtime PostgreSQL catalog is postgres_ops, and Mart is expected at
-- postgres_ops.mart after the migration from Iceberg.


-- ============================================================================
-- 1. ADMIN (connect as admin)
-- All statements in this section must succeed.
-- ============================================================================

SHOW CATALOGS;
SHOW SCHEMAS FROM iceberg;
SHOW SCHEMAS FROM postgres_ops;
SHOW TABLES FROM iceberg.silver;
SHOW TABLES FROM postgres_ops.mart;
SHOW TABLES FROM postgres_ops.ops;

SELECT COUNT(*)
FROM iceberg.nyc_taxi.fhvhv_trips;

SELECT COUNT(*)
FROM iceberg.silver.fact_trip;

SELECT COUNT(*)
FROM postgres_ops.mart.daily_market_kpi;

SELECT COUNT(*)
FROM postgres_ops.ops.monthly_kpi_target;

SELECT node_id, coordinator, state
FROM system.runtime.nodes;


-- ============================================================================
-- 2. DATA ENGINEER (connect as de1 or de2)
-- ============================================================================

-- 2.1. These read statements must succeed.

SHOW SCHEMAS FROM iceberg;
SHOW TABLES FROM iceberg.nyc_taxi;
SHOW TABLES FROM iceberg.bronze;
SHOW TABLES FROM iceberg.silver;
SHOW TABLES FROM iceberg.quality;
SHOW TABLES FROM iceberg.semantic;
SHOW TABLES FROM postgres_ops.mart;
SHOW TABLES FROM postgres_ops.ops;

SELECT COUNT(*)
FROM iceberg.nyc_taxi.fhvhv_trips;

SELECT COUNT(*)
FROM iceberg.silver.fact_trip;

SELECT COUNT(*)
FROM iceberg.quality.trip_quality_daily;

SELECT COUNT(*)
FROM postgres_ops.mart.daily_market_kpi;

SELECT COUNT(*)
FROM postgres_ops.ops.data_quality_rule;

SELECT COUNT(*)
FROM postgres_ops.ops.pipeline_run;

SELECT COUNT(*)
FROM postgres_ops.ops.dashboard_refresh_run;


-- 2.2. These statements verify DE write access in Iceberg.
-- They create only a dedicated ACL test table and remove it at the end.

DROP TABLE IF EXISTS iceberg.quality.acl_de_write_test;

CREATE TABLE iceberg.quality.acl_de_write_test (
    test_id INTEGER,
    test_value VARCHAR
)
WITH (
    format = 'PARQUET',
    format_version = 2
);

INSERT INTO iceberg.quality.acl_de_write_test
VALUES (1, 'created by ACL test');

UPDATE iceberg.quality.acl_de_write_test
SET test_value = 'updated by ACL test'
WHERE test_id = 1;

DELETE FROM iceberg.quality.acl_de_write_test
WHERE test_id = 1;

DROP TABLE iceberg.quality.acl_de_write_test;


-- 2.3. These statements verify DE write access to the PostgreSQL Mart.
-- They create only a dedicated ACL test table and remove it at the end.

DROP TABLE IF EXISTS postgres_ops.mart.acl_de_write_test;

CREATE TABLE postgres_ops.mart.acl_de_write_test (
    test_id INTEGER,
    test_value VARCHAR
);

INSERT INTO postgres_ops.mart.acl_de_write_test
VALUES (1, 'created by ACL test');

UPDATE postgres_ops.mart.acl_de_write_test
SET test_value = 'updated by ACL test'
WHERE test_id = 1;

DELETE FROM postgres_ops.mart.acl_de_write_test
WHERE test_id = 1;

DROP TABLE postgres_ops.mart.acl_de_write_test;


-- 2.4. Every statement below must fail with Access Denied.
-- Run them one at a time because many SQL clients stop after the first error.

DELETE FROM iceberg.nyc_taxi.fhvhv_trips
WHERE false;

UPDATE iceberg.nyc_taxi.fhvhv_trips
SET pickup_datetime = pickup_datetime
WHERE false;

DROP TABLE iceberg.nyc_taxi.fhvhv_trips;

SELECT COUNT(*)
FROM postgres_ops.ops.monthly_kpi_target;

UPDATE postgres_ops.ops.data_quality_rule
SET threshold_value = threshold_value
WHERE false;

DELETE FROM postgres_ops.ops.pipeline_run
WHERE false;


-- ============================================================================
-- 3. DATA SCIENTIST (connect as ds1 or ds2)
-- ============================================================================

-- 3.1. These statements must succeed.

SHOW SCHEMAS FROM iceberg;
SHOW TABLES FROM iceberg.silver;
SHOW TABLES FROM iceberg.quality;
SHOW TABLES FROM iceberg.semantic;
SHOW TABLES FROM postgres_ops.mart;

-- Expected result when 2025 data exists:
-- min_source_year = 2025, max_source_year = 2025, visible_driver_pay_count = 0.
SELECT
    MIN(source_year) AS min_source_year,
    MAX(source_year) AS max_source_year,
    COUNT(driver_pay) AS visible_driver_pay_count
FROM iceberg.silver.fact_trip;

SELECT COUNT(*)
FROM iceberg.silver.dim_date;

SELECT COUNT(*)
FROM iceberg.silver.dim_location;

SELECT COUNT(*)
FROM iceberg.silver.dim_base;

SELECT COUNT(*)
FROM iceberg.quality.trip_quality_daily;

SELECT *
FROM iceberg.semantic.v_daily_market_kpi
LIMIT 10;

SELECT *
FROM postgres_ops.mart.daily_market_kpi
LIMIT 10;


-- 3.2. Every statement below must fail with Access Denied.
-- Run them one at a time.

SELECT COUNT(*)
FROM iceberg.nyc_taxi.fhvhv_trips;

SELECT COUNT(*)
FROM iceberg.bronze.fhvhv_trip;

INSERT INTO iceberg.silver.fact_trip
SELECT *
FROM iceberg.silver.fact_trip
WHERE false;

CREATE TABLE iceberg.silver.acl_ds_write_test (
    test_id INTEGER
);

SELECT COUNT(*)
FROM postgres_ops.ops.data_quality_rule;


-- ============================================================================
-- 4. DATA ANALYST (connect as da1 or da2)
-- ============================================================================

-- 4.1. These statements must succeed.

SHOW SCHEMAS FROM iceberg;
SHOW SCHEMAS FROM postgres_ops;
SHOW TABLES FROM iceberg.quality;
SHOW TABLES FROM iceberg.semantic;
SHOW TABLES FROM postgres_ops.mart;
SHOW TABLES FROM postgres_ops.ops;

SELECT *
FROM postgres_ops.mart.daily_market_kpi
LIMIT 10;

SELECT *
FROM postgres_ops.mart.zone_demand_hourly
LIMIT 10;

SELECT *
FROM postgres_ops.mart.base_performance_monthly
LIMIT 10;

SELECT *
FROM postgres_ops.mart.zone_flow_daily
LIMIT 10;

SELECT *
FROM iceberg.semantic.v_daily_market_kpi
LIMIT 10;

SELECT *
FROM iceberg.quality.trip_quality_daily
LIMIT 10;

SELECT *
FROM postgres_ops.ops.monthly_kpi_target
LIMIT 10;

SELECT *
FROM postgres_ops.ops.zone_demand_target
LIMIT 10;

SELECT *
FROM postgres_ops.ops.data_quality_rule
LIMIT 10;


-- 4.2. This Mart-to-operational-schema query must succeed.

SELECT
    m.metric_month,
    m.pu_location_id,
    m.actual_trip_count,
    t.target_trip_count,
    m.actual_trip_count - t.target_trip_count AS trip_count_variance
FROM postgres_ops.mart.zone_monthly_demand_vs_target AS m
LEFT JOIN postgres_ops.ops.zone_demand_target AS t
    ON m.metric_month = t.metric_month
   AND m.pu_location_id = t.pu_location_id
ORDER BY ABS(m.actual_trip_count - t.target_trip_count) DESC
LIMIT 50;


-- 4.3. Every statement below must fail with Access Denied.
-- Run them one at a time.

SELECT COUNT(*)
FROM iceberg.nyc_taxi.fhvhv_trips;

SELECT COUNT(*)
FROM iceberg.bronze.fhvhv_trip;

SELECT COUNT(*)
FROM iceberg.silver.fact_trip;

SELECT COUNT(*)
FROM postgres_ops.ops.pipeline_run;

SELECT COUNT(*)
FROM postgres_ops.ops.dashboard_refresh_run;

INSERT INTO postgres_ops.mart.daily_market_kpi
SELECT *
FROM postgres_ops.mart.daily_market_kpi
WHERE false;

CREATE TABLE postgres_ops.mart.acl_da_write_test (
    test_id INTEGER
);
