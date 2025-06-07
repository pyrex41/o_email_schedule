# Dump-Based Workflow for Turso Integration

## Overview

This document describes the new dump-based workflow for Turso integration, designed to work around broken embedded replica functionality. Instead of using embedded replicas, this approach:

1. **Dumps the entire remote database as SQL** 
2. **Creates a local SQLite database** from the dump
3. **Uses sqldiff** to generate changesets
4. **Applies changes in batches** to the remote database for efficiency

## Why This Approach?

- **Embedded replicas are broken** in the current Turso implementation
- **Simple and reliable**: No complex sync state management  
- **Efficient batching**: Changes are applied in optimized batches (CREATE, DELETE, INSERT)
- **Full compatibility**: Works with existing OCaml code and sqldiff tools
- **Transparent**: You can inspect the dump and diff files for debugging

## Commands

### `dump-init` - Initialize Local Database

```bash
./turso-workflow.sh dump-init
```

**What it does:**
1. Connects to your Turso database (no sync/replica setup)
2. Executes a full database dump (schema + data)
3. Creates a baseline SQLite database (`baseline.db`) from the dump (one-time slow operation)
4. Copies baseline to working copy (`working_copy.db`) via fast file copy
5. Saves the original dump (`original_dump.sql`) for reference

**Requirements:**
- `TURSO_DATABASE_URL` and `TURSO_AUTH_TOKEN` environment variables
- `sqlite3` command available in PATH

### `dump-push` - Push Changes to Turso  

```bash
./turso-workflow.sh dump-push
```

**What it does:**
1. Creates a temporary database by copying the baseline database (fast file copy)
2. Runs `sqldiff` between the temporary database and your current working copy
3. Applies changes to the remote Turso database using optimized batching:
   - **CREATE statements** first (with IF NOT EXISTS for idempotency)
   - **DELETE statements** in large batches (1000 per batch)
   - **INSERT statements** in medium batches (500 per batch)
   - **Other statements** individually
4. Updates the baseline database and dump file to reflect the current remote state

**Requirements:**
- Must run `dump-init` first
- `sqldiff` command available in PATH
- Local `working_copy.db` and `baseline.db` files must exist

## Example Workflow

```bash
# 1. Set up environment
export TURSO_DATABASE_URL="libsql://your-database-url"
export TURSO_AUTH_TOKEN="your-auth-token"

# 2. Initialize local database from remote dump
./turso-workflow.sh dump-init

# 3. Run your OCaml application (uses working_copy.db)
dune exec -- ./bin/main.exe

# 4. Push changes back to Turso
./turso-workflow.sh dump-push

# 5. Check status anytime
./turso-workflow.sh status
```

## Performance Optimizations

### ⚡ Baseline Database Optimization

The workflow uses a **baseline database** strategy for maximum speed:

- **dump-init**: Creates `baseline.db` once (slow, ~20s for large databases)
- **dump-push**: Copies `baseline.db` to `temp_original.db` (fast, ~0.01s)
- **No more**: 20+ second SQL dump recreation on every push!

**Before optimization**: 21+ seconds to recreate from SQL dump  
**After optimization**: 0.01 seconds to copy database file  
**Speed improvement**: 2000x faster! 🚀

### Batching Strategy

The `dump-push` command uses intelligent batching:

- **CREATE statements**: Executed individually with idempotency (`IF NOT EXISTS`)
- **DELETE statements**: Batched in groups of 1000 (simple, fast operations)  
- **INSERT statements**: Batched in groups of 500 (larger payloads)
- **Other statements**: Executed individually for safety

### Dump Strategy

The `dump-init` command generates SQL dumps by:

1. Querying `sqlite_master` for schema definitions
2. Iterating through each table to dump data as INSERT statements
3. Handling all SQLite data types (NULL, INTEGER, REAL, TEXT, BLOB)
4. Properly escaping string values and encoding binary data

## Files Created

- **`working_copy.db`**: Your local SQLite database for OCaml
- **`baseline.db`**: Baseline database (original remote state) for fast diff generation
- **`original_dump.sql`**: The original dump from Turso (for reference)
- **`diff.sql`**: The latest diff file (for debugging)
- **`temp_original.db`**: Temporary file (automatically cleaned up)

## Error Handling

- Validates that required tools (`sqlite3`, `sqldiff`) are available
- Checks for required environment variables
- Provides clear error messages with suggested fixes
- Cleans up temporary files on failure

## Monitoring

Use `./turso-workflow.sh status` to check:
- ✅ File sizes and availability
- ✅ Required tools installation
- ✅ Environment variables
- ✅ Command availability

## Troubleshooting

### Common Issues

1. **"sqlite3 command not found"**
   ```bash
   # macOS
   brew install sqlite
   
   # Ubuntu/Debian  
   sudo apt-get install sqlite3
   ```

2. **"sqldiff command not found"**
   ```bash
   # Already included in this project
   ./sqldiff --help
   
   # Or install SQLite tools
   brew install sqlite  # includes sqldiff
   ```

3. **"Baseline database not found"**
   ```bash
   # Must run dump-init first
   ./turso-workflow.sh dump-init
   ```

4. **Large diff files**
   - The batching automatically handles large diffs
   - Monitor progress with the detailed logging output
   - Diff files are saved for inspection

### Debug Information

All commands provide detailed logging:
- Connection status
- File sizes and operations
- Batch processing progress
- Timing information
- Statement counts and types

## Comparison with Other Approaches

| Approach | Pros | Cons |
|----------|------|------|
| **Dump-based** (New) | ✅ Reliable, ✅ Simple, ✅ Fast batching | ❌ Full download each init |
| **Embedded Replica** | ✅ Incremental sync | ❌ Currently broken |
| **LibSQL Sync** | ✅ Built-in sync | ❌ May inherit replica issues |
| **Manual sqldiff** | ✅ Simple | ❌ No batching, slow for large changes |

## Integration with OCaml

Your OCaml code doesn't need any changes! Just use `working_copy.db` as your SQLite database:

```ocaml
let db_path = "working_copy.db" in
let db = Sqlite3.db_open db_path in
(* Your existing code works unchanged *)
```

The dump-based workflow is a drop-in replacement that handles all the Turso synchronization transparently. 