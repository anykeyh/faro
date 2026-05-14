# Faro

Simple monitoring solution, but not _dumb-simple_. One binary installation. Compatible with most deployment.

Perfect for quick monitoring of embedded system, local servers, bare metal deployments, or small clusters. Compatible with Prometheus scrape format. 
When you need a serious monitoring setup but don't want to waste a day on it.

---

## Features

- **Zero-dependency binary** — compiled Crystal + embedded DuckDB. No Postgres, no Redis, no external database.
- **Built-in probes** — CPU, memory, disk, network, load, swap, processes, GPU, thermal, HTTP checks, and more. Just reference them by name.
- **Custom probes** — bring your own shell scripts or binaries. Faro runs anything that writes JSON to stdout.
- **Container-aware** — run probes inside Docker containers with `via: docker`.
- **Threshold alerts** — define latches with set/release levels and sustain durations. Get notified via scripts.
- **Web dashboard** — drag-and-drop grid with indicator cards, live graphs, and alert status. Built with Mithril.js, served by the binary itself.
- **Prometheus endpoint** — `/metrics` exposes all latest values for scraping.
- **Notifications** — run any script (Slack webhook, PagerDuty, email) on latch open/close events.
- **Embedded storage** — DuckDB powers retention and querying. No separate storage process needed.

## Installation

### From GitHub releases (recommended)

```bash
# x86_64 Linux
curl -L -o faro \
  "https://github.com/anykeyh/faro/releases/latest/download/faro-linux-amd64" && \
  chmod +x faro

# ARM64 Linux (Raspberry Pi, AWS Graviton, etc.)
curl -L -o faro \
  "https://github.com/anykeyh/faro/releases/latest/download/faro-linux-arm64" && \
  chmod +x faro
```

### From source

```bash
git clone https://github.com/anykeyh/faro
cd faro
crystal build src/main.cr --release
```

Requires Crystal 1.20+ and DuckDB development headers.

## Configuration

Faro uses a single YAML configuration file. Run with:

```bash
./faro -c config.yml
```

### Minimal config

```yaml
db: ":memory:"

server:
  host: "0.0.0.0"
  port: 3000
```

This will start **all system probes** automatically (see below).

### Configuration reference

#### `db`

Storage backend. Supports both **SQLite3** and **DuckDB** via the URI scheme:

```yaml
db: "sqlite3://:memory:"               # ephemeral with SQLite3
db: "duckdb://:memory:"                # ephemeral with DuckDB
db: "sqlite3:///data/faro.db"          # persistent file (SQLite3)
db: "duckdb:///data/faro.duckdb"       # persistent file (DuckDB)
```

### Storage & compaction

Faro uses a **multi-tier bucket system** to keep the database small and queries fast.

| Tier | Resolution | Retention |
|------|------------|-----------|
| Raw  | Each sample as received | ~5 minutes |
| 1m   | Aggregated per minute   | ~1 hour   |
| 5m   | Aggregated per 5 minutes | ~1 hour   |
| 10m  | Aggregated per 10 minutes | ~6 hours |
| 30m  | Aggregated per 30 minutes | ~24 hours |
| 1h   | Aggregated per hour       | ~72 hours |
| 6h   | Aggregated per 6 hours    | ~7 days   |
| 1d   | Aggregated per day        | ~30 days  |

When new data arrives, Faro:
1. Writes it as a **raw** row with the exact timestamp
2. Older raw rows are **compacted** into coarser buckets using Welford online statistics (avg, min, max, variance preserved)
3. Data older than the last tier's age is **purged** automatically

This means a probe running every 5 seconds produces ~12 raw rows/minute, which become 1 row in the 1m tier, then 1 row in the 5m tier, and so on. The database stays at a predictable size regardless of uptime.

The compaction schedule is fully configurable via the `storage` section:

```yaml
storage:
  # Compaction tiers: each tier defines bucket size and minimum age
  # before data is compacted into it.
  tiers:
    - size: 1m
      age: 5m
    - size: 5m
      age: 1h
    - size: 1h
      age: 72h

  # Data older than this is hard-deleted
  purge_after: 365d
```

The `size` and `age` fields accept duration strings (`5s`, `1m`, `5m`, `1h`, `1d`). Tiers are sorted by size automatically. If omitted, the defaults above apply.

#### `log`

Controls logging. All three fields are optional with sensible defaults.

```yaml
log:
  level: warn      # trace, debug, info, warn, error, fatal
  output: /dev/stdout  # where info-level and below go
  error: /dev/stderr   # where warn-level and above go
```

| Field    | Default        | Description |
|----------|----------------|-------------|
| `level`  | `warn`         | Minimum severity to emit |
| `output` | `/dev/stdout`  | Receives trace, debug, info messages |
| `error`  | `/dev/stderr`  | Receives warn, error, fatal messages |

The `level` can also be set via CLI flag `--verbose` / `-v`, which overrides the config to `debug`.

#### `server`

HTTP API bind address and port:

```yaml
server:
  host: "0.0.0.0"
  port: 3000
```

**Optional HTTP Basic Auth**:

```yaml
server:
  host: "0.0.0.0"
  port: 3000
  basic_auth:
    username: admin
    password: changeme
```

When enabled, all HTTP endpoints (dashboard, API, Prometheus) require authentication via the `Authorization: Basic ...` header.

#### `probes`

Controls which system probes run automatically. Each probe runs at a **5-second interval**.

**All system probes** (not set, or commented out):

| Probe | Description | Metric example |
|-------|-------------|----------------|
| `$cpu`       | CPU usage percentage (0–1) | `cpu.usage_pct` |
| `$memory`    | Memory usage (kB, M, pct) | `memory.usage_kb`, `memory.usage_pct` |
| `$disk`      | Disk usage per mount (%) | `disk./.pct` |
| `$load`      | Load averages (1m, 5m, 15m) | `load.load_1m` |
| `$network`   | Network I/O per interface | `network.eth0.rx_bytes` |
| `$swap`      | Swap usage (kB, pct) | `swap.usage_kb`, `swap.usage_pct` |
| `$processes` | Process/thread counts | `processes.total` |
| `$system`    | Uptime, connections | `system.uptime_seconds` |
| `$thermal`   | Thermal zone temperatures | `thermal.zone_0.temp` |

**Opt-in probes** (disabled by default — add them to your `probes` list to enable):

| Probe | Description | Metric example |
|-------|-------------|----------------|
| `$gpu`       | GPU metrics (NVIDIA) | `gpu.gpu0.utilization_pct` |

**Customize** which system probes run (only the listed ones will start):

```yaml
probes:
  - $cpu
  - $memory
  - $disk
  - $load
  - $network
  - $swap
  - $processes
  - $system
  - $thermal
  - $gpu       # < opt-in probe added alongside the others
```

**Disable all system probes**:

```yaml
probes: []
```

#### `adapters`

Each adapter defines a probe to run periodically. An adapter with the same name as a system probe **overrides** its interval or configuration.

Every adapter automatically gets a `_alive` metric — `1.0` when the probe succeeds, `0.0` when it fails or times out. This powers the built-in `meta.healthy` metric (all alive = 1.0, any down = 0.0) and can be used in thresholds:

```yaml
thresholds:
  - name: alive-check
    metric: cpu._alive
    latches:
      - name: dead
        set: 0.5
        release: 0.9
        sustain: 10
```

| Field              | Description |
|--------------------|-------------|
| `name`             | Unique adapter identifier |
| `run`              | Command or `$probe_name` (embedded) |
| `collect_interval` | Polling frequency (e.g. `5s`, `10`, `1m`) |
| `timeout`          | Optional timeout per probe execution |
| `env`              | Environment variables to pass to the probe |
| `via`              | Run inside a container (`docker`) |

**Custom probes** — any executable that writes JSON to stdout:

```yaml
adapters:
  - name: nginx-status
    run: /usr/local/bin/nginx_metrics.sh
    collect_interval: 10s

  - name: database-size
    run: /opt/faro/db_size_check.sh
    collect_interval: 5m
    env:
      DB_DSN: "postgres://user:pass@localhost/mydb"
```

**Container probes** — run inside a Docker container:

```yaml
adapters:
  - name: app-health
    run: $curl_check
    collect_interval: 30s
    via:
      type: docker
      container: api-gateway
    env:
      CURL_URL: http://localhost/health
```

**Meta healthy probe** — automatically tracks if all adapters are alive (built-in, no config needed). Shows as `meta.healthy` in the dashboard. 1.0 when all probes are alive, 0.0 otherwise.

#### `thresholds`

Named alert rules that track when metrics cross thresholds:

```yaml
thresholds:
  - name: high-cpu
    metric: cpu.usage_pct
    latches:
      - name: critical
        set: 0.9
        release: 0.7
        sustain: 30s

      - name: warning
        set: 0.8
        release: 0.6
        sustain: 5m
```

| Field    | Description |
|----------|-------------|
| `set`    | Value at which the latch opens (triggers) |
| `release`| Value at which the latch closes (recovers) |
| `sustain`| How long the condition must persist before opening (optional) |

For `_pct` metrics (0–1), use values like `0.9`. For raw metrics like `_kb` or `_bytes`, use the raw numbers. For time metrics like `time_total_ms`, use milliseconds.

#### `notifications`

Run scripts when latches open or close:

```yaml
notifications:
  - on: "high-cpu.critical"
    script: /opt/faro/scripts/slack_notify.sh
```

Event matching:
- `"name"` — matches any latch for that threshold
- `"name.latch"` — matches a specific latch

Environment variables passed to the script:

| Variable         | Description |
|------------------|-------------|
| `FARO_EVENT`     | `"open"` or `"close"` |
| `FARO_NAME`      | Threshold name |
| `FARO_LATCH`     | Latch name |
| `FARO_METRIC`    | Metric name |
| `FARO_VALUE`     | Trigger value |
| `FARO_TIMESTAMP` | ISO 8601 timestamp |

## API endpoints

| Path                     | Description |
|--------------------------|-------------|
| `/`                      | Dashboard |
| `/health`                | Health check |
| `/api/sensors`           | List all adapters and their metrics |
| `/api/sensors/:name`     | Query time series data (with `since`/`until` params) |
| `/api/sensors/:name/latest` | Latest value per metric (lightweight) |
| `/api/latches`           | All thresholds and current latch states |
| `/metrics`               | Prometheus format |

## Dashboard

The web dashboard is served by Faro itself — no separate frontend server needed. Open `http://localhost:3000` in your browser.

- **Card types**: Indicator (numeric values), Graph (time series), Alerts (threshold status)
- **Drag & drop**: Move cards by grabbing the title bar
- **Resize**: Drag the bottom-right corner to resize any card
- **Add cards**: Click a `+` slot row at the bottom of the grid
- **Edit**: Pencil icon on any card to change its metrics or alerts
- **Auto-refresh**: Cards update every 5 seconds

## Prometheus scraping

```yaml
scrape_configs:
  - job_name: "faro"
    scrape_interval: 10s
    static_configs:
      - targets: ["localhost:3000"]
```

All latest values are exposed as `faro_adapter_metric{adapter="...",metric="..."}` at `/metrics`.

## License

MIT
