# API Monitoring Platform

## Phase 1: Database Setup (Postgres + TimescaleDB)

### What we did, step by step

1. **Designed the schema** — `schema.sql`
   - `users` — one row per developer account
   - `projects` — one row per monitored backend (a user can have many)
   - `api_keys` — keys the SDK sends with each event; only a hash is stored, never the plain key
   - `events` — the core time-series table (hypertable), one row per captured request, with nullable AI-specific columns (`ai_provider`, `ai_model`, token counts, cost)
   - `events_hourly` — a continuous aggregate (auto-refreshing hourly rollup) for request counts, error counts, avg latency, latency percentiles (via `percentile_agg()`), and AI cost/token totals

2. **Set up Docker** — `docker-compose.yml`
   - Used `timescale/timescaledb-ha:pg16` (not plain `postgres` or plain `timescale/timescaledb`) because this image bundles both TimescaleDB and the `timescaledb_toolkit` extension we need for latency percentiles
   - Mapped host port `5433` → container port `5432`, to avoid clashing with any local Postgres install
   - Added a named volume (`db_data`) so data survives container restarts

3. **Started the container**

   ```
   docker compose up -d
   ```

   Verified it was running and healthy with:

   ```
   docker ps
   ```

4. **Connected via terminal (psql)**

   ```
   docker exec -it monitoring_db psql -U monitoring_user -d monitoring
   ```

5. **Applied the schema**

   ```
   docker exec -i monitoring_db psql -U monitoring_user -d monitoring < schema.sql
   ```

   Confirmed all objects were created: 4 tables, hypertable, indexes, compression policy, continuous aggregate + refresh policy.

6. **Verified everything exists**
   - `\dt` → confirmed `users`, `projects`, `api_keys`, `events`
   - `\dv` → confirmed `events_hourly` (shows as a view, not `\dm`, because TimescaleDB continuous aggregates store real data internally and expose it through a view)

7. **Fixed a GUI connection issue**
   - `psql` worked immediately because it connects locally through a Unix socket (no password check by default)
   - TablePlus connects over the network (TCP), which does require password auth — this is why the two behaved differently
   - Fixed by explicitly setting the password inside psql:
     ```sql
     ALTER USER monitoring_user WITH PASSWORD 'monitoring_dev_password';
     ```

8. **Connected a GUI (TablePlus)**
   - Host: `localhost`, Port: `5433`, User: `monitoring_user`, DB: `monitoring`
   - Confirmed all tables visible in the sidebar

### Current project folder state

```
api-monitoring-platform/
  docker-compose.yml     <- running
  schema.sql             <- applied
  backend/               <- empty, next phase
  frontend/              <- empty, later phase
```

### Known non-issues (don't debug these again)

- `WARNING: column "id" should be used for segmenting or ordering` on the compression `ALTER TABLE` — harmless, `id` is just a uniqueness tiebreaker, not something we filter/sort by
- `events_hourly` not showing under `\dm` — expected, it's a view (`\dv`), not a plain materialized view

---