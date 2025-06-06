#!/bin/bash

# Turso Sync Workflow Script
# This script manages the sync between OCaml SQLite and Turso

set -e

# Configuration
REPLICA_DB="local_replica.db"
WORKING_DB="working_copy.db"
DIFF_FILE="diff.sql"
RUST_BINARY="./target/release/turso-sync"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Load .env file if it exists
load_env() {
    if [ -f ".env" ]; then
        print_info "Loading environment from .env file"
        export $(grep -v '^#' .env | xargs)
    fi
}

# Check if environment variables are set
check_env() {
    load_env
    
    if [ -z "$TURSO_DATABASE_URL" ]; then
        print_error "TURSO_DATABASE_URL environment variable is not set"
        print_info "Create a .env file or export the variable:"
        print_info "  echo 'TURSO_DATABASE_URL=libsql://your-db-url' >> .env"
        exit 1
    fi
    
    if [ -z "$TURSO_AUTH_TOKEN" ]; then
        print_error "TURSO_AUTH_TOKEN environment variable is not set"
        print_info "Create a .env file or export the variable:"
        print_info "  echo 'TURSO_AUTH_TOKEN=your-auth-token' >> .env"
        exit 1
    fi
}

# Build Rust binary if it doesn't exist
build_rust() {
    if [ ! -f "$RUST_BINARY" ]; then
        print_info "Building Rust binary..."
        cargo build --release
    fi
}

# Check if sqldiff is available
check_sqldiff() {
    if ! command -v sqldiff &> /dev/null; then
        print_error "sqldiff command not found. Please install SQLite tools."
        print_info "On macOS: brew install sqlite"
        print_info "On Ubuntu: sudo apt-get install sqlite3"
        exit 1
    fi
}

# Check if bc is available (for timing calculations)
check_bc() {
    if ! command -v bc &> /dev/null; then
        print_warn "bc command not found. Timing information will be approximate."
        print_info "On macOS: brew install bc"
        print_info "On Ubuntu: sudo apt-get install bc"
        return 1
    fi
    return 0
}

# Initialize: sync from Turso and create working copy
init() {
    print_info "Initializing Turso sync workflow..."
    
    check_env
    build_rust
    check_sqldiff
    
    print_info "Syncing from Turso to local replica..."
    $RUST_BINARY sync --replica-path "$REPLICA_DB"
    
    print_info "Creating working copy for OCaml..."
    $RUST_BINARY copy --source "$REPLICA_DB" --dest "$WORKING_DB"
    
    print_info "✅ Initialization complete!"
    print_info "Your OCaml code can now use: $WORKING_DB"
    print_info "Run './turso-workflow.sh push' when ready to sync changes back"
}

# Push changes from working copy to Turso
push() {
    print_info "Pushing changes to Turso..."
    
    check_env
    build_rust
    check_sqldiff
    
    if [ ! -f "$REPLICA_DB" ]; then
        print_error "Local replica not found. Run './turso-workflow.sh init' first."
        exit 1
    fi
    
    if [ ! -f "$WORKING_DB" ]; then
        print_error "Working copy not found. Run './turso-workflow.sh init' first."
        exit 1
    fi
    
    print_info "Generating diff and applying to Turso..."
    $RUST_BINARY push --replica-path "$REPLICA_DB" --working-path "$WORKING_DB" --diff-file "$DIFF_FILE"
    
    print_info "Updating working copy with latest state..."
    $RUST_BINARY copy --source "$REPLICA_DB" --dest "$WORKING_DB"
    
    print_info "✅ Push complete!"
}

# Apply diff file and sync using offline sync capabilities
apply_diff() {
    local no_sync_flag=""
    local sync_message="and syncing to Turso"
    
    # Check for --no-sync flag
    if [[ "$2" == "--no-sync" ]]; then
        no_sync_flag="--no-sync"
        sync_message="(skipping sync to Turso)"
    fi
    
    print_info "Applying diff file $sync_message using offline sync..."
    
    check_env
    build_rust
    
    if [ ! -f "$REPLICA_DB" ]; then
        print_error "Local replica not found. Run './turso-workflow.sh init' first."
        exit 1
    fi
    
    if [ ! -f "$DIFF_FILE" ]; then
        print_error "Diff file not found. Run './turso-workflow.sh diff' first."
        exit 1
    fi
    
    # Show diff size for timing context
    local diff_size=$(wc -c < "$DIFF_FILE")
    print_info "Diff file size: $diff_size bytes"
    
    print_info "⏱️  Starting diff application to $REPLICA_DB..."
    local start_time=$(date +%s.%N)
    
    $RUST_BINARY apply-diff --db-path "$REPLICA_DB" --diff-file "$DIFF_FILE" $no_sync_flag
    
    local end_time=$(date +%s.%N)
    local duration
    if check_bc; then
        duration=$(echo "$end_time - $start_time" | bc -l)
        duration=$(printf "%.3f" "$duration")
    else
        # Fallback to integer seconds if bc is not available
        local start_int=${start_time%.*}
        local end_int=${end_time%.*}
        duration=$((end_int - start_int))
    fi
    
    if [[ "$no_sync_flag" == "--no-sync" ]]; then
        print_info "✅ Diff applied locally in ${duration}s (sync skipped)"
        print_info "💡 Run without --no-sync to see sync timing comparison"
    else
        print_info "✅ Diff applied and synced to Turso in ${duration}s"
    fi
}

# Sync database using offline sync capabilities
sync_offline() {
    local direction="${1:-both}"
    print_info "Syncing database using offline sync (direction: $direction)..."
    
    check_env
    build_rust
    
    if [ ! -f "$WORKING_DB" ]; then
        print_warn "Working copy not found, will be created during sync."
    fi
    
    print_info "Performing offline sync..."
    $RUST_BINARY offline-sync --db-path "$WORKING_DB" --direction "$direction"
    
    print_info "✅ Offline sync complete!"
}

# Bidirectional sync using libSQL sync (recommended)
libsql_sync() {
    local db_path="${1:-$WORKING_DB}"
    print_info "Performing bidirectional sync using libSQL sync..."
    
    check_env
    build_rust
    
    if [ ! -f "$db_path" ]; then
        print_warn "Database not found, will be created during sync."
    fi
    
    print_info "Running libSQL bidirectional sync..."
    $RUST_BINARY libsql-sync --db-path "$db_path"
    
    print_info "✅ LibSQL sync complete!"
}

# Sync latest changes from Turso (without pushing local changes)
pull() {
    print_info "Pulling latest changes from Turso..."
    
    check_env
    build_rust
    
    print_info "Syncing from Turso..."
    $RUST_BINARY sync --replica-path "$REPLICA_DB"
    
    print_warn "⚠️  Working copy ($WORKING_DB) has NOT been updated."
    print_info "Your local changes are preserved."
    print_info "Run './turso-workflow.sh reset' to discard local changes and sync with Turso."
}

# Reset working copy to match Turso (discards local changes)
reset() {
    print_warn "⚠️  This will discard all local changes in $WORKING_DB"
    read -p "Are you sure? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Resetting working copy..."
        
        check_env
        build_rust
        
        $RUST_BINARY sync --replica-path "$REPLICA_DB"
        $RUST_BINARY copy --source "$REPLICA_DB" --dest "$WORKING_DB"
        
        print_info "✅ Working copy reset to match Turso"
    else
        print_info "Reset cancelled"
    fi
}

# Show diff between working copy and replica
diff() {
    check_sqldiff
    
    if [ ! -f "$REPLICA_DB" ] || [ ! -f "$WORKING_DB" ]; then
        print_error "Database files not found. Run './turso-workflow.sh init' first."
        exit 1
    fi
    
    print_info "Generating diff between local replica and working copy..."
    
    sqldiff --transaction "$REPLICA_DB" "$WORKING_DB" > "$DIFF_FILE"
    
    if [ -s "$DIFF_FILE" ]; then
        print_info "Changes detected:"
        echo "===================="
        cat "$DIFF_FILE"
        echo "===================="
        print_info "Diff saved to: $DIFF_FILE"
    else
        print_info "No changes detected - databases are identical"
    fi
}

# Start background workflow (periodic sync)
workflow() {
    print_info "Starting background sync workflow..."
    print_info "This will run periodic syncs from Turso every 5 minutes"
    print_info "Press Ctrl+C to stop"
    
    check_env
    build_rust
    
    $RUST_BINARY workflow --replica-path "$REPLICA_DB" --working-path "$WORKING_DB"
}

# Status check
status() {
    print_info "Turso Sync Status:"
    echo "=================="
    
    if [ -f "$REPLICA_DB" ]; then
        echo "✅ Local replica: $REPLICA_DB ($(du -h "$REPLICA_DB" | cut -f1))"
    else
        echo "❌ Local replica: $REPLICA_DB (not found)"
    fi
    
    if [ -f "$WORKING_DB" ]; then
        echo "✅ Working copy: $WORKING_DB ($(du -h "$WORKING_DB" | cut -f1))"
    else
        echo "❌ Working copy: $WORKING_DB (not found)"
    fi
    
    if [ -f "$DIFF_FILE" ]; then
        echo "📄 Last diff: $DIFF_FILE ($(du -h "$DIFF_FILE" | cut -f1))"
    else
        echo "📄 Last diff: $DIFF_FILE (not found)"
    fi
    
    echo "=================="
    
    if command -v sqldiff &> /dev/null; then
        echo "✅ sqldiff: available"
    else
        echo "❌ sqldiff: not found"
    fi
    
    if [ -f "$RUST_BINARY" ]; then
        echo "✅ Rust binary: built"
    else
        echo "❌ Rust binary: needs building"
    fi
    
    echo "=================="
    
    if [ -n "$TURSO_DATABASE_URL" ]; then
        echo "✅ TURSO_DATABASE_URL: set"
    else
        echo "❌ TURSO_DATABASE_URL: not set"
    fi
    
    if [ -n "$TURSO_AUTH_TOKEN" ]; then
        echo "✅ TURSO_AUTH_TOKEN: set"
    else
        echo "❌ TURSO_AUTH_TOKEN: not set"
    fi
    
    echo "=================="
    echo "Available commands:"
    echo "  Legacy: init, push, pull, reset, diff"
    echo "  New:    apply-diff, offline-sync"
    echo "  Other:  workflow, status"
}

# Usage information
usage() {
    echo "Turso Sync Workflow Script"
    echo ""
    echo "Usage: $0 {init|push|pull|reset|diff|apply-diff|offline-sync|workflow|status}"
    echo ""
    echo "Commands:"
    echo "  init        - Initialize: sync from Turso and create working copy"
    echo "  push        - Push local changes to Turso using sqldiff (legacy method)"
    echo "  pull        - Pull latest changes from Turso (preserves local changes)"
    echo "  reset       - Reset working copy to match Turso (discards local changes)"
    echo "  diff        - Show differences between working copy and replica"
    echo "  apply-diff  - Apply diff file to local replica and sync to Turso (uses offline sync)"
    echo "              Use --no-sync to skip syncing to Turso after applying diff"
    echo "  offline-sync [direction] - Sync using offline sync capabilities"
    echo "              direction: pull, push, or both (default: both)"
    echo "  libsql-sync [db-path]   - Bidirectional sync using libSQL sync (recommended)"
    echo "              db-path: path to database file (default: working_copy.db)"
    echo "  workflow    - Start background periodic sync (every 5 minutes)"
    echo "  status      - Show current status of databases and tools"
    echo ""
    echo "Environment variables required:"
    echo "  TURSO_DATABASE_URL - Your Turso database URL"
    echo "  TURSO_AUTH_TOKEN   - Your Turso authentication token"
    echo ""
    echo "Example workflows:"
    echo ""
    echo "Legacy workflow (using replica sync):"
    echo "  1. ./turso-workflow.sh init     # Initial setup"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh diff     # Check what changed"
    echo "  4. ./turso-workflow.sh push     # Push changes to Turso"
    echo ""
    echo "Recommended libSQL sync workflow:"
    echo "  1. ./turso-workflow.sh libsql-sync         # Bidirectional sync with Turso"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh libsql-sync         # Sync changes back to Turso"
    echo ""
    echo "Alternative offline sync workflow:"
    echo "  1. ./turso-workflow.sh offline-sync pull    # Pull from Turso"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh diff                 # Check what changed"
    echo "  4. ./turso-workflow.sh apply-diff          # Apply diff and sync to Turso"
    echo "     OR"
    echo "  4. ./turso-workflow.sh apply-diff --no-sync # Apply diff locally only (see timing)"
    echo "  5. ./turso-workflow.sh offline-sync push   # Push all changes to Turso"
}

# Main script logic
case "${1:-}" in
    init)
        init
        ;;
    push)
        push
        ;;
    pull)
        pull
        ;;
    reset)
        reset
        ;;
    diff)
        diff
        ;;
    apply-diff)
        apply_diff "$@"
        ;;
    offline-sync)
        sync_offline "${2:-both}"
        ;;
    libsql-sync)
        libsql_sync "${2:-$WORKING_DB}"
        ;;
    workflow)
        workflow
        ;;
    status)
        status
        ;;
    *)
        usage
        exit 1
        ;;
esac 