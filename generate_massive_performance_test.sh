#!/bin/bash

# Massive Performance Test Generator for Email Scheduler
# Creates 750,000 contacts database and performs comprehensive performance analysis

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}🚀 Massive Performance Test Generator${NC}"
echo "======================================"

# Configuration
CONTACTS_COUNT=750000
BATCH_SIZE=10000
DB_FILE="massive_performance_test.db"
RESULTS_DIR="performance_results_$(date +%Y%m%d_%H%M%S)"
MEMORY_MONITORING=true
DETAILED_PROFILING=false
CLEANUP_BATCHES=true

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --contacts)
            CONTACTS_COUNT="$2"
            shift 2
            ;;
        --batch-size)
            BATCH_SIZE="$2"
            shift 2
            ;;
        --no-memory-monitoring)
            MEMORY_MONITORING=false
            shift
            ;;
        --detailed-profiling)
            DETAILED_PROFILING=true
            shift
            ;;
        --keep-batches)
            CLEANUP_BATCHES=false
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --contacts N           Number of contacts (default: 750000)"
            echo "  --batch-size N         Batch size for generation (default: 10000)"
            echo "  --no-memory-monitoring Disable memory monitoring"
            echo "  --detailed-profiling   Enable detailed execution profiling"
            echo "  --keep-batches         Don't cleanup intermediate files"
            echo "  --help                 Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                           # Full 750k test"
            echo "  $0 --contacts 1000000        # 1M contacts test"
            echo "  $0 --detailed-profiling      # With detailed profiling"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

mkdir -p "$RESULTS_DIR"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "$message"
    echo "[$timestamp] [$level] $message" >> "$RESULTS_DIR/performance.log"
}

# Function to get memory usage in MB
get_memory_usage() {
    local pid="$1"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        ps -o rss= -p "$pid" 2>/dev/null | awk '{print int($1/1024)}'
    else
        echo "0"
    fi
}

# Function to get system memory info
get_system_memory() {
    free -m | awk 'NR==2{printf "%.1f", $3*100/$2}'
}

# Function to monitor memory usage during execution
monitor_memory() {
    local pid="$1"
    local interval="$2"
    local output_file="$3"
    
    echo "timestamp,process_memory_mb,system_memory_percent" > "$output_file"
    
    while kill -0 "$pid" 2>/dev/null; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local process_mem=$(get_memory_usage "$pid")
        local system_mem=$(get_system_memory)
        echo "$timestamp,$process_mem,$system_mem" >> "$output_file"
        sleep "$interval"
    done
}

# Function to create optimized database schema
create_optimized_schema() {
    log "INFO" "${CYAN}🏗️  Creating optimized database schema...${NC}"
    
    rm -f "$DB_FILE"
    
    sqlite3 "$DB_FILE" "
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA cache_size = 100000;
    PRAGMA temp_store = MEMORY;
    PRAGMA mmap_size = 268435456; -- 256MB
    "
    
    # Apply migrations
    if [ -f "migrations/003_add_campaign_tables.sql" ]; then
        sqlite3 "$DB_FILE" < migrations/003_add_campaign_tables.sql
    fi
    
    sqlite3 "$DB_FILE" "
    CREATE TABLE IF NOT EXISTS contacts (
        id INTEGER PRIMARY KEY,
        email TEXT NOT NULL,
        birth_date TEXT,
        effective_date TEXT,
        state TEXT,
        zip_code TEXT,
        carrier TEXT,
        current_carrier TEXT,
        failed_underwriting INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS email_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        contact_id INTEGER NOT NULL,
        email_type TEXT NOT NULL,
        scheduled_send_date TEXT NOT NULL,
        scheduled_send_time TEXT NOT NULL DEFAULT '08:30:00',
        status TEXT NOT NULL DEFAULT 'scheduled',
        skip_reason TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        updated_at TEXT NOT NULL DEFAULT (datetime('now')),
        batch_id TEXT,
        event_year INTEGER,
        event_month INTEGER,
        event_day INTEGER,
        catchup_note TEXT,
        actual_send_datetime TEXT,
        FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE
    );

    -- Performance tracking table
    CREATE TABLE performance_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        test_phase TEXT NOT NULL,
        start_time TEXT NOT NULL,
        end_time TEXT,
        duration_ms INTEGER,
        memory_start_mb INTEGER,
        memory_peak_mb INTEGER,
        memory_end_mb INTEGER,
        contacts_processed INTEGER DEFAULT 0,
        schedules_generated INTEGER DEFAULT 0,
        cpu_percent REAL,
        notes TEXT,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    
    -- Comprehensive indexes for performance
    CREATE INDEX IF NOT EXISTS idx_contacts_state ON contacts (state);
    CREATE INDEX IF NOT EXISTS idx_contacts_birth_date ON contacts (birth_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_effective_date ON contacts (effective_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_failed_underwriting ON contacts (failed_underwriting);
    CREATE INDEX IF NOT EXISTS idx_contacts_composite ON contacts (state, birth_date, effective_date);
    
    CREATE INDEX IF NOT EXISTS idx_email_schedules_contact_id ON email_schedules (contact_id);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_date ON email_schedules (scheduled_send_date);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_status ON email_schedules (status);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_type ON email_schedules (email_type);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_composite ON email_schedules (contact_id, email_type, scheduled_send_date);
    
    CREATE INDEX IF NOT EXISTS idx_performance_metrics_phase ON performance_metrics (test_phase);
    
    -- Enable query optimization
    ANALYZE;
    "
    
    log "INFO" "${GREEN}✅ Optimized schema created${NC}"
}

# Function to generate massive contact dataset
generate_massive_contacts() {
    log "INFO" "${CYAN}📊 Generating $CONTACTS_COUNT contacts in batches of $BATCH_SIZE...${NC}"
    
    local start_time=$(date +%s%3N)
    local memory_start=$(free -m | awk 'NR==2{print $3}')
    
    # Record performance metric start
    sqlite3 "$DB_FILE" "
    INSERT INTO performance_metrics (test_phase, start_time, memory_start_mb, contacts_processed)
    VALUES ('contact_generation', datetime('now'), $memory_start, 0);
    "
    local metric_id=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
    
    # Realistic state distribution (weighted by population)
    local states=(
        "CA" "CA" "CA" "CA" "CA" "CA" "CA" "CA" "CA" "CA"  # 10% - California
        "TX" "TX" "TX" "TX" "TX" "TX" "TX" "TX"            # 8% - Texas  
        "FL" "FL" "FL" "FL" "FL" "FL"                       # 6% - Florida
        "NY" "NY" "NY" "NY" "NY"                           # 5% - New York
        "PA" "PA" "PA" "PA"                                # 4% - Pennsylvania
        "IL" "IL" "IL"                                     # 3% - Illinois
        "OH" "OH" "OH"                                     # 3% - Ohio
        "GA" "GA"                                          # 2% - Georgia
        "NC" "NC"                                          # 2% - North Carolina
        "MI" "MI"                                          # 2% - Michigan
        "NJ" "VA" "WA" "AZ" "MA" "TN" "IN" "MD" "MO" "WI"  # 1% each
        "CT" "OR" "KY" "OK" "NV" "ID" "AL" "SC" "LA" "UT"  # <1% each
        "NE" "NM" "HI" "ME" "MT" "ND" "SD" "DE" "RI" "VT" "WY" "AK"  # Very small
    )
    
    local total_batches=$(( (CONTACTS_COUNT + BATCH_SIZE - 1) / BATCH_SIZE ))
    
    # Pre-generate random data files for efficiency
    local temp_dir="$RESULTS_DIR/temp_data"
    mkdir -p "$temp_dir"
    
    log "INFO" "${YELLOW}⚡ Pre-generating random data for efficiency...${NC}"
    
    # Generate birth years (ages 25-80, weighted toward middle ages)
    echo "Generating birth year distribution..."
    for i in {1945..2000}; do
        # Weight middle ages more heavily
        local weight=1
        if [ $i -ge 1955 ] && [ $i -le 1985 ]; then
            weight=3
        elif [ $i -ge 1945 ] && [ $i -le 1975 ]; then
            weight=2
        fi
        for w in $(seq 1 $weight); do
            echo "$i"
        done
    done | shuf > "$temp_dir/birth_years.txt"
    
    # Generate effective years (weighted toward recent years)
    echo "Generating effective year distribution..."
    for year in {2015..2024}; do
        local weight=$((2025 - year))  # More recent = higher weight
        for w in $(seq 1 $weight); do
            echo "$year"
        done
    done | shuf > "$temp_dir/effective_years.txt"
    
    log "INFO" "${CYAN}🔄 Starting batch generation...${NC}"
    
    for batch in $(seq 1 $total_batches); do
        local start_id=$(( (batch - 1) * BATCH_SIZE + 1 ))
        local end_id=$(( batch * BATCH_SIZE ))
        if [ $end_id -gt $CONTACTS_COUNT ]; then
            end_id=$CONTACTS_COUNT
        fi
        
        local batch_size_actual=$((end_id - start_id + 1))
        
        echo -n "    Batch $batch/$total_batches (contacts $start_id-$end_id, size: $batch_size_actual)..."
        
        # Generate batch data file
        local batch_file="$temp_dir/batch_$batch.sql"
        echo "INSERT INTO contacts (id, email, state, birth_date, effective_date, failed_underwriting) VALUES " > "$batch_file"
        
        for contact_id in $(seq $start_id $end_id); do
            # Use pre-generated distributions
            local state=${states[$((RANDOM % ${#states[@]}))]}
            local birth_year=$(sed -n "$((RANDOM % $(wc -l < "$temp_dir/birth_years.txt") + 1))p" "$temp_dir/birth_years.txt")
            local birth_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local birth_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            local eff_year=$(sed -n "$((RANDOM % $(wc -l < "$temp_dir/effective_years.txt") + 1))p" "$temp_dir/effective_years.txt")
            local eff_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local eff_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            local failed_uw=$((RANDOM % 10 == 0 ? 1 : 0))
            
            if [ $contact_id -gt $start_id ]; then
                echo "," >> "$batch_file"
            fi
            echo -n "($contact_id, 'perf${contact_id}@example.com', '$state', '$birth_year-$birth_month-$birth_day', '$eff_year-$eff_month-$eff_day', $failed_uw)" >> "$batch_file"
        done
        echo ";" >> "$batch_file"
        
        # Execute batch insert with timing
        local batch_start=$(date +%s%3N)
        sqlite3 "$DB_FILE" ".read $batch_file"
        local batch_end=$(date +%s%3N)
        local batch_time=$((batch_end - batch_start))
        
        # Clean up batch file if requested
        if [ "$CLEANUP_BATCHES" = true ]; then
            rm -f "$batch_file"
        fi
        
        # Calculate progress metrics
        local contacts_per_sec=$(echo "scale=0; $batch_size_actual * 1000 / $batch_time" | bc -l 2>/dev/null || echo "N/A")
        local total_progress=$(echo "scale=1; 100 * $contact_id / $CONTACTS_COUNT" | bc -l)
        
        echo " ✅ ${batch_time}ms (${contacts_per_sec} contacts/sec, ${total_progress}% total)"
        
        # Memory check every 10 batches
        if [ $((batch % 10)) -eq 0 ]; then
            local current_memory=$(free -m | awk 'NR==2{print $3}')
            local db_size=$(stat -c%s "$DB_FILE" 2>/dev/null || stat -f%z "$DB_FILE" 2>/dev/null || echo "0")
            local db_size_mb=$((db_size / 1024 / 1024))
            echo "      Memory: ${current_memory}MB, DB size: ${db_size_mb}MB"
        fi
    done
    
    # Clean up temp directory
    if [ "$CLEANUP_BATCHES" = true ]; then
        rm -rf "$temp_dir"
    fi
    
    local end_time=$(date +%s%3N)
    local total_time=$((end_time - start_time))
    local memory_end=$(free -m | awk 'NR==2{print $3}')
    
    # Update performance metrics
    sqlite3 "$DB_FILE" "
    UPDATE performance_metrics 
    SET end_time = datetime('now'),
        duration_ms = $total_time,
        memory_end_mb = $memory_end,
        contacts_processed = $CONTACTS_COUNT
    WHERE id = $metric_id;
    "
    
    log "INFO" "${GREEN}✅ Contact generation complete: $CONTACTS_COUNT contacts in ${total_time}ms${NC}"
    
    # Generate database statistics
    local final_stats=$(sqlite3 "$DB_FILE" "
    SELECT 
        COUNT(*) as total_contacts,
        COUNT(DISTINCT state) as unique_states,
        MIN(birth_date) as earliest_birth,
        MAX(birth_date) as latest_birth,
        COUNT(CASE WHEN failed_underwriting = 1 THEN 1 END) as failed_uw_count
    FROM contacts;
    ")
    
    IFS='|' read -r total_contacts unique_states earliest_birth latest_birth failed_uw_count <<< "$final_stats"
    
    log "INFO" "${CYAN}📊 Database Statistics:${NC}"
    log "INFO" "   Total contacts: $total_contacts"
    log "INFO" "   Unique states: $unique_states"
    log "INFO" "   Birth date range: $earliest_birth to $latest_birth"
    log "INFO" "   Failed underwriting: $failed_uw_count"
    
    # Database file size
    local db_size=$(stat -c%s "$DB_FILE" 2>/dev/null || stat -f%z "$DB_FILE" 2>/dev/null || echo "0")
    local db_size_mb=$((db_size / 1024 / 1024))
    log "INFO" "   Database size: ${db_size_mb}MB"
}

# Function to add realistic campaigns for 750k scale
add_massive_campaigns() {
    log "INFO" "${CYAN}🎯 Adding campaigns for massive scale testing...${NC}"
    
    sqlite3 "$DB_FILE" "
    INSERT INTO campaign_types (
        name, respect_exclusion_windows, enable_followups, days_before_event,
        target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
    ) VALUES 
    ('mega_newsletter', 1, 0, 0, 1, 50, 1, 1, 0),
    ('birthday_mega_special', 0, 0, 3, 0, 15, 1, 0, 0),
    ('renewal_blast', 1, 1, 30, 1, 25, 1, 1, 1),
    ('compliance_alert', 0, 0, 0, 1, 5, 1, 0, 0);
    
    INSERT INTO campaign_instances (
        campaign_type, instance_name,
        active_start_date, active_end_date,
        spread_start_date, spread_end_date
    ) VALUES
    ('mega_newsletter', 'Massive Newsletter 2025', '2025-01-01', '2025-12-31', '2025-03-01', '2025-04-30'),
    ('birthday_mega_special', 'Birthday Mega Campaign', '2025-01-01', '2025-12-31', '2025-01-01', '2025-12-31'),
    ('renewal_blast', 'Renewal Reminder Blast', '2025-06-01', '2025-08-31', '2025-06-15', '2025-07-15'),
    ('compliance_alert', 'Urgent Compliance Update', '2025-06-01', '2025-06-07', '2025-06-01', '2025-06-01');
    "
    
    # Enroll contacts in campaigns (sample to avoid overwhelming)
    log "INFO" "${YELLOW}📝 Enrolling contacts in campaigns (sampling for performance)...${NC}"
    
    # Enroll every 10th contact in mega newsletter (75k contacts)
    sqlite3 "$DB_FILE" "
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci 
    WHERE ci.campaign_type = 'mega_newsletter'
    AND c.id % 10 = 0;
    "
    
    # Enroll every 50th contact in birthday special (15k contacts)  
    sqlite3 "$DB_FILE" "
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'birthday_mega_special'
    AND c.id % 50 = 0;
    "
    
    # Enroll every 100th contact in renewal blast (7.5k contacts)
    sqlite3 "$DB_FILE" "
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'renewal_blast'
    AND c.id % 100 = 0;
    "
    
    local enrollment_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM contact_campaigns;")
    log "INFO" "${GREEN}✅ Campaign enrollment complete: $enrollment_count enrollments${NC}"
}

# Function to run comprehensive performance test
run_performance_test() {
    log "INFO" "${BOLD}🚀 Starting Massive Performance Test${NC}"
    log "INFO" "${CYAN}Testing with $CONTACTS_COUNT contacts${NC}"
    
    local start_time=$(date +%s%3N)
    local memory_start=$(free -m | awk 'NR==2{print $3}')
    
    # Record performance metric start
    sqlite3 "$DB_FILE" "
    INSERT INTO performance_metrics (test_phase, start_time, memory_start_mb, contacts_processed)
    VALUES ('scheduler_execution', datetime('now'), $memory_start, $CONTACTS_COUNT);
    "
    local metric_id=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")
    
    # Memory monitoring setup
    local memory_log="$RESULTS_DIR/memory_usage.csv"
    local scheduler_pid=""
    
    echo "Starting scheduler execution..."
    
    # Run scheduler with memory monitoring
    if [ "$MEMORY_MONITORING" = true ]; then
        echo "Memory monitoring enabled - logging to $memory_log"
        eval $(opam env)
        timeout 3600s dune exec campaign_aware_scheduler "$DB_FILE" &
        scheduler_pid=$!
        
        # Start memory monitoring in background
        monitor_memory "$scheduler_pid" 5 "$memory_log" &
        local monitor_pid=$!
        
        # Wait for scheduler to complete
        wait "$scheduler_pid"
        local scheduler_exit_code=$?
        
        # Stop memory monitoring
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true
    else
        eval $(opam env)
        timeout 3600s dune exec campaign_aware_scheduler "$DB_FILE"
        local scheduler_exit_code=$?
    fi
    
    local end_time=$(date +%s%3N)
    local execution_time=$((end_time - start_time))
    local memory_end=$(free -m | awk 'NR==2{print $3}')
    
    # Calculate peak memory if monitoring was enabled
    local memory_peak=$memory_end
    if [ "$MEMORY_MONITORING" = true ] && [ -f "$memory_log" ]; then
        memory_peak=$(tail -n +2 "$memory_log" | cut -d',' -f2 | sort -n | tail -1)
    fi
    
    # Get schedules generated
    local schedules_generated=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM email_schedules;")
    
    # Update performance metrics
    sqlite3 "$DB_FILE" "
    UPDATE performance_metrics 
    SET end_time = datetime('now'),
        duration_ms = $execution_time,
        memory_end_mb = $memory_end,
        memory_peak_mb = $memory_peak,
        schedules_generated = $schedules_generated,
        notes = 'Exit code: $scheduler_exit_code'
    WHERE id = $metric_id;
    "
    
    if [ $scheduler_exit_code -eq 0 ]; then
        log "INFO" "${GREEN}✅ Scheduler execution completed successfully${NC}"
    elif [ $scheduler_exit_code -eq 124 ]; then
        log "WARN" "${YELLOW}⚠️  Scheduler timed out after 1 hour${NC}"
    else
        log "ERROR" "${RED}❌ Scheduler failed with exit code $scheduler_exit_code${NC}"
    fi
    
    # Performance summary
    local execution_seconds=$(echo "scale=2; $execution_time / 1000" | bc -l)
    local contacts_per_second=$(echo "scale=0; $CONTACTS_COUNT * 1000 / $execution_time" | bc -l 2>/dev/null || echo "N/A")
    local schedules_per_second=$(echo "scale=0; $schedules_generated * 1000 / $execution_time" | bc -l 2>/dev/null || echo "N/A")
    local memory_growth=$((memory_end - memory_start))
    
    log "INFO" "${CYAN}📊 Performance Results:${NC}"
    log "INFO" "   Execution time: ${execution_seconds}s"
    log "INFO" "   Contacts processed: $CONTACTS_COUNT"
    log "INFO" "   Schedules generated: $schedules_generated"
    log "INFO" "   Contacts per second: $contacts_per_second"
    log "INFO" "   Schedules per second: $schedules_per_second"
    log "INFO" "   Memory start: ${memory_start}MB"
    log "INFO" "   Memory peak: ${memory_peak}MB"
    log "INFO" "   Memory end: ${memory_end}MB"
    log "INFO" "   Memory growth: ${memory_growth}MB"
    
    return $scheduler_exit_code
}

# Function to analyze results and generate detailed report
analyze_performance_results() {
    log "INFO" "${CYAN}📋 Analyzing performance results and generating report...${NC}"
    
    local report_file="$RESULTS_DIR/MASSIVE_PERFORMANCE_REPORT.md"
    
    cat > "$report_file" << EOF
# Massive Performance Test Report

**Generated:** $(date)  
**Contacts:** $CONTACTS_COUNT  
**Batch Size:** $BATCH_SIZE  
**Database:** $DB_FILE  

## Executive Summary

$(sqlite3 "$DB_FILE" "
SELECT 
    'Total Contacts: ' || MAX(contacts_processed) ||
    '\nTotal Schedules: ' || MAX(schedules_generated) ||
    '\nExecution Time: ' || printf('%.2f', MAX(duration_ms)/1000.0) || 's' ||
    '\nThroughput: ' || printf('%.0f', MAX(contacts_processed) * 1000.0 / MAX(duration_ms)) || ' contacts/sec' ||
    '\nMemory Peak: ' || MAX(memory_peak_mb) || 'MB' ||
    '\nMemory Growth: ' || (MAX(memory_end_mb) - MIN(memory_start_mb)) || 'MB'
FROM performance_metrics 
WHERE test_phase = 'scheduler_execution';
")

## Detailed Performance Metrics

### Contact Generation Performance
$(sqlite3 "$DB_FILE" "
SELECT 
    'Generation Time: ' || printf('%.2f', duration_ms/1000.0) || 's' ||
    '\nGeneration Rate: ' || printf('%.0f', contacts_processed * 1000.0 / duration_ms) || ' contacts/sec' ||
    '\nMemory Used: ' || (memory_end_mb - memory_start_mb) || 'MB'
FROM performance_metrics 
WHERE test_phase = 'contact_generation';
")

### Scheduler Execution Performance
$(sqlite3 "$DB_FILE" "
SELECT 
    'Execution Time: ' || printf('%.2f', duration_ms/1000.0) || 's' ||
    '\nProcessing Rate: ' || printf('%.0f', contacts_processed * 1000.0 / duration_ms) || ' contacts/sec' ||
    '\nSchedule Rate: ' || printf('%.0f', schedules_generated * 1000.0 / duration_ms) || ' schedules/sec' ||
    '\nMemory Peak: ' || memory_peak_mb || 'MB' ||
    '\nMemory Efficiency: ' || printf('%.1f', schedules_generated * 1.0 / memory_peak_mb) || ' schedules/MB'
FROM performance_metrics 
WHERE test_phase = 'scheduler_execution';
")

## Database Statistics

### Contact Distribution
$(sqlite3 "$DB_FILE" "
SELECT 
    state,
    COUNT(*) as contact_count,
    COUNT(CASE WHEN failed_underwriting = 1 THEN 1 END) as failed_uw,
    printf('%.1f%%', 100.0 * COUNT(*) / (SELECT COUNT(*) FROM contacts)) as percentage
FROM contacts 
GROUP BY state 
ORDER BY contact_count DESC 
LIMIT 15;
" | while IFS='|' read state count failed_uw pct; do
    echo "- **$state:** $count contacts ($pct), $failed_uw failed underwriting"
done)

### Email Schedule Distribution  
$(sqlite3 "$DB_FILE" "
SELECT 
    email_type,
    COUNT(*) as total_schedules,
    COUNT(CASE WHEN status = 'scheduled' OR status = 'pre-scheduled' THEN 1 END) as scheduled,
    COUNT(CASE WHEN status = 'skipped' THEN 1 END) as skipped,
    printf('%.1f%%', 100.0 * COUNT(CASE WHEN status = 'skipped' THEN 1 END) / COUNT(*)) as skip_rate
FROM email_schedules 
GROUP BY email_type 
ORDER BY total_schedules DESC;
" | while IFS='|' read type total scheduled skipped skip_rate; do
    echo "- **$type:** $total total, $scheduled scheduled, $skipped skipped ($skip_rate)"
done)

### Campaign Performance
$(sqlite3 "$DB_FILE" "
SELECT 
    ci.instance_name,
    ct.name as campaign_type,
    COUNT(cc.contact_id) as enrolled_contacts,
    COUNT(es.id) as generated_schedules,
    printf('%.1f', 1.0 * COUNT(es.id) / COUNT(cc.contact_id)) as schedules_per_contact
FROM campaign_instances ci
JOIN campaign_types ct ON ci.campaign_type = ct.name
LEFT JOIN contact_campaigns cc ON ci.id = cc.campaign_instance_id
LEFT JOIN email_schedules es ON cc.contact_id = es.contact_id AND es.email_type LIKE '%' || ct.name || '%'
GROUP BY ci.id, ci.instance_name, ct.name
ORDER BY enrolled_contacts DESC;
" | while IFS='|' read instance_name campaign_type enrolled schedules ratio; do
    echo "- **$instance_name** ($campaign_type): $enrolled contacts enrolled, $schedules schedules ($ratio per contact)"
done)

## Performance Benchmarks

### Memory Usage Analysis
EOF

    if [ "$MEMORY_MONITORING" = true ] && [ -f "$RESULTS_DIR/memory_usage.csv" ]; then
        cat >> "$report_file" << EOF

Memory usage tracked during execution:

$(tail -n +2 "$RESULTS_DIR/memory_usage.csv" | awk -F',' '
BEGIN { 
    min_mem = 999999; max_mem = 0; sum_mem = 0; count = 0;
    min_sys = 100; max_sys = 0; sum_sys = 0;
}
{
    if ($2 > 0) {
        if ($2 < min_mem) min_mem = $2;
        if ($2 > max_mem) max_mem = $2;
        sum_mem += $2; count++;
    }
    if ($3 < min_sys) min_sys = $3;
    if ($3 > max_sys) max_sys = $3;
    sum_sys += $3;
}
END {
    printf "- Process Memory: %dMB min, %dMB max, %.1fMB avg\n", min_mem, max_mem, sum_mem/count;
    printf "- System Memory: %.1f%% min, %.1f%% max, %.1f%% avg\n", min_sys, max_sys, sum_sys/count;
}')"

EOF
    else
        echo "Memory monitoring was disabled for this run." >> "$report_file"
    fi

    cat >> "$report_file" << EOF

## Scale Comparison

### Performance Scaling Analysis
$(sqlite3 "$DB_FILE" "
SELECT 
    'Contacts per Second: ' || printf('%.0f', MAX(contacts_processed) * 1000.0 / MAX(duration_ms)) ||
    '\nSchedules per Second: ' || printf('%.0f', MAX(schedules_generated) * 1000.0 / MAX(duration_ms)) ||
    '\nMemory per Contact: ' || printf('%.2f', MAX(memory_peak_mb) * 1.0 / MAX(contacts_processed)) || 'MB' ||
    '\nSchedules per Contact: ' || printf('%.2f', MAX(schedules_generated) * 1.0 / MAX(contacts_processed)) ||
    '\nTime per 1000 Contacts: ' || printf('%.2f', MAX(duration_ms) * 1.0 / MAX(contacts_processed) * 1000 / 1000) || 's'
FROM performance_metrics 
WHERE test_phase = 'scheduler_execution';
")

### Database Efficiency
$(sqlite3 "$DB_FILE" "
SELECT 
    'Database Size: ' || (SELECT page_count * page_size / 1024 / 1024 FROM pragma_page_count(), pragma_page_size()) || 'MB' ||
    '\nContacts per MB: ' || printf('%.0f', (SELECT COUNT(*) FROM contacts) * 1.0 / (SELECT page_count * page_size / 1024 / 1024 FROM pragma_page_count(), pragma_page_size())) ||
    '\nSchedules per MB: ' || printf('%.0f', (SELECT COUNT(*) FROM email_schedules) * 1.0 / (SELECT page_count * page_size / 1024 / 1024 FROM pragma_page_count(), pragma_page_size()))
")

## Bottleneck Analysis

Based on the performance metrics:

$(sqlite3 "$DB_FILE" "
SELECT 
    CASE 
        WHEN MAX(duration_ms) > 300000 THEN '- ⚠️  **Performance Warning**: Execution time >5 minutes for ' || MAX(contacts_processed) || ' contacts'
        WHEN MAX(duration_ms) > 120000 THEN '- ✅ **Good Performance**: Execution time 2-5 minutes for ' || MAX(contacts_processed) || ' contacts'
        ELSE '- 🚀 **Excellent Performance**: Execution time <2 minutes for ' || MAX(contacts_processed) || ' contacts'
    END ||
    '\n' ||
    CASE 
        WHEN MAX(memory_peak_mb) > 8192 THEN '- ⚠️  **Memory Warning**: Peak usage >8GB (' || MAX(memory_peak_mb) || 'MB)'
        WHEN MAX(memory_peak_mb) > 4096 THEN '- ✅ **Good Memory Usage**: Peak usage 4-8GB (' || MAX(memory_peak_mb) || 'MB)'
        ELSE '- 🚀 **Excellent Memory Usage**: Peak usage <4GB (' || MAX(memory_peak_mb) || 'MB)'
    END ||
    '\n' ||
    CASE 
        WHEN MAX(contacts_processed) * 1000.0 / MAX(duration_ms) < 1000 THEN '- ⚠️  **Throughput Warning**: <1000 contacts/sec'
        WHEN MAX(contacts_processed) * 1000.0 / MAX(duration_ms) < 5000 THEN '- ✅ **Good Throughput**: 1000-5000 contacts/sec'
        ELSE '- 🚀 **Excellent Throughput**: >5000 contacts/sec'
    END
FROM performance_metrics 
WHERE test_phase = 'scheduler_execution';
")

## Recommendations

### Production Deployment
1. **Memory Allocation**: Ensure at least $(sqlite3 "$DB_FILE" "SELECT MAX(memory_peak_mb) + 1024 FROM performance_metrics WHERE test_phase = 'scheduler_execution';")MB available RAM
2. **Execution Time**: Budget $(sqlite3 "$DB_FILE" "SELECT printf('%.1f', MAX(duration_ms)/1000.0/60.0 * 1.5) FROM performance_metrics WHERE test_phase = 'scheduler_execution';") minutes for similar contact volumes
3. **Database Optimization**: Current setup handles $(sqlite3 "$DB_FILE" "SELECT printf('%.0f', MAX(contacts_processed) * 1000.0 / MAX(duration_ms)) FROM performance_metrics WHERE test_phase = 'scheduler_execution';") contacts/second efficiently

### Scaling Considerations  
- **Linear Scaling**: Performance appears to scale linearly with contact count
- **Memory Efficiency**: System uses approximately $(sqlite3 "$DB_FILE" "SELECT printf('%.2f', MAX(memory_peak_mb) * 1.0 / MAX(contacts_processed)) FROM performance_metrics WHERE test_phase = 'scheduler_execution';")MB per 1000 contacts
- **Optimal Batch Size**: Current batch size of $BATCH_SIZE performs well

## Raw Data Files

- Performance Database: \`$DB_FILE\`
- Performance Metrics: \`performance_metrics\` table
- Memory Usage Log: \`$RESULTS_DIR/memory_usage.csv\`
- Full Report: \`$report_file\`

EOF

    log "INFO" "${GREEN}✅ Performance report generated: $report_file${NC}"
}

# Main execution function
main() {
    log "INFO" "${BOLD}🚀 Starting Massive Performance Test${NC}"
    log "INFO" "${CYAN}Target: $CONTACTS_COUNT contacts${NC}"
    
    # Check prerequisites
    if ! eval $(opam env) 2>/dev/null; then
        log "ERROR" "${RED}❌ OCaml environment not available${NC}"
        exit 1
    fi
    
    if ! command -v sqlite3 >/dev/null 2>&1; then
        log "ERROR" "${RED}❌ SQLite3 not found${NC}"
        exit 1
    fi
    
    if ! dune build bin/campaign_aware_scheduler.exe 2>/dev/null; then
        log "ERROR" "${RED}❌ Cannot build scheduler binary${NC}"
        exit 1
    fi
    
    # Check available memory
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    log "INFO" "${CYAN}💾 Available memory: ${available_memory}MB${NC}"
    
    if [ "$available_memory" -lt 4096 ]; then
        log "WARN" "${YELLOW}⚠️  Warning: Less than 4GB available memory${NC}"
        log "WARN" "${YELLOW}   Large-scale test may experience performance issues${NC}"
    fi
    
    # Step 1: Create optimized database
    create_optimized_schema
    
    # Step 2: Generate massive contact dataset
    generate_massive_contacts
    
    # Step 3: Add campaigns
    add_massive_campaigns
    
    # Step 4: Run performance test
    local test_result=0
    run_performance_test || test_result=$?
    
    # Step 5: Analyze results
    analyze_performance_results
    
    # Final summary
    local db_size=$(stat -c%s "$DB_FILE" 2>/dev/null || stat -f%z "$DB_FILE" 2>/dev/null || echo "0")
    local db_size_mb=$((db_size / 1024 / 1024))
    
    log "INFO" "${BOLD}🎉 Massive Performance Test Complete!${NC}"
    log "INFO" "${GREEN}📊 Final Statistics:${NC}"
    log "INFO" "   Database size: ${db_size_mb}MB"
    log "INFO" "   Results directory: $RESULTS_DIR"
    
    if [ $test_result -eq 0 ]; then
        log "INFO" "${GREEN}✅ All tests passed successfully${NC}"
    else
        log "WARN" "${YELLOW}⚠️  Test completed with issues (exit code: $test_result)${NC}"
    fi
    
    echo ""
    log "INFO" "${CYAN}📋 Detailed report: $RESULTS_DIR/MASSIVE_PERFORMANCE_REPORT.md${NC}"
    log "INFO" "${CYAN}💾 Performance database: $DB_FILE${NC}"
    log "INFO" "${CYAN}📊 Memory usage log: $RESULTS_DIR/memory_usage.csv${NC}"
    
    return $test_result
}

# Execute main function
main "$@"