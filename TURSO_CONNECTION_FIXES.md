# Fixing Turso Connection Issues ("hrana disconnect errors")

## Key Issues Found in Your Original Code

### 1. **Wrong Connection Type**
```rust
// ❌ Your original code (causes connection issues)
Builder::new_remote(url, token).build().await.unwrap()

// ✅ Fixed version (more reliable)
Builder::new_remote_replica("local_replica.db", url, token).build().await.unwrap()
```

**Why:** `new_remote()` creates a pure HTTP connection that's more prone to disconnects. `new_remote_replica()` creates a local replica that syncs with the remote database, providing better reliability and performance.

### 2. **Multiple SQL Statements in Single Query**
```rust
// ❌ Your original code (not supported)
conn.query("select 1; select 1;", ()).await.unwrap();

// ✅ Fixed version
conn.execute_batch("SELECT 1; SELECT 1;").await.unwrap();
```

**Why:** The libSQL client doesn't support multiple statements in a single `query()` call. Use `execute_batch()` instead.

### 3. **Incorrect Row Value Access**
```rust
// ❌ Your original code (deprecated method)
let value = row.get_value(0).unwrap();

// ✅ Fixed version
let value: String = row.get(0).unwrap();
```

**Why:** `get_value()` is deprecated. Use `get::<Type>(index)` with explicit type annotation.

### 4. **Environment Variable Mismatch**
```rust
// ❌ Your original code (inconsistent naming)
let token = std::env::var("LIBSQL_AUTH_TOKEN").unwrap_or_else(|_| {
    println!("LIBSQL_TOKEN not set, using empty token...");  // Wrong name in message
    "".to_string()
});

// ✅ Fixed version
let token = std::env::var("LIBSQL_AUTH_TOKEN").unwrap_or_else(|_| {
    println!("LIBSQL_AUTH_TOKEN not set, using empty token...");
    String::new()
});
```

## How to Test the Fixes

### Option 1: Use the Built-in Test Command
```bash
# Test with environment variables
export LIBSQL_URL="your-turso-url"
export LIBSQL_AUTH_TOKEN="your-auth-token"
cargo run -- test

# Or test with command line args
cargo run -- test --url "your-turso-url" --token "your-auth-token"
```

### Option 2: Run the Example
```bash
# Set environment variables
export LIBSQL_URL="your-turso-url"
export LIBSQL_AUTH_TOKEN="your-auth-token"

# Run the example
cargo run --example turso_connection_example
```

### Option 3: Test Locally (No Turso)
```bash
# This will use in-memory SQLite
unset LIBSQL_URL
cargo run --example turso_connection_example
```

## Additional Recommendations

### 1. **Enable Logging**
Add this to see what's happening:
```rust
env_logger::init();
```

### 2. **Use Proper Error Handling**
```rust
// Instead of .unwrap() everywhere
use anyhow::{Context, Result};

async fn main() -> Result<()> {
    let db = Builder::new_remote_replica("local.db", url, token)
        .build()
        .await
        .context("Failed to build database")?;
    // ...
}
```

### 3. **Consider Connection Features**
```rust
// For better reliability, you can also configure:
let db = Builder::new_remote_replica("local.db", url, token)
    .sync_interval(Duration::from_secs(300))  // Auto-sync every 5 minutes
    .read_your_writes(true)                   // Ensure consistency
    .build()
    .await?;
```

### 4. **Manual Sync When Needed**
```rust
// Sync before important operations
db.sync().await?;

// Your database operations here
let conn = db.connect()?;
// ...
```

## Root Cause of "hrana disconnect errors"

The main issue was using `new_remote()` which creates a direct HTTP connection to Turso. This connection type:
- Is more prone to network timeouts
- Doesn't handle connection drops gracefully  
- Has no local caching/buffering
- Can hang indefinitely on large operations

Using `new_remote_replica()` solves this by:
- Creating a local SQLite replica
- Syncing changes with the remote database
- Providing better performance and reliability
- Handling network issues more gracefully
- Using efficient sync protocol instead of raw HTTP

## What Was Fixed in Your Code

I've implemented **two different strategies** based on your workflow requirements:

### **Pure Dump-Based Workflow (dump-init & dump-push)**
These functions keep using `Builder::new_remote()` as intended, but with **major performance optimizations**:

### 1. Fixed `apply_diff_to_remote()` function 
- **Before**: Large batches (1000 DELETE, 500 INSERT) with no timeouts
- **After**: Small batches (100 DELETE, 50 INSERT) with 30-60s timeouts + retry logic
- **Impact**: Prevents indefinite hangs during large batch operations

### 2. `dump_init()` & `dump_push()` baseline update
- **Strategy**: Keep using direct remote connections for pure dump workflow
- **Fix**: Relies on the improved `apply_diff_to_remote()` batching
- **Impact**: Maintains your intended architecture without embedded sync

### **Replica-Based Workflow (push & other commands)**
These functions use `Builder::new_remote_replica()` for better reliability:

### 3. Fixed `push_to_turso()` function
- **Before**: Used `Builder::new_remote()` for applying diffs  
- **After**: Uses `Builder::new_remote_replica()` with sync operations
- **Impact**: Prevents hangs when using the `push` command

### 4. Other sync functions already correct
- Functions like `sync_from_turso()` and `libsql_sync()` already used proper patterns

Your existing code in `main.rs` already uses these patterns correctly in functions like `sync_from_turso()` and `libsql_sync()`, so you were on the right track!

## Performance Improvements

The fixes should dramatically improve performance because:

### **For Dump-Based Workflow (dump-init & dump-push):**
1. **Smart batching**: Much smaller batches (100 DELETE, 50 INSERT) prevent timeouts
2. **Timeout handling**: 30-60 second timeouts per batch with retry logic
3. **Rate limiting**: Pauses between batches (500ms-1000ms) to avoid overwhelming server
4. **Progress tracking**: Detailed logging shows exactly where operations are

### **For Replica-Based Workflow (push & other commands):**
1. **Local replica caching**: Changes are applied locally first, then synced
2. **Better batching**: Uses libSQL's efficient sync protocol 
3. **Graceful error handling**: Network issues don't cause indefinite hangs
4. **Temporary files**: Cleanup prevents disk space issues 