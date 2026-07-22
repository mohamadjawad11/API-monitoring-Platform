-- =========================================================
-- API Monitoring Platform — Initial Schema
-- Postgres + TimescaleDB
-- =========================================================

CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE projects (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_projects_user_id ON projects(user_id);

CREATE TABLE api_keys (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    name          TEXT NOT NULL,
    key_prefix    TEXT NOT NULL,
    key_hash      TEXT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at    TIMESTAMPTZ,
    last_used_at  TIMESTAMPTZ
);

CREATE INDEX idx_api_keys_project_id ON api_keys(project_id);
CREATE UNIQUE INDEX idx_api_keys_key_hash ON api_keys(key_hash);

CREATE TABLE events (
    time                TIMESTAMPTZ NOT NULL,
    id                  UUID NOT NULL DEFAULT gen_random_uuid(),
    project_id          UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    endpoint            TEXT NOT NULL,
    method               TEXT NOT NULL,
    status_code          INT NOT NULL,
    latency_ms           DOUBLE PRECISION NOT NULL,
    error_type           TEXT,
    error_message        TEXT,
    is_ai_call           BOOLEAN NOT NULL DEFAULT false,
    ai_provider          TEXT,
    ai_model             TEXT,
    prompt_tokens        INT,
    completion_tokens    INT,
    total_tokens         INT,
    estimated_cost_usd   NUMERIC(12, 6),
    metadata             JSONB,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('events', 'time', chunk_time_interval => INTERVAL '1 day');

CREATE INDEX idx_events_project_time ON events (project_id, time DESC);
CREATE INDEX idx_events_project_endpoint_time ON events (project_id, endpoint, time DESC);
CREATE INDEX idx_events_ai_calls ON events (project_id, time DESC) WHERE is_ai_call = true;
CREATE INDEX idx_events_errors ON events (project_id, time DESC) WHERE status_code >= 400;

ALTER TABLE events SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'project_id',
    timescaledb.compress_orderby   = 'time DESC'
);

SELECT add_compression_policy('events', INTERVAL '7 days');

CREATE MATERIALIZED VIEW events_hourly
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 hour', time) AS bucket,
    project_id,
    endpoint,
    count(*)                                              AS request_count,
    count(*) FILTER (WHERE status_code >= 400)            AS error_count,
    avg(latency_ms)                                        AS avg_latency_ms,
    percentile_agg(latency_ms)                             AS latency_percentiles,
    count(*) FILTER (WHERE is_ai_call)                     AS ai_call_count,
    sum(total_tokens) FILTER (WHERE is_ai_call)            AS ai_total_tokens,
    sum(estimated_cost_usd) FILTER (WHERE is_ai_call)      AS ai_cost_usd
FROM events
GROUP BY bucket, project_id, endpoint
WITH NO DATA;

SELECT add_continuous_aggregate_policy('events_hourly',
    start_offset     => INTERVAL '3 hours',
    end_offset        => INTERVAL '1 hour',
    schedule_interval  => INTERVAL '1 hour'
);
