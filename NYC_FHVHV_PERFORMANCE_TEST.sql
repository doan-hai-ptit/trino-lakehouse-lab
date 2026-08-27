-- NYC FHVHV Lakehouse performance test queries
--
-- Huong dan chay:
-- 1. Chay P00 de kiem tra statistics truoc khi benchmark.
-- 2. Chay moi EXPLAIN ANALYZE tu 3 lan: lan dau la cold run, cac lan sau la
--    warm run. Khong so sanh mot cold run voi mot warm run.
-- 3. Ghi lai Query ID, Planning, Execution, CPU, Physical Input, Input rows,
--    peak memory va spilled data trong output EXPLAIN ANALYZE.
-- 4. Chay tung truy van rieng, khong chay toan bo file nhu mot batch.
-- 5. Cac truy van Iceberg fact-level can chay bang admin hoac DE. DA khong co
--    quyen doc Silver; DS chi thay du lieu nam 2025 va driver_pay bi mask.
-- 6. Catalog PostgreSQL runtime la postgresql; Mart nam trong schema mart.
--
-- EXPLAIN ANALYZE thuc thi truy van that. Cac truy van trong file nay chi doc
-- du lieu, nhung P01 va P07 co the ton nhieu CPU, memory va I/O.


-- ============================================================================
-- P00. Statistics va pham vi du lieu
-- Muc dich: xac nhan optimizer co row count, min/max va column statistics.
-- ============================================================================

SHOW STATS FOR iceberg.silver.fact_trip;

SHOW STATS FOR (
    SELECT *
    FROM iceberg.silver.fact_trip
    WHERE pickup_date >= DATE '2025-01-01'
      AND pickup_date < DATE '2025-02-01'
);

SHOW STATS FOR postgresql.mart.daily_market_kpi;


-- ============================================================================
-- P01. Iceberg full scan baseline
-- Muc dich: do throughput khi doc toan bo fact table.
-- Can theo doi: Physical Input, Input rows, CPU, blocked time va skew.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    COUNT(*) AS trip_count,
    SUM(trip_miles) AS total_miles,
    SUM(base_passenger_fare) AS total_passenger_fare,
    SUM(driver_pay) AS total_driver_pay
FROM iceberg.silver.fact_trip;


-- ============================================================================
-- P02. Iceberg partition pruning theo mot thang
-- Muc dich: so sanh Physical Input voi P01. fact_trip duoc partition theo
-- month(pickup_date), nen input cua P02 phai nho hon dang ke P01.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    COUNT(*) AS trip_count,
    SUM(trip_miles) AS total_miles,
    AVG(calculated_duration_seconds) / 60.0 AS avg_duration_minutes,
    SUM(base_passenger_fare) AS total_passenger_fare
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2025-02-01';


-- ============================================================================
-- P03. Selective filter va column pruning
-- Muc dich: chi doc mot so cot can thiet va mot khoang ngay ngan.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    pickup_date,
    pu_location_id,
    COUNT(*) AS trip_count,
    AVG(trip_miles) AS avg_trip_miles
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2025-01-08'
  AND pu_location_id IN (132, 138, 161, 162, 230)
GROUP BY pickup_date, pu_location_id
ORDER BY pickup_date, trip_count DESC;


-- ============================================================================
-- P04. Aggregation co cardinality cao
-- Muc dich: do hash aggregation, network exchange va data skew theo base/zone.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    pickup_date,
    dispatching_base_num,
    pu_location_id,
    COUNT(*) AS trip_count,
    SUM(trip_miles) AS total_miles,
    SUM(base_passenger_fare) AS total_passenger_fare
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2025-02-01'
  AND dispatching_base_num IS NOT NULL
GROUP BY pickup_date, dispatching_base_num, pu_location_id;


-- ============================================================================
-- P05. Join fact voi dimension trong Iceberg
-- Muc dich: kiem tra join distribution, exchange va kha nang broadcast dim_date.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    d.is_weekend,
    HOUR(f.pickup_ts) AS pickup_hour,
    COUNT(*) AS trip_count,
    AVG(f.trip_miles) AS avg_trip_miles,
    AVG(f.calculated_duration_seconds) / 60.0 AS avg_duration_minutes
FROM iceberg.silver.fact_trip AS f
INNER JOIN iceberg.silver.dim_date AS d
    ON f.pickup_date = d.date_key
WHERE f.pickup_date >= DATE '2025-01-01'
  AND f.pickup_date < DATE '2025-06-01'
GROUP BY d.is_weekend, HOUR(f.pickup_ts)
ORDER BY d.is_weekend, pickup_hour;


-- ============================================================================
-- P06. Top-N tren ket qua aggregate
-- Muc dich: do partial aggregation va TopN, tranh sort toan bo fact rows.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    dispatching_base_num,
    COUNT(*) AS trip_count,
    SUM(base_passenger_fare) AS total_passenger_fare,
    SUM(driver_pay) AS total_driver_pay
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2025-04-01'
  AND dispatching_base_num IS NOT NULL
GROUP BY dispatching_base_num
ORDER BY trip_count DESC
LIMIT 20;


-- ============================================================================
-- P07. Window function tren aggregate hang ngay
-- Muc dich: do sort/window ma khong ap dung window truc tiep len fact rows.
-- ============================================================================

EXPLAIN ANALYZE VERBOSE
WITH daily AS (
    SELECT
        pickup_date,
        COUNT(*) AS trip_count,
        SUM(base_passenger_fare) AS daily_fare
    FROM iceberg.silver.fact_trip
    WHERE pickup_date >= DATE '2025-01-01'
      AND pickup_date < DATE '2025-07-01'
    GROUP BY pickup_date
)
SELECT
    pickup_date,
    trip_count,
    daily_fare,
    AVG(trip_count) OVER (
        ORDER BY pickup_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS trip_count_7d_avg,
    SUM(daily_fare) OVER (
        ORDER BY pickup_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_fare
FROM daily
ORDER BY pickup_date;


-- ============================================================================
-- P08. PostgreSQL Mart filter va aggregation
-- Muc dich: kiem tra connector pushdown. Trong plan, tim scan postgresql va
-- xac nhan filter/aggregation co duoc day xuong PostgreSQL hay khong.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    metric_date,
    SUM(trip_count) AS trip_count,
    SUM(total_miles) AS total_miles,
    SUM(total_passenger_fare) AS total_passenger_fare
FROM postgresql.mart.daily_market_kpi
WHERE metric_date >= DATE '2025-01-01'
  AND metric_date < DATE '2025-04-01'
GROUP BY metric_date
ORDER BY metric_date;


-- ============================================================================
-- P09. PostgreSQL Mart join PostgreSQL target
-- Muc dich: do join giua hai schema trong cung PostgreSQL catalog va kiem tra
-- muc do pushdown cua connector.
-- ============================================================================

EXPLAIN ANALYZE
WITH actual AS (
    SELECT
        CAST(DATE_TRUNC('month', metric_date) AS DATE) AS metric_month,
        SUM(trip_count) AS actual_trip_count
    FROM postgresql.mart.daily_market_kpi
    WHERE metric_date >= DATE '2025-01-01'
      AND metric_date < DATE '2026-01-01'
    GROUP BY 1
)
SELECT
    a.metric_month,
    a.actual_trip_count,
    t.target_value AS target_trip_count,
    a.actual_trip_count - t.target_value AS trip_target_variance
FROM actual AS a
LEFT JOIN postgresql.ops.monthly_kpi_target AS t
    ON a.metric_month = t.metric_month
   AND t.metric_name = 'trip_count'
   AND t.scope_type = 'city'
   AND t.scope_key = 'nyc'
ORDER BY a.metric_month;


-- ============================================================================
-- P10. Join xuyen catalog Iceberg va PostgreSQL
-- Muc dich: do chi phi doc hai connector, exchange va join tai Trino.
-- Chay bang admin, DE hoac DA; DS khong co quyen doc data_quality_rule.
-- ============================================================================

EXPLAIN ANALYZE
WITH observed AS (
    SELECT
        metric_date,
        source_year,
        'missing_location_rows' AS metric_name,
        CAST(missing_location_rows AS DECIMAL(18, 2)) AS actual_value
    FROM iceberg.quality.trip_quality_daily
    WHERE metric_date >= DATE '2025-01-01'
      AND metric_date < DATE '2025-04-01'
)
SELECT
    o.metric_date,
    o.source_year,
    o.actual_value,
    r.threshold_value,
    CASE
        WHEN o.actual_value <= r.threshold_value THEN 'PASS'
        WHEN r.rule_id IS NULL THEN 'NO_RULE'
        ELSE 'FAIL'
    END AS rule_status
FROM observed AS o
LEFT JOIN postgresql.ops.data_quality_rule AS r
    ON r.source_table = 'iceberg.bronze.fhvhv_trip'
   AND r.metric_name = o.metric_name
   AND r.is_enabled = true
ORDER BY o.metric_date;


-- ============================================================================
-- P11. Cung mot KPI: tinh tu Silver va doc tu Mart
-- Muc dich: chay hai truy van rieng va so sanh Execution/CPU/Physical Input.
-- Khong cong thoi gian cua hai truy van vao mot ket qua duy nhat.
-- ============================================================================

-- P11-A: tinh truc tiep tu Silver.
EXPLAIN ANALYZE
SELECT
    pickup_date AS metric_date,
    COUNT(*) AS trip_count,
    SUM(trip_miles) AS total_miles,
    SUM(base_passenger_fare) AS total_passenger_fare
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2026-01-01'
GROUP BY pickup_date
ORDER BY pickup_date;

-- P11-B: doc KPI da tong hop tu PostgreSQL Mart.
EXPLAIN ANALYZE
SELECT
    metric_date,
    SUM(trip_count) AS trip_count,
    SUM(total_miles) AS total_miles,
    SUM(total_passenger_fare) AS total_passenger_fare
FROM postgresql.mart.daily_market_kpi
WHERE metric_date >= DATE '2025-01-01'
  AND metric_date < DATE '2026-01-01'
GROUP BY metric_date
ORDER BY metric_date;


-- ============================================================================
-- P12. Concurrency test
-- Mo 3 den 5 session cung mot user va chay P02 dong thoi. So sanh voi baseline
-- mot session: queued time, execution time, CPU, blocked time va peak memory.
-- Dung truy van duoi day trong moi session de giu workload giong nhau.
-- ============================================================================

EXPLAIN ANALYZE
SELECT
    pickup_date,
    pu_location_id,
    COUNT(*) AS trip_count,
    SUM(trip_miles) AS total_miles,
    AVG(calculated_duration_seconds) / 60.0 AS avg_duration_minutes
FROM iceberg.silver.fact_trip
WHERE pickup_date >= DATE '2025-01-01'
  AND pickup_date < DATE '2025-02-01'
GROUP BY pickup_date, pu_location_id;


-- ============================================================================
-- J01. Join cung catalog Iceberg: fact_trip voi dim_date
-- Ket qua 2025: Queued 2.52ms, Analysis 1.37s, Planning 1.31s, CPU 55.53ms,
-- Peak memory 2.86KB, Execution ~45.3s.
-- ============================================================================
EXPLAIN ANALYZE
SELECT
    d.is_weekend,
    COUNT(*) AS trip_count,
    SUM(f.trip_miles) AS total_miles,
    AVG(f.calculated_duration_seconds) / 60.0 AS avg_duration_minutes
FROM iceberg.silver.fact_trip AS f
JOIN iceberg.silver.dim_date AS d
    ON f.pickup_date = d.date_key
WHERE f.pickup_date >= DATE '2025-01-01'
  AND f.pickup_date < DATE '2026-01-01'
GROUP BY d.is_weekend
ORDER BY d.is_weekend;


-- ============================================================================
-- J02. Join cung catalog PostgreSQL: daily KPI voi monthly target
-- Ket qua 2025: Queued 1.72ms, Analysis 173.08ms, Planning 273.98ms,
-- CPU 36.13ms, Peak memory 2.70KB, Execution ~0.847s.
-- ============================================================================
EXPLAIN ANALYZE
SELECT
    CAST(DATE_TRUNC('month', k.metric_date) AS DATE) AS metric_month,
    SUM(k.trip_count) AS actual_trip_count,
    t.target_value,
    SUM(k.trip_count) - t.target_value AS variance
FROM postgresql.mart.daily_market_kpi AS k
LEFT JOIN postgresql.ops.monthly_kpi_target AS t
    ON CAST(DATE_TRUNC('month', k.metric_date) AS DATE) = t.metric_month
   AND t.metric_name = 'trip_count'
   AND t.scope_type = 'city'
   AND t.scope_key = 'nyc'
WHERE k.metric_date >= DATE '2025-01-01'
  AND k.metric_date < DATE '2026-01-01'
GROUP BY 1, t.target_value
ORDER BY 1;


-- ============================================================================
-- J03. Join xuyen catalog: Iceberg quality voi PostgreSQL rule
-- Ket qua 2025: Queued 1.79ms, Analysis 598.21ms, Planning 466.27ms,
-- CPU 27.01ms, Peak memory 17.60KB, Execution ~0.741s.
-- ============================================================================
EXPLAIN ANALYZE
SELECT
    q.metric_date,
    q.source_year,
    q.missing_location_rows,
    r.threshold_value,
    CASE
        WHEN r.rule_id IS NULL THEN 'NO_RULE'
        WHEN q.missing_location_rows <= r.threshold_value THEN 'PASS'
        ELSE 'FAIL'
    END AS rule_status
FROM iceberg.quality.trip_quality_daily AS q
LEFT JOIN postgresql.ops.data_quality_rule AS r
    ON r.source_table = 'iceberg.bronze.fhvhv_trip'
   AND r.metric_name = 'missing_location_rows'
   AND r.is_enabled = true
WHERE q.metric_date >= DATE '2025-01-01'
  AND q.metric_date < DATE '2026-01-01'
ORDER BY q.metric_date;
