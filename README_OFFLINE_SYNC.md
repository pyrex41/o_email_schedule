# Turso Offline Sync Commands

This document explains the new commands added to support Turso's offline sync capabilities for applying diff files and syncing with remote databases.

## New Commands

### 1. `apply-diff` - Apply Diff File and Sync

This command applies a SQL diff file to your local database and syncs the changes to Turso using the libSQL client's sync capabilities.

```bash
./turso-workflow.sh apply-diff
# OR directly with the Rust binary:
./target/release/turso-sync apply-diff --db-path working_copy.db --diff-file diff.sql
```

**Features:**
- Applies SQL statements from diff.sql to your local database
- Handles large diffs by processing in smaller batches
- Automatically syncs changes to Turso after applying
- Uses `--no-sync` flag to skip the sync step if needed

**Options:**
- `--db-path` - Path to local database (default: working_copy.db)
- `--diff-file` - Path to diff SQL file (default: diff.sql)
- `--sync-url` - Turso database URL (or use TURSO_DATABASE_URL env var)
- `--token` - Auth token (or use TURSO_AUTH_TOKEN env var)
- `--no-sync` - Skip sync to remote after applying diff

### 2. `offline-sync` - Bidirectional Sync

This command performs offline sync operations to keep your local database in sync with Turso.

```bash
./turso-workflow.sh offline-sync [direction]
# OR directly with the Rust binary:
./target/release/turso-sync offline-sync --db-path working_copy.db --direction both
```

**Directions:**
- `pull` - Pull changes from remote to local
- `push` - Push local changes to remote
- `both` - Bidirectional sync (default)

**Options:**
- `--db-path` - Path to local database (default: working_copy.db)
- `--sync-url` - Turso database URL (or use TURSO_DATABASE_URL env var)
- `--token` - Auth token (or use TURSO_AUTH_TOKEN env var)
- `--direction` - Sync direction: pull, push, or both (default: both)

## Workflow Examples

### New Offline Sync Workflow

1. **Initial setup:**
   ```bash
   ./turso-workflow.sh offline-sync pull    # Pull from Turso
   ```

2. **Run your OCaml application** (uses working_copy.db)

3. **Check what changed:**
   ```bash
   ./turso-workflow.sh diff                 # Generate diff.sql
   ```

4. **Apply changes and sync:**
   ```bash
   ./turso-workflow.sh apply-diff          # Apply diff and sync to Turso
   ```

### Alternative: Direct Push

Instead of using apply-diff, you can push all changes directly:

```bash
./turso-workflow.sh offline-sync push   # Push all changes to Turso
```

### Legacy Workflow (Still Supported)

The original workflow using replica sync is still available:

1. `./turso-workflow.sh init`     # Initial setup
2. Run your OCaml application
3. `./turso-workflow.sh diff`     # Check what changed
4. `./turso-workflow.sh push`     # Push changes to Turso

## Environment Variables

Set these in your `.env` file or environment:

```bash
TURSO_DATABASE_URL=libsql://your-database-url
TURSO_AUTH_TOKEN=your-auth-token
```

## Technical Details

The new commands use libSQL's replica sync capabilities with these features:

- **Batched execution**: Large diffs are processed in batches to avoid overwhelming the database
- **Error handling**: Individual statement errors are reported with context
- **Sync status**: Shows database statistics after sync operations
- **Flexible sync**: Supports pull-only, push-only, or bidirectional sync

## Migration from Legacy Commands

| Legacy Command | New Command | Notes |
|----------------|-------------|-------|
| `init` | `offline-sync pull` | Initial sync from remote |
| `push` | `apply-diff` or `offline-sync push` | Apply diff or push all changes |
| `pull` | `offline-sync pull` | Pull from remote |

The new commands provide more granular control and better error handling compared to the legacy sqldiff-based approach. 