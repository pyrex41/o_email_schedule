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
    local db_path="${1:-$REPLICA_DB}"
    print_info "Performing bidirectional sync using libSQL sync..."
    
    check_env
    build_rust
    
    if [ ! -f "$db_path" ]; then
        print_warn "Database not found, will be created during sync."
    fi
    
    print_info "Running libSQL bidirectional sync for $db_path..."
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

# Initialize workflow (initial setup, then manual syncs)
workflow() {
    print_info "Setting up Turso sync workflow (manual sync mode)..."
    
    check_env
    build_rust
    
    print_info "Running initial setup..."
    $RUST_BINARY workflow --replica-path "$REPLICA_DB" --working-path "$WORKING_DB"
    
    print_info "🎉 Workflow setup complete!"
    print_info ""
    print_info "💡 Next steps - choose your sync approach:"
    print_info "  • Recommended: ./turso-workflow.sh libsql-sync"
    print_info "  • Legacy:      ./turso-workflow.sh push (after making changes)"
    print_info "  • Advanced:    ./turso-workflow.sh apply-diff (after creating diff)"
}

# Initialize using dump-based workflow (recommended for broken embedded replicas)
dump_init() {
    print_info "Initializing using dump-based workflow (no embedded replica)..."
    
    check_env
    build_rust
    
    print_info "Dumping remote database and creating local copy..."
    $RUST_BINARY dump-init --db-path "$WORKING_DB"
    
    print_info "✅ Dump-based initialization complete!"
    print_info "Your OCaml code can now use: $WORKING_DB"
    print_info "Run './turso-workflow.sh dump-push' when ready to sync changes back"
}

# Push changes using dump-based workflow with batched execution
dump_push() {
    print_info "Pushing changes using dump-based workflow with smart optimization..."
    
    check_env
    build_rust
    
    if [ ! -f "$WORKING_DB" ]; then
        print_error "Working copy not found. Run './turso-workflow.sh dump-init' first."
        exit 1
    fi
    
    if [ ! -f "baseline.db" ]; then
        print_error "Baseline database not found. Run './turso-workflow.sh dump-init' first."
        exit 1
    fi
    
    # Step 1: Generate diff to check what changed
    print_info "Generating diff between baseline and working copy..."
    local start_time=$(date +%s.%N)
    
    sqldiff --transaction baseline.db "$WORKING_DB" > "$DIFF_FILE"
    
    local diff_size=$(wc -c < "$DIFF_FILE")
    local end_time=$(date +%s.%N)
    local diff_duration
    if check_bc; then
        diff_duration=$(echo "$end_time - $start_time" | bc -l)
        diff_duration=$(printf "%.3f" "$diff_duration")
    else
        diff_duration="<1"
    fi
    
    print_info "📊 Diff generated in ${diff_duration}s - Size: $diff_size bytes"
    
    # Step 2: Check if there are real changes (more than just BEGIN/COMMIT)
    if [ "$diff_size" -le 50 ]; then
        # Check if it's just an empty transaction
        if grep -q "^BEGIN TRANSACTION;$" "$DIFF_FILE" && grep -q "^COMMIT;$" "$DIFF_FILE"; then
            local line_count=$(wc -l < "$DIFF_FILE")
            if [ "$line_count" -le 3 ]; then
                print_info "✅ No changes detected - databases are identical!"
                print_info "🚀 Smart update optimization working perfectly"
                print_info "💡 Skipping upload to Turso (no changes to sync)"
                return 0
            fi
        fi
    fi
    
    # Step 3: There are real changes, proceed with upload
    print_info "📤 Changes detected - proceeding with upload to Turso..."
    
    # Show some stats about what's changing
    local delete_count=$(grep -c "DELETE FROM" "$DIFF_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    local insert_count=$(grep -c "INSERT INTO" "$DIFF_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    local update_count=$(grep -c "UPDATE " "$DIFF_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    local create_count=$(grep -c "CREATE " "$DIFF_FILE" 2>/dev/null | tr -d '\n' || echo "0")
    
    # Ensure counts are integers (fallback to 0 if parsing fails)
    delete_count=${delete_count:-0}
    insert_count=${insert_count:-0}
    update_count=${update_count:-0}
    create_count=${create_count:-0}
    
    if [ "$delete_count" -gt 0 ] 2>/dev/null || [ "$insert_count" -gt 0 ] 2>/dev/null || [ "$update_count" -gt 0 ] 2>/dev/null || [ "$create_count" -gt 0 ] 2>/dev/null; then
        print_info "📈 Change summary:"
        [ "$create_count" -gt 0 ] 2>/dev/null && print_info "   • CREATE statements: $create_count"
        [ "$delete_count" -gt 0 ] 2>/dev/null && print_info "   • DELETE statements: $delete_count"  
        [ "$insert_count" -gt 0 ] 2>/dev/null && print_info "   • INSERT statements: $insert_count"
        [ "$update_count" -gt 0 ] 2>/dev/null && print_info "   • UPDATE statements: $update_count"
    fi
    
    # Step 4: Apply changes to Turso with timing
    print_info "⏱️  Applying changes to Turso with optimized batching..."
    local upload_start=$(date +%s.%N)
    
    $RUST_BINARY dump-push --db-path "$WORKING_DB" --diff-file "$DIFF_FILE"
    
    local upload_end=$(date +%s.%N)
    local upload_duration
    if check_bc; then
        upload_duration=$(echo "$upload_end - $upload_start" | bc -l)
        upload_duration=$(printf "%.3f" "$upload_duration")
    else
        upload_duration="<measurement unavailable>"
    fi
    
    print_info "✅ Changes successfully uploaded to Turso in ${upload_duration}s"
    print_info "🎯 Total workflow time: diff generation (${diff_duration}s) + upload (${upload_duration}s)"
    print_info "💡 Next time: if no changes are made, upload will be skipped entirely!"
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
    
    if [ -f "baseline.db" ]; then
        echo "📄 Baseline database: baseline.db ($(du -h "baseline.db" | cut -f1))"
    else
        echo "📄 Baseline database: baseline.db (not found)"
    fi
    
    if [ -f "original_dump.sql" ]; then
        echo "💾 Original dump: original_dump.sql ($(du -h "original_dump.sql" | cut -f1))"
    else
        echo "💾 Original dump: original_dump.sql (not found)"
    fi
    
    echo "=================="
    
    if command -v sqldiff &> /dev/null; then
        echo "✅ sqldiff: available"
    else
        echo "❌ sqldiff: not found"
    fi
    
    if command -v sqlite3 &> /dev/null; then
        echo "✅ sqlite3: available"
    else
        echo "❌ sqlite3: not found"
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
    echo "  Recommended: dump-init, dump-push"
    echo "  Legacy: init, push, pull, reset, diff"
    echo "  Advanced: apply-diff, offline-sync, libsql-sync"
    echo "  Other: workflow, status"
}

# Usage information
usage() {
    echo "Turso Sync Workflow Script"
    echo ""
    echo "Usage: $0 {dump-init|dump-push|init|push|pull|reset|diff|apply-diff|offline-sync|workflow|status}"
    echo ""
    echo "🔥 RECOMMENDED COMMANDS (for broken embedded replicas):"
    echo "  dump-init   - Initialize: dump remote DB and create local SQLite (no replica)"
    echo "  dump-push   - Push local changes using dump-based workflow with smart optimization"
    echo "              ✨ NEW: Automatically skips upload when no changes detected!"
    echo "              ⚡ Optimized for OCaml smart update - minimal diffs when unchanged"
    echo ""
    echo "Legacy commands:"
    echo "  init        - Initialize: sync from Turso and create working copy"
    echo "  push        - Push local changes to Turso using sqldiff (legacy method)"
    echo "  pull        - Pull latest changes from Turso (preserves local changes)"
    echo "  reset       - Reset working copy to match Turso (discards local changes)"
    echo "  diff        - Show differences between working copy and replica"
    echo "  apply-diff  - Apply diff file to local replica and sync to Turso (uses offline sync)"
    echo "              Use --no-sync to skip syncing to Turso after applying diff"
    echo "  offline-sync [direction] - Sync using offline sync capabilities"
    echo "              direction: pull, push, or both (default: both)"
    echo "  libsql-sync [db-path]   - Bidirectional sync using libSQL sync"
    echo "              db-path: path to database file (default: local_replica.db)"
    echo "  workflow    - Initialize workflow: setup databases for manual syncing"
    echo "  status      - Show current status of databases and tools"
    echo ""
    echo "Environment variables required:"
    echo "  TURSO_DATABASE_URL - Your Turso database URL"
    echo "  TURSO_AUTH_TOKEN   - Your Turso authentication token"
    echo ""
    echo "Example workflows:"
    echo ""
    echo "🚀 RECOMMENDED: Dump-based workflow (for broken embedded replicas):"
    echo "  1. ./turso-workflow.sh dump-init      # Download and create local DB"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh dump-push      # Push changes with smart optimization"
    echo "     💡 Smart features:"
    echo "       • Skips upload when no changes detected (saves time & bandwidth)"
    echo "       • Shows detailed change statistics (CREATE/DELETE/INSERT/UPDATE counts)"  
    echo "       • Optimized for OCaml smart update - minimal diffs when data unchanged"
    echo ""
    echo "Quick setup workflow (may not work with broken replicas):"
    echo "  1. ./turso-workflow.sh workflow          # Initial setup"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh libsql-sync       # Sync changes"
    echo ""
    echo "Legacy workflow (using replica sync):"
    echo "  1. ./turso-workflow.sh init     # Initial setup"
    echo "  2. # Run your OCaml application (uses working_copy.db)"
    echo "  3. ./turso-workflow.sh diff     # Check what changed"
    echo "  4. ./turso-workflow.sh push     # Push changes to Turso"
    echo ""
    echo "Advanced workflows:"
    echo "  Manual libSQL sync:"
    echo "    1. ./turso-workflow.sh libsql-sync         # Bidirectional sync with Turso"
    echo "    2. # Run your OCaml application (uses working_copy.db)"
    echo "    3. ./turso-workflow.sh libsql-sync         # Sync changes back to Turso"
    echo ""
    echo "  Alternative offline sync:"
    echo "    1. ./turso-workflow.sh offline-sync pull    # Pull from Turso"
    echo "    2. # Run your OCaml application (uses working_copy.db)"  
    echo "    3. ./turso-workflow.sh diff                 # Check what changed"
    echo "    4. ./turso-workflow.sh apply-diff          # Apply diff and sync to Turso"
    echo "       OR"
    echo "    4. ./turso-workflow.sh apply-diff --no-sync # Apply diff locally only (see timing)"
    echo "    5. ./turso-workflow.sh offline-sync push   # Push all changes to Turso"
}

# Main script logic
case "${1:-}" in
    dump-init)
        dump_init
        ;;
    dump-push)
        dump_push
        ;;
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
        libsql_sync "${2:-$REPLICA_DB}"
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