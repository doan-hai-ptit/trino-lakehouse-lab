\set ON_ERROR_STOP on

BEGIN;

CREATE SCHEMA IF NOT EXISTS ops AUTHORIZATION nyc_ops_user;

CREATE TABLE IF NOT EXISTS ops.hvfhs_provider (
    hvfhs_license_num varchar(6) PRIMARY KEY,
    provider_name varchar(100) NOT NULL UNIQUE,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    updated_at timestamptz NOT NULL DEFAULT current_timestamp,
    CONSTRAINT hvfhs_provider_license_format_chk
        CHECK (hvfhs_license_num ~ '^HV[0-9]{4}$')
);

CREATE TABLE IF NOT EXISTS ops.dispatching_base (
    dispatching_base_num varchar(6) PRIMARY KEY,
    hvfhs_license_num varchar(6) NOT NULL,
    base_name varchar(150) NOT NULL,
    is_active boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    updated_at timestamptz NOT NULL DEFAULT current_timestamp,
    CONSTRAINT dispatching_base_number_format_chk
        CHECK (dispatching_base_num ~ '^B[0-9]{5}$'),
    CONSTRAINT dispatching_base_provider_fk
        FOREIGN KEY (hvfhs_license_num)
        REFERENCES ops.hvfhs_provider (hvfhs_license_num)
);

CREATE INDEX IF NOT EXISTS idx_dispatching_base_hvfhs_license
    ON ops.dispatching_base (hvfhs_license_num);

CREATE TABLE IF NOT EXISTS ops.base_monthly_kpi_target (
    metric_month date NOT NULL,
    dispatching_base_num varchar(6) NOT NULL,
    trip_target bigint NOT NULL,
    passenger_fare_target numeric(18, 2) NOT NULL,
    status varchar(16) NOT NULL DEFAULT 'APPROVED',
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    updated_at timestamptz NOT NULL DEFAULT current_timestamp,
    CONSTRAINT base_monthly_kpi_target_pk
        PRIMARY KEY (metric_month, dispatching_base_num),
    CONSTRAINT base_monthly_kpi_target_base_fk
        FOREIGN KEY (dispatching_base_num)
        REFERENCES ops.dispatching_base (dispatching_base_num),
    CONSTRAINT base_monthly_kpi_target_month_chk
        CHECK (metric_month = date_trunc('month', metric_month)::date),
    CONSTRAINT base_monthly_kpi_target_trip_chk
        CHECK (trip_target > 0),
    CONSTRAINT base_monthly_kpi_target_fare_chk
        CHECK (passenger_fare_target >= 0),
    CONSTRAINT base_monthly_kpi_target_status_chk
        CHECK (status IN ('DRAFT', 'APPROVED', 'RETIRED'))
);

CREATE INDEX IF NOT EXISTS idx_base_monthly_kpi_target_base_month
    ON ops.base_monthly_kpi_target (dispatching_base_num, metric_month);

CREATE TABLE IF NOT EXISTS ops.ingestion_batch (
    batch_id varchar(64) PRIMARY KEY,
    dataset_name varchar(100) NOT NULL,
    target_schema varchar(63) NOT NULL,
    target_table varchar(63) NOT NULL,
    period_start date NOT NULL,
    period_end date NOT NULL,
    status varchar(16) NOT NULL,
    source_row_count bigint NOT NULL,
    loaded_row_count bigint,
    rejected_row_count bigint NOT NULL DEFAULT 0,
    started_at timestamptz NOT NULL,
    finished_at timestamptz,
    error_message text,
    created_at timestamptz NOT NULL DEFAULT current_timestamp,
    CONSTRAINT ingestion_batch_dataset_period_uk
        UNIQUE (dataset_name, target_schema, target_table, period_start, period_end),
    CONSTRAINT ingestion_batch_period_chk
        CHECK (period_end > period_start),
    CONSTRAINT ingestion_batch_status_chk
        CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED')),
    CONSTRAINT ingestion_batch_source_count_chk
        CHECK (source_row_count >= 0),
    CONSTRAINT ingestion_batch_loaded_count_chk
        CHECK (loaded_row_count IS NULL OR loaded_row_count >= 0),
    CONSTRAINT ingestion_batch_rejected_count_chk
        CHECK (rejected_row_count >= 0),
    CONSTRAINT ingestion_batch_finished_at_chk
        CHECK (finished_at IS NULL OR finished_at >= started_at),
    CONSTRAINT ingestion_batch_status_time_chk
        CHECK (
            (status = 'RUNNING' AND finished_at IS NULL)
            OR (status IN ('SUCCEEDED', 'FAILED') AND finished_at IS NOT NULL)
        ),
    CONSTRAINT ingestion_batch_succeeded_count_chk
        CHECK (status <> 'SUCCEEDED' OR loaded_row_count IS NOT NULL),
    CONSTRAINT ingestion_batch_failed_error_chk
        CHECK (status <> 'FAILED' OR error_message IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_ingestion_batch_status_started_at
    ON ops.ingestion_batch (status, started_at DESC);

INSERT INTO ops.hvfhs_provider (
    hvfhs_license_num,
    provider_name
)
VALUES
    ('HV0003', 'Uber'),
    ('HV0005', 'Lyft')
ON CONFLICT (hvfhs_license_num) DO NOTHING;

INSERT INTO ops.dispatching_base (
    dispatching_base_num,
    hvfhs_license_num,
    base_name
)
VALUES
    ('B03404', 'HV0003', 'UBER USA, LLC'),
    ('B03406', 'HV0005', 'TRI-CITY, LLC')
ON CONFLICT (dispatching_base_num) DO NOTHING;

INSERT INTO ops.base_monthly_kpi_target (
    metric_month,
    dispatching_base_num,
    trip_target,
    passenger_fare_target,
    status
)
VALUES
    (DATE '2024-01-01', 'B03404', 14900000, 362000000.00, 'APPROVED'),
    (DATE '2024-01-01', 'B03406',  5400000, 124000000.00, 'APPROVED'),
    (DATE '2024-02-01', 'B03404', 14900000, 365000000.00, 'APPROVED'),
    (DATE '2024-02-01', 'B03406',  5100000, 120000000.00, 'APPROVED'),
    (DATE '2024-03-01', 'B03404', 16100000, 416000000.00, 'APPROVED'),
    (DATE '2024-03-01', 'B03406',  5900000, 145000000.00, 'APPROVED'),
    (DATE '2024-04-01', 'B03404', 15200000, 395000000.00, 'APPROVED'),
    (DATE '2024-04-01', 'B03406',  5200000, 133000000.00, 'APPROVED'),
    (DATE '2024-05-01', 'B03404', 16100000, 438000000.00, 'APPROVED'),
    (DATE '2024-05-01', 'B03406',  5400000, 143000000.00, 'APPROVED'),
    (DATE '2024-06-01', 'B03404', 15700000, 423000000.00, 'APPROVED'),
    (DATE '2024-06-01', 'B03406',  5200000, 138000000.00, 'APPROVED')
ON CONFLICT (metric_month, dispatching_base_num) DO NOTHING;

INSERT INTO ops.ingestion_batch (
    batch_id,
    dataset_name,
    target_schema,
    target_table,
    period_start,
    period_end,
    status,
    source_row_count,
    loaded_row_count,
    rejected_row_count,
    started_at,
    finished_at
)
VALUES
    (
        'fhvhv-bronze-2024-01', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-01-01', DATE '2024-02-01', 'SUCCEEDED',
        19663930, 19663930, 0,
        TIMESTAMPTZ '2026-07-15 08:07:28+00', TIMESTAMPTZ '2026-07-15 08:08:29.963+00'
    ),
    (
        'fhvhv-bronze-2024-02', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-02-01', DATE '2024-03-01', 'SUCCEEDED',
        19359148, 19359148, 0,
        TIMESTAMPTZ '2026-07-15 08:08:44+00', TIMESTAMPTZ '2026-07-15 08:09:38.494+00'
    ),
    (
        'fhvhv-bronze-2024-03', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-03-01', DATE '2024-04-01', 'SUCCEEDED',
        21280788, 21280788, 0,
        TIMESTAMPTZ '2026-07-15 08:09:51+00', TIMESTAMPTZ '2026-07-15 08:10:50.682+00'
    ),
    (
        'fhvhv-bronze-2024-04', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-04-01', DATE '2024-05-01', 'SUCCEEDED',
        19733038, 19733038, 0,
        TIMESTAMPTZ '2026-07-15 08:10:58+00', TIMESTAMPTZ '2026-07-15 08:12:03.147+00'
    ),
    (
        'fhvhv-bronze-2024-05', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-05-01', DATE '2024-06-01', 'SUCCEEDED',
        20704538, 20704538, 0,
        TIMESTAMPTZ '2026-07-15 08:12:13+00', TIMESTAMPTZ '2026-07-15 08:13:13.500+00'
    ),
    (
        'fhvhv-bronze-2024-06', 'nyc_taxi_fhvhv', 'bronze', 'fhvhv_trip',
        DATE '2024-06-01', DATE '2024-07-01', 'SUCCEEDED',
        20123226, 20123226, 0,
        TIMESTAMPTZ '2026-07-15 08:13:27+00', TIMESTAMPTZ '2026-07-15 08:14:35.092+00'
    )
ON CONFLICT (batch_id) DO NOTHING;

COMMIT;
