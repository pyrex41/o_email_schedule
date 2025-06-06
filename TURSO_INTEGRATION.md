# Turso Integration for OCaml Email Scheduler

This project integrates with [Turso](https://turso.tech) (distributed SQLite) while keeping your existing OCaml code largely unchanged. The solution uses a hybrid approach:

- **Rust** handles Turso synchronization and writes
- **OCaml** continues using regular SQLite3 for reads/writes on a local working copy
- **sqldiff** generates SQL patches to sync changes back to Turso

## Architecture

```
┌─────────────┐    sync     ┌─────────────────┐
│    Turso    │◄───────────►│ local_replica.db│
│  (Remote)   │             │   (Rust sync)   │
└─────────────┘             └─────────────────┘
                                      │ copy
                                      ▼
                            ┌─────────────────┐
                            │ working_copy.db │◄─── OCaml App
                            │ (OCaml R/W)     │
                            └─────────────────┘
                                      │ sqldiff
                                      ▼
                            ┌─────────────────┐
                            │    diff.sql     │───► Apply to Turso
                            │   (Changes)     │     (via Rust)
                            └─────────────────┘
```

## Setup

### 1. Install Dependencies

**Rust:**
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source ~/.cargo/env
```

**SQLite tools (for sqldiff):**
```bash
# macOS
brew install sqlite

# Ubuntu/Debian
sudo apt-get install sqlite3

# Verify sqldiff is available
sqldiff --help
```

### 2. Configure Turso Credentials

Create your Turso database and get credentials:
```bash
# Install Turso CLI
curl -sSfL https://get.tur.so/install.sh | bash

# Create database
turso db create my-email-scheduler

# Get URL and token
turso db show --url my-email-scheduler
turso db tokens create my-email-scheduler
```

Set environment variables (choose one method):

**Method 1: Using .env file (recommended):**
```bash
# Copy the example file and edit it
cp env.example .env
# Edit .env with your actual credentials
```

**Method 2: Using environment variables:**
```bash
export TURSO_DATABASE_URL="libsql://your-database-url"
export TURSO_AUTH_TOKEN="your-auth-token"

# Add to your shell profile for persistence
echo 'export TURSO_DATABASE_URL="libsql://your-database-url"' >> ~/.bashrc
echo 'export TURSO_AUTH_TOKEN="your-auth-token"' >> ~/.bashrc
```

**Method 3: Automated setup:**
```bash
./setup-turso.sh  # Interactive setup script
```

### 3. Initialize the Workflow

```bash
# Check status
./turso-workflow.sh status

# Initialize (sync from Turso and create working copy)
./turso-workflow.sh init
```

This creates:
- `local_replica.db` - Local replica synced with Turso
- `working_copy.db` - Working copy for your OCaml application

## Usage

### Basic Workflow

1. **Initialize** (first time only):
   ```bash
   ./turso-workflow.sh init
   ```

2. **Develop** - Your OCaml code uses `working_copy.db` normally:
   ```ocaml
   let conn = Turso_integration.get_connection ()
   (* Use conn for all your database operations *)
   ```

3. **Check changes**:
   ```bash
   ./turso-workflow.sh diff
   ```

4. **Push changes to Turso**:
   ```bash
   ./turso-workflow.sh push
   ```

5. **Pull latest from Turso**:
   ```bash
   ./turso-workflow.sh pull
   ```

### Commands Reference

| Command | Description |
|---------|-------------|
| `./turso-workflow.sh init` | Initial setup: sync from Turso and create working copy |
| `./turso-workflow.sh push` | Push local changes to Turso using sqldiff |
| `./turso-workflow.sh pull` | Pull latest changes from Turso (preserves local changes) |
| `./turso-workflow.sh reset` | Reset working copy to match Turso (⚠️ discards local changes) |
| `./turso-workflow.sh diff` | Show differences between working copy and replica |
| `./turso-workflow.sh workflow` | Start background periodic sync (every 5 minutes) |
| `./turso-workflow.sh status` | Show current status of databases and tools |

### Background Sync

For long-running applications, you can start a background sync process:

```bash
# Terminal 1: Start background sync
./turso-workflow.sh workflow

# Terminal 2: Run your OCaml application
dune exec -- your-app
```

## Integration with OCaml

### Simple Integration

Your existing OCaml code requires minimal changes:

```ocaml
(* Before: hardcoded database path *)
let conn = Database_native.create_connection "my_database.db"

(* After: use working copy *)
let conn = Turso_integration.get_connection ()
```

### Example Usage

```ocaml
open Lwt.Syntax

let main () =
  (* Check if Turso sync is initialized *)
  if not (Turso_integration.is_initialized ()) then (
    print_endline "❌ Turso not initialized. Run: ./turso-workflow.sh init";
    exit 1
  );

  (* Get connection to working copy *)
  let* conn = Turso_integration.get_connection () in
  
  (* Your existing database code works unchanged *)
  let* results = Database_native.execute_query conn your_query params in
  
  (* Optional: Check if sync might be needed *)
  Turso_integration.suggest_sync_check ();
  
  Lwt.return_unit
```

## Development Patterns

### Pattern 1: Manual Sync Points

```bash
# Development cycle
./turso-workflow.sh pull     # Get latest
# ... make changes in OCaml ...
./turso-workflow.sh diff     # Review changes  
./turso-workflow.sh push     # Push to Turso
```

### Pattern 2: Background Sync

```bash
# Terminal 1: Background sync
./turso-workflow.sh workflow

# Terminal 2: Develop normally
dune build && dune exec -- your-app
```

### Pattern 3: Team Collaboration

```bash
# Before starting work
./turso-workflow.sh pull

# After finishing a feature
./turso-workflow.sh diff     # Review your changes
./turso-workflow.sh push     # Share with team

# Teammates can pull your changes
./turso-workflow.sh pull
```

## Advanced Configuration

### Custom Database Paths

Edit `turso-workflow.sh` to change default paths:

```bash
REPLICA_DB="data/local_replica.db"
WORKING_DB="data/working_copy.db" 
DIFF_FILE="data/diff.sql"
```

### OCaml Configuration

Update `lib/db/turso_integration.ml`:

```ocaml
let working_database_path = "data/working_copy.db"
```

### Automatic Sync Integration

Add sync checks to your OCaml application:

```ocaml
let check_and_suggest_sync () =
  if should_sync_heuristic () then (
    print_endline "💡 Consider syncing: ./turso-workflow.sh push";
    print_endline "💡 Or pull latest: ./turso-workflow.sh pull"
  )
```

## Troubleshooting

### Common Issues

**1. sqldiff not found:**
```bash
# Install SQLite tools
brew install sqlite  # macOS
# or
sudo apt-get install sqlite3  # Ubuntu
```

**2. Rust binary not built:**
```bash
cargo build --release
```

**3. Environment variables not set:**
```bash
./turso-workflow.sh status  # Check what's missing
export TURSO_DATABASE_URL="..."
export TURSO_AUTH_TOKEN="..."
```

**4. Database file conflicts:**
```bash
./turso-workflow.sh status  # Check file status
./turso-workflow.sh reset   # Reset to clean state (⚠️ loses local changes)
```

### Debugging

**Check diff before pushing:**
```bash
./turso-workflow.sh diff
cat diff.sql  # Review the SQL that will be applied
```

**Manual operations:**
```bash
# Build Rust binary
cargo build --release

# Manual sync
./target/release/turso-sync sync

# Manual copy  
./target/release/turso-sync copy

# Manual push
./target/release/turso-sync push
```

**Check file states:**
```bash
ls -la *.db *.sql
./turso-workflow.sh status
```

### Performance Considerations

- **Working copy**: All reads/writes are local (fast)
- **Sync operations**: Only run when needed (push/pull)
- **sqldiff**: Efficient - only generates necessary changes
- **Background sync**: Configurable interval (default: 5 minutes)

## Migration from Pure SQLite

1. **Backup** your existing database
2. **Upload** to Turso:
   ```bash
   turso db shell my-database < backup.sql
   ```
3. **Initialize** workflow:
   ```bash
   ./turso-workflow.sh init
   ```
4. **Update** OCaml code to use `working_copy.db`
5. **Test** the workflow with some changes

## Security Notes

- Environment variables contain sensitive tokens
- Database files may contain sensitive data
- Consider `.gitignore` entries:
  ```
  *.db
  *.db-*
  diff.sql
  target/
  ```

## Contributing

This integration can be enhanced with:
- Automatic conflict resolution
- Schema migration support  
- Performance monitoring
- Integration with CI/CD pipelines
- Multiple database support

## Support

For issues:
1. Check `./turso-workflow.sh status`
2. Review logs from Rust binary
3. Verify Turso connectivity: `turso db show`
4. Check SQLite tools: `sqldiff --help` 