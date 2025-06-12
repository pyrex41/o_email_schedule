# Turso Sync Service

A lightweight Go service that maintains a local embedded replica of the Turso database, allowing OCaml code to query using standard SQLite libraries.

## Features

- **Embedded Replica**: Maintains a local SQLite file synced with Turso
- **Auto-sync**: Automatically syncs every 2 minutes
- **Manual Sync**: Endpoint to trigger manual sync
- **Health Checks**: Monitor service and database status
- **Read-Your-Writes**: Ensures consistency for the same connection

## Environment Variables

The service reads from the parent directory's `.env` file:

- `CENTRAL_DB_URL` - Turso database URL (required)
- `CENTRAL_DB_TOKEN` - Turso auth token (required)
- `REPLICA_DB_PATH` - Local replica path (default: `./data/central_replica.db`)
- `SYNC_SERVICE_PORT` - HTTP port (default: `9191`)

## Usage

### Start the service:
```bash
cd sync-service
chmod +x start.sh
./start.sh
```

### Check status:
```bash
curl http://localhost:9191/health
```

### Manual sync:
```bash
curl -X POST http://localhost:9191/sync
```

### Get database path:
```bash
curl http://localhost:9191/info
```

## OCaml Integration

Once the service is running, your OCaml code can access the central database using standard SQLite libraries:

```ocaml
(* The replica database path will be: ./sync-service/data/central_replica.db *)
let db_path = "./sync-service/data/central_replica.db"
let db = Sqlite3.db_open db_path

(* Query organizations table with all the new hybrid config columns *)
let get_org_config org_id =
  let sql = "SELECT enable_post_window_emails, pre_exclusion_buffer_days, 
                   timezone, size_profile FROM organizations WHERE id = ?" in
  (* ... standard SQLite query ... *)
```

## Database Schema

After running the migrations, the central database includes:

### organizations table (new columns):
- `enable_post_window_emails` (BOOLEAN, default: 1)
- `effective_date_first_email_months` (INTEGER, default: 11)
- `exclude_failed_underwriting_global` (BOOLEAN, default: 0)
- `send_without_zipcode_for_universal` (BOOLEAN, default: 1)
- `pre_exclusion_buffer_days` (INTEGER, default: 60)
- `birthday_days_before` (INTEGER, default: 14)
- `effective_date_days_before` (INTEGER, default: 30)
- `send_time_hour` (INTEGER, default: 8)
- `send_time_minute` (INTEGER, default: 30)
- `timezone` (TEXT, default: 'America/Chicago')
- `max_emails_per_period` (INTEGER, default: 3)
- `frequency_period_days` (INTEGER, default: 30)
- `size_profile` (TEXT, default: 'medium')
- `config_overrides` (JSON)

### organization_state_buffers table:
- `org_id` (INTEGER, FK to organizations)
- `state_code` (TEXT, 2 chars)
- `pre_exclusion_buffer_days` (INTEGER)
- Timestamps: `created_at`, `updated_at`

## Architecture

```
Turso Database (main-new) 
    ↓ (sync every 2 minutes)
Go Sync Service 
    ↓ (writes to local file)
SQLite Replica File
    ↑ (reads from)
OCaml Application
```

This approach gives you:
- **Familiar SQLite API** in OCaml
- **Always up-to-date data** (2-minute lag max)
- **High read performance** (local file access)
- **Reliability** (works even if Turso is temporarily unavailable) 