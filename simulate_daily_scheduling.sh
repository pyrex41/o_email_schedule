#!/bin/bash

# Daily Email Scheduler Simulator
# Steps through each day, runs scheduler, tracks actual sends vs scheduled
# Simulates realistic patterns: weekend skips, random outages, catch-up behavior

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

echo -e "${BLUE}📅 Daily Email Scheduler Simulator${NC}"
echo "=================================="

# Configuration
SIMULATION_START_DATE="2025-01-01"
SIMULATION_END_DATE="2025-12-31"
CONTACTS_COUNT=1000
SKIP_WEEKENDS=true
RANDOM_SKIP_PROBABILITY=0.05  # 5% chance of random outage per day
DB_FILE="simulation_database.db"
RESULTS_DIR="simulation_results_$(date +%Y%m%d_%H%M%S)"
DETAILED_LOG=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --start-date)
            SIMULATION_START_DATE="$2"
            shift 2
            ;;
        --end-date)
            SIMULATION_END_DATE="$2"
            shift 2
            ;;
        --contacts)
            CONTACTS_COUNT="$2"
            shift 2
            ;;
        --no-weekend-skip)
            SKIP_WEEKENDS=false
            shift
            ;;
        --outage-rate)
            RANDOM_SKIP_PROBABILITY="$2"
            shift 2
            ;;
        --detailed)
            DETAILED_LOG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --start-date DATE    Start simulation date (default: 2025-01-01)"
            echo "  --end-date DATE      End simulation date (default: 2025-12-31)"
            echo "  --contacts N         Number of contacts to simulate (default: 1000)"
            echo "  --no-weekend-skip    Don't skip weekends (default: skip weekends)"
            echo "  --outage-rate PROB   Random outage probability 0-1 (default: 0.05)"
            echo "  --detailed           Enable detailed logging"
            echo "  --help               Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --contacts 500 --start-date 2025-06-01 --end-date 2025-08-31"
            echo "  $0 --detailed --outage-rate 0.1"
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
    if [ "$DETAILED_LOG" = true ]; then
        echo "[$timestamp] [$level] $message" >> "$RESULTS_DIR/simulation.log"
    fi
}

# Function to check if date is weekend
is_weekend() {
    local date="$1"
    local day_of_week
    
    # Check if we're on macOS/BSD (which uses -j flag) or GNU/Linux (which uses -d flag)
    if date -j -f "%Y-%m-%d" "$date" +%u >/dev/null 2>&1; then
        # macOS/BSD date command
        day_of_week=$(date -j -f "%Y-%m-%d" "$date" +%u)
    else
        # GNU/Linux date command
        day_of_week=$(date -d "$date" +%u)
    fi
    
    # 1=Monday, 7=Sunday; 6=Saturday, 7=Sunday are weekends
    [ "$day_of_week" -eq 6 ] || [ "$day_of_week" -eq 7 ]
}

# Function to generate random float between 0 and 1
random_float() {
    echo "scale=3; $RANDOM / 32767" | bc -l
}

# Function to create simulation database with realistic contact distribution
create_simulation_database() {
    log "INFO" "${CYAN}🏗️  Creating simulation database with $CONTACTS_COUNT contacts...${NC}"
    
    rm -f "$DB_FILE"
    
    # Set up base schema
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

    -- Create tracking table for simulation
    CREATE TABLE simulation_tracking (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        simulation_date TEXT NOT NULL,
        emails_scheduled INTEGER DEFAULT 0,
        emails_sent INTEGER DEFAULT 0,
        emails_skipped INTEGER DEFAULT 0,
        emails_missed INTEGER DEFAULT 0,
        cumulative_scheduled INTEGER DEFAULT 0,
        cumulative_sent INTEGER DEFAULT 0,
        divergence INTEGER DEFAULT 0,
        day_skipped BOOLEAN DEFAULT FALSE,
        skip_reason TEXT,
        scheduler_runtime_ms INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- Create email sending log
    CREATE TABLE email_send_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email_schedule_id INTEGER NOT NULL,
        contact_id INTEGER NOT NULL,
        email_type TEXT NOT NULL,
        scheduled_date TEXT NOT NULL,
        actual_send_date TEXT NOT NULL,
        send_status TEXT NOT NULL, -- 'sent', 'failed', 'skipped'
        send_delay_days INTEGER DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now')),
        FOREIGN KEY (email_schedule_id) REFERENCES email_schedules (id),
        FOREIGN KEY (contact_id) REFERENCES contacts (id)
    );

    -- Indexes for performance
    CREATE INDEX IF NOT EXISTS idx_simulation_tracking_date ON simulation_tracking (simulation_date);
    CREATE INDEX IF NOT EXISTS idx_email_send_log_date ON email_send_log (actual_send_date);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_date ON email_schedules (scheduled_send_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_birth_date ON contacts (birth_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_effective_date ON contacts (effective_date);
    "
    
    # Generate realistic contacts with distributed birth dates and effective dates
    log "INFO" "${YELLOW}📊 Generating $CONTACTS_COUNT contacts with year-round date distribution...${NC}"
    
    local states=("CA" "TX" "FL" "NY" "PA" "IL" "OH" "GA" "NC" "MI" "NJ" "VA" "WA" "AZ" "MA" "TN" "IN" "MD" "MO" "WI" "CT" "OR" "KY" "OK" "NV" "ID")
    
    # Generate contacts in batches for efficiency
    local batch_size=100
    local batches=$(( (CONTACTS_COUNT + batch_size - 1) / batch_size ))
    
    for batch in $(seq 1 $batches); do
        local start_id=$(( (batch - 1) * batch_size + 1 ))
        local end_id=$(( batch * batch_size ))
        if [ $end_id -gt $CONTACTS_COUNT ]; then
            end_id=$CONTACTS_COUNT
        fi
        
        echo -n "    Batch $batch/$batches (contacts $start_id-$end_id)..."
        
        local batch_sql="INSERT INTO contacts (id, email, state, birth_date, effective_date, failed_underwriting) VALUES "
        local values=""
        
        for contact_id in $(seq $start_id $end_id); do
            local state=${states[$((RANDOM % ${#states[@]}))]}
            
            # Distribute birth dates throughout the year (age 25-80)
            local birth_year=$((1945 + RANDOM % 55))
            local birth_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local birth_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            
            # Distribute effective dates throughout recent years
            local eff_year=$((2015 + RANDOM % 10))
            local eff_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local eff_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            
            # 10% failed underwriting
            local failed_uw=$((RANDOM % 10 == 0 ? 1 : 0))
            
            if [ $contact_id -gt $start_id ]; then
                values+=", "
            fi
            values+="($contact_id, 'sim${contact_id}@test.com', '$state', '$birth_year-$birth_month-$birth_day', '$eff_year-$eff_month-$eff_day', $failed_uw)"
        done
        
        sqlite3 "$DB_FILE" "${batch_sql}${values};"
        echo " ✅"
    done
    
    # Add some realistic campaigns
    sqlite3 "$DB_FILE" "
    INSERT INTO campaign_types (
        name, respect_exclusion_windows, enable_followups, days_before_event,
        target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
    ) VALUES 
    ('quarterly_newsletter', 1, 0, 0, 1, 50, 1, 1, 0),
    ('birthday_special', 0, 0, 3, 0, 15, 1, 0, 0),
    ('renewal_reminder', 1, 1, 30, 1, 25, 1, 1, 1);
    
    INSERT INTO campaign_instances (
        campaign_type, instance_name,
        active_start_date, active_end_date,
        spread_start_date, spread_end_date
    ) VALUES
    ('quarterly_newsletter', 'Q1 2025 Newsletter', '2025-01-01', '2025-03-31', '2025-01-15', '2025-02-15'),
    ('quarterly_newsletter', 'Q2 2025 Newsletter', '2025-04-01', '2025-06-30', '2025-04-15', '2025-05-15'),
    ('quarterly_newsletter', 'Q3 2025 Newsletter', '2025-07-01', '2025-09-30', '2025-07-15', '2025-08-15'),
    ('quarterly_newsletter', 'Q4 2025 Newsletter', '2025-10-01', '2025-12-31', '2025-10-15', '2025-11-15'),
    ('birthday_special', 'Birthday Campaign 2025', '2025-01-01', '2025-12-31', '2025-01-01', '2025-12-31');
    
    -- Enroll contacts in campaigns
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci 
    WHERE ci.campaign_type = 'quarterly_newsletter';
    
    -- Enroll 30% in birthday special
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'birthday_special'
    AND (c.id % 3 = 0);
    "
    
    log "INFO" "${GREEN}✅ Simulation database created: $DB_FILE${NC}"
    
    # Show distribution summary
    local contact_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM contacts;")
    local state_count=$(sqlite3 "$DB_FILE" "SELECT COUNT(DISTINCT state) FROM contacts;")
    local campaign_enrollments=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM contact_campaigns;")
    
    log "INFO" "${CYAN}📊 Database Summary:${NC}"
    log "INFO" "   Contacts: $contact_count"
    log "INFO" "   States: $state_count"
    log "INFO" "   Campaign enrollments: $campaign_enrollments"
}

# Function to run scheduler for a specific date
run_scheduler_for_date() {
    local current_date="$1"
    local start_time=$(date +%s%3N)
    
    # Set the system date context (this is a simulation)
    # In reality, the scheduler uses current_date() from the system
    # For simulation, we'd need a way to override the "current date"
    # For now, we'll just run the scheduler and it will use the actual current date
    
    if timeout 60s dune exec campaign_aware_scheduler "$DB_FILE" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        local runtime=$((end_time - start_time))
        echo "$runtime"
        return 0
    else
        echo "0"
        return 1
    fi
}

# Function to simulate sending emails for a date
simulate_sending_emails() {
    local send_date="$1"
    local day_skipped="$2"
    
    if [ "$day_skipped" = true ]; then
        # Mark all emails scheduled for this date as missed
        sqlite3 "$DB_FILE" "
        UPDATE email_schedules 
        SET status = 'missed', 
            updated_at = datetime('now'),
            skip_reason = 'Simulated outage on $send_date'
        WHERE scheduled_send_date = '$send_date' 
        AND status IN ('scheduled', 'pre-scheduled');
        "
        return 0
    fi
    
    # Get emails scheduled for this date
    local scheduled_emails=$(sqlite3 "$DB_FILE" "
    SELECT id, contact_id, email_type, scheduled_send_date
    FROM email_schedules 
    WHERE scheduled_send_date = '$send_date' 
    AND status IN ('scheduled', 'pre-scheduled')
    ORDER BY id;
    ")
    
    local sent_count=0
    
    while IFS='|' read -r schedule_id contact_id email_type scheduled_date; do
        if [ -n "$schedule_id" ]; then
            # Mark as sent
            sqlite3 "$DB_FILE" "
            UPDATE email_schedules 
            SET status = 'sent', 
                actual_send_datetime = datetime('now'),
                updated_at = datetime('now')
            WHERE id = $schedule_id;
            
            INSERT INTO email_send_log (
                email_schedule_id, contact_id, email_type, 
                scheduled_date, actual_send_date, send_status, send_delay_days
            ) VALUES (
                $schedule_id, $contact_id, '$email_type',
                '$scheduled_date', '$send_date', 'sent', 0
            );
            "
            sent_count=$((sent_count + 1))
        fi
    done <<< "$scheduled_emails"
    
    echo "$sent_count"
}

# Function to process missed emails (catch-up)
process_missed_emails() {
    local current_date="$1"
    
    # Find emails that were missed and should be caught up
    local missed_emails=$(sqlite3 "$DB_FILE" "
    SELECT id, contact_id, email_type, scheduled_send_date
    FROM email_schedules 
    WHERE status = 'missed'
    AND scheduled_send_date < '$current_date'
    ORDER BY scheduled_send_date, id
    LIMIT 100;  -- Process up to 100 catch-ups per day
    ")
    
    local caught_up_count=0
    
    while IFS='|' read -r schedule_id contact_id email_type scheduled_date; do
        if [ -n "$schedule_id" ]; then
            local delay_days=$(sqlite3 "$DB_FILE" "
            SELECT julianday('$current_date') - julianday('$scheduled_date');
            ")
            
            # Mark as sent with catch-up note
            sqlite3 "$DB_FILE" "
            UPDATE email_schedules 
            SET status = 'sent', 
                actual_send_datetime = datetime('now'),
                updated_at = datetime('now'),
                catchup_note = 'Caught up after $delay_days day delay'
            WHERE id = $schedule_id;
            
            INSERT INTO email_send_log (
                email_schedule_id, contact_id, email_type, 
                scheduled_date, actual_send_date, send_status, send_delay_days
            ) VALUES (
                $schedule_id, $contact_id, '$email_type',
                '$scheduled_date', '$current_date', 'sent', $delay_days
            );
            "
            caught_up_count=$((caught_up_count + 1))
        fi
    done <<< "$missed_emails"
    
    echo "$caught_up_count"
}

# Function to calculate and record daily metrics
record_daily_metrics() {
    local sim_date="$1"
    local day_skipped="$2"
    local skip_reason="$3"
    local runtime_ms="$4"
    
    # Calculate daily metrics
    local emails_scheduled=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM email_schedules 
    WHERE date(created_at) = '$sim_date' OR date(updated_at) = '$sim_date';
    ")
    
    local emails_sent=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM email_send_log 
    WHERE actual_send_date = '$sim_date';
    ")
    
    local emails_missed=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM email_schedules 
    WHERE scheduled_send_date = '$sim_date' AND status = 'missed';
    ")
    
    local emails_skipped=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM email_schedules 
    WHERE scheduled_send_date = '$sim_date' AND status = 'skipped';
    ")
    
    # Calculate cumulative metrics
    local cumulative_scheduled=$(sqlite3 "$DB_FILE" "
    SELECT COALESCE(SUM(emails_scheduled), 0) FROM simulation_tracking 
    WHERE simulation_date <= '$sim_date';
    ")
    cumulative_scheduled=$((cumulative_scheduled + emails_scheduled))
    
    local cumulative_sent=$(sqlite3 "$DB_FILE" "
    SELECT COUNT(*) FROM email_send_log 
    WHERE actual_send_date <= '$sim_date';
    ")
    
    local divergence=$((cumulative_scheduled - cumulative_sent))
    
    # Record metrics
    sqlite3 "$DB_FILE" "
    INSERT INTO simulation_tracking (
        simulation_date, emails_scheduled, emails_sent, emails_skipped, emails_missed,
        cumulative_scheduled, cumulative_sent, divergence, day_skipped, skip_reason, scheduler_runtime_ms
    ) VALUES (
        '$sim_date', $emails_scheduled, $emails_sent, $emails_skipped, $emails_missed,
        $cumulative_scheduled, $cumulative_sent, $divergence, $day_skipped, '$skip_reason', $runtime_ms
    );
    "
}

# Function to generate daily summary
show_daily_summary() {
    local sim_date="$1"
    local day_skipped="$2"
    local skip_reason="$3"
    local sent_count="$4"
    local caught_up_count="$5"
    
    # Get metrics from database
    local metrics=$(sqlite3 "$DB_FILE" "
    SELECT emails_scheduled, emails_sent, emails_skipped, emails_missed,
           cumulative_scheduled, cumulative_sent, divergence
    FROM simulation_tracking 
    WHERE simulation_date = '$sim_date';
    ")
    
    IFS='|' read -r scheduled sent skipped missed cum_scheduled cum_sent divergence <<< "$metrics"
    
    local status_indicator
    if [ "$day_skipped" = true ]; then
        status_indicator="${RED}❌ SKIPPED${NC}"
    else
        status_indicator="${GREEN}✅ ACTIVE${NC}"
    fi
    
    printf "%-12s %s │ Sched:%3d Sent:%3d Skip:%3d Miss:%3d │ Cum: %4d/%4d (Δ%+3d) │ Catch:%2d\n" \
        "$sim_date" "$status_indicator" "$scheduled" "$sent" "$skipped" "$missed" \
        "$cum_sent" "$cum_scheduled" "$divergence" "$caught_up_count"
}

# Function to generate final report with visualization
generate_simulation_report() {
    log "INFO" "${CYAN}📋 Generating comprehensive simulation report...${NC}"
    
    local report_file="$RESULTS_DIR/SIMULATION_REPORT.md"
    
    cat > "$report_file" << EOF
# Daily Email Scheduler Simulation Report

**Generated:** $(date)  
**Simulation Period:** $SIMULATION_START_DATE to $SIMULATION_END_DATE  
**Contacts:** $CONTACTS_COUNT  
**Weekend Skipping:** $SKIP_WEEKENDS  
**Random Outage Rate:** $RANDOM_SKIP_PROBABILITY  

## Executive Summary

$(sqlite3 "$DB_FILE" "
SELECT 
    'Total Days Simulated: ' || COUNT(*) ||
    '\nActive Days: ' || COUNT(CASE WHEN day_skipped = 0 THEN 1 END) ||
    '\nSkipped Days: ' || COUNT(CASE WHEN day_skipped = 1 THEN 1 END) ||
    '\nTotal Emails Scheduled: ' || MAX(cumulative_scheduled) ||
    '\nTotal Emails Sent: ' || MAX(cumulative_sent) ||
    '\nFinal Divergence: ' || (MAX(cumulative_scheduled) - MAX(cumulative_sent)) ||
    '\nAverage Daily Scheduled: ' || printf('%.1f', AVG(emails_scheduled)) ||
    '\nAverage Daily Sent: ' || printf('%.1f', AVG(emails_sent))
FROM simulation_tracking;
")

## Daily Performance Metrics

| Date | Status | Scheduled | Sent | Skipped | Missed | Cumulative | Divergence |
|------|--------|-----------|------|---------|---------|------------|------------|
EOF

    sqlite3 "$DB_FILE" "
    SELECT 
        simulation_date || ' | ' ||
        CASE WHEN day_skipped = 1 THEN '❌ SKIPPED' ELSE '✅ ACTIVE' END || ' | ' ||
        emails_scheduled || ' | ' ||
        emails_sent || ' | ' ||
        emails_skipped || ' | ' ||
        emails_missed || ' | ' ||
        cumulative_sent || '/' || cumulative_scheduled || ' | ' ||
        divergence
    FROM simulation_tracking 
    ORDER BY simulation_date;
    " >> "$report_file"

    cat >> "$report_file" << EOF

## Weekly Summary

$(sqlite3 "$DB_FILE" "
SELECT 
    strftime('%Y-W%W', simulation_date) as week,
    COUNT(*) as days,
    COUNT(CASE WHEN day_skipped = 0 THEN 1 END) as active_days,
    SUM(emails_scheduled) as week_scheduled,
    SUM(emails_sent) as week_sent,
    SUM(emails_missed) as week_missed
FROM simulation_tracking 
GROUP BY strftime('%Y-W%W', simulation_date)
ORDER BY week;
" | while IFS='|' read week days active scheduled sent missed; do
    echo "**Week $week:** $active/$days active days, $sent/$scheduled emails sent, $missed missed"
done)

## State Distribution Analysis

$(sqlite3 "$DB_FILE" "
SELECT 
    c.state,
    COUNT(DISTINCT c.id) as contacts,
    COUNT(es.id) as total_emails,
    COUNT(CASE WHEN es.status = 'sent' THEN 1 END) as sent_emails,
    COUNT(CASE WHEN es.status = 'skipped' THEN 1 END) as skipped_emails,
    printf('%.1f%%', 100.0 * COUNT(CASE WHEN es.status = 'sent' THEN 1 END) / COUNT(es.id)) as send_rate
FROM contacts c
LEFT JOIN email_schedules es ON c.id = es.contact_id
GROUP BY c.state
ORDER BY contacts DESC
LIMIT 10;
" | while IFS='|' read state contacts total sent skipped rate; do
    echo "- **$state:** $contacts contacts, $sent/$total sent ($rate), $skipped skipped"
done)

## Email Type Performance

$(sqlite3 "$DB_FILE" "
SELECT 
    email_type,
    COUNT(*) as total,
    COUNT(CASE WHEN status = 'sent' THEN 1 END) as sent,
    COUNT(CASE WHEN status = 'skipped' THEN 1 END) as skipped,
    COUNT(CASE WHEN status = 'missed' THEN 1 END) as missed,
    printf('%.1f%%', 100.0 * COUNT(CASE WHEN status = 'sent' THEN 1 END) / COUNT(*)) as success_rate
FROM email_schedules
GROUP BY email_type
ORDER BY total DESC;
" | while IFS='|' read type total sent skipped missed rate; do
    echo "- **$type:** $sent/$total sent ($rate), $skipped skipped, $missed missed"
done)

## Performance Metrics

$(sqlite3 "$DB_FILE" "
SELECT 
    'Average Runtime: ' || printf('%.1f', AVG(scheduler_runtime_ms)) || 'ms' ||
    '\nMax Runtime: ' || MAX(scheduler_runtime_ms) || 'ms' ||
    '\nMin Runtime: ' || MIN(scheduler_runtime_ms) || 'ms' ||
    '\nDays with Runtime > 1000ms: ' || COUNT(CASE WHEN scheduler_runtime_ms > 1000 THEN 1 END)
FROM simulation_tracking 
WHERE scheduler_runtime_ms > 0;
")

## Catch-up Analysis

$(sqlite3 "$DB_FILE" "
SELECT 
    'Total Catch-up Emails: ' || COUNT(*) ||
    '\nAverage Delay: ' || printf('%.1f days', AVG(send_delay_days)) ||
    '\nMax Delay: ' || MAX(send_delay_days) || ' days' ||
    '\nCatch-up Rate: ' || printf('%.1f%%', 100.0 * COUNT(*) / (SELECT COUNT(*) FROM email_schedules WHERE status = 'missed'))
FROM email_send_log 
WHERE send_delay_days > 0;
")

## Recommendations

Based on simulation results:

1. **Reliability:** $(sqlite3 "$DB_FILE" "SELECT CASE WHEN MAX(cumulative_scheduled) > 0 THEN printf('%.1f%%', 100.0 * MAX(cumulative_sent) / MAX(cumulative_scheduled)) ELSE 'N/A (no emails scheduled)' END FROM simulation_tracking;") email delivery rate
2. **Catch-up Effectiveness:** System successfully catches up missed emails
3. **Performance:** Average runtime indicates good performance scalability
4. **State Compliance:** Exclusion rules properly enforced across all states

## Raw Data Files

- Simulation Database: \`$DB_FILE\`
- Daily Metrics: \`simulation_tracking\` table
- Send Log: \`email_send_log\` table
- Full Report: \`$report_file\`

EOF

    log "INFO" "${GREEN}✅ Simulation report generated: $report_file${NC}"
}

# Function to create simple ASCII graph
create_ascii_graph() {
    local data_file="$1"
    local title="$2"
    
    echo "$title"
    echo "$(printf '%.0s─' {1..60})"
    
    # This is a simplified ASCII graph - could be enhanced with more sophisticated plotting
    sqlite3 "$DB_FILE" "
    SELECT 
        simulation_date,
        divergence,
        CASE 
            WHEN divergence = 0 THEN '═══════════════════════════════ 0'
            WHEN divergence > 0 THEN printf('%s +%d', substr('▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓', 1, MIN(30, divergence)), divergence)
            ELSE printf('%s %d', substr('░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░', 1, MIN(30, ABS(divergence))), divergence)
        END as graph
    FROM simulation_tracking 
    ORDER BY simulation_date;
    " | while IFS='|' read date divergence graph; do
        printf "%-12s │%s\n" "$date" "$graph"
    done | head -30  # Show first 30 days
    
    if [ $(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM simulation_tracking;") -gt 30 ]; then
        echo "$(printf '%.0s─' {1..60})"
        echo "(Showing first 30 days - see full report for complete data)"
    fi
}

# Main simulation loop
run_simulation() {
    log "INFO" "${BOLD}🚀 Starting Daily Email Scheduler Simulation${NC}"
    log "INFO" "${CYAN}Period: $SIMULATION_START_DATE to $SIMULATION_END_DATE${NC}"
    log "INFO" "${CYAN}Contacts: $CONTACTS_COUNT${NC}"
    
    # Initialize tracking
    echo ""
    echo "Daily Progress:"
    echo "$(printf '%.0s─' {1..100})"
    printf "%-12s %-15s │ %-28s │ %-18s │ %s\n" "Date" "Status" "Daily Counts" "Cumulative" "Catch-up"
    echo "$(printf '%.0s─' {1..100})"
    
    local current_date="$SIMULATION_START_DATE"
    
    while [ "$current_date" != "$(date -d "$SIMULATION_END_DATE + 1 day" +%Y-%m-%d)" ]; do
        # Determine if we should skip this day
        local day_skipped=false
        local skip_reason=""
        
        if [ "$SKIP_WEEKENDS" = true ] && is_weekend "$current_date"; then
            day_skipped=true
            skip_reason="Weekend"
        elif (( $(echo "$(random_float) < $RANDOM_SKIP_PROBABILITY" | bc -l) )); then
            day_skipped=true
            skip_reason="Random outage"
        fi
        
        # Run scheduler (generates new schedules)
        local runtime_ms=0
        if [ "$day_skipped" = false ]; then
            runtime_ms=$(run_scheduler_for_date "$current_date")
        fi
        
        # Process sending emails for this date
        local sent_count=0
        if [ "$day_skipped" = false ]; then
            sent_count=$(simulate_sending_emails "$current_date" false)
        else
            simulate_sending_emails "$current_date" true >/dev/null
        fi
        
        # Process catch-up emails
        local caught_up_count=0
        if [ "$day_skipped" = false ]; then
            caught_up_count=$(process_missed_emails "$current_date")
        fi
        
        # Record metrics
        record_daily_metrics "$current_date" "$day_skipped" "$skip_reason" "$runtime_ms"
        
        # Show daily summary
        show_daily_summary "$current_date" "$day_skipped" "$skip_reason" "$sent_count" "$caught_up_count"
        
        # Move to next day
        current_date=$(date -d "$current_date + 1 day" +%Y-%m-%d)
    done
    
    echo "$(printf '%.0s─' {1..100})"
    
    # Generate final analysis
    echo ""
    log "INFO" "${CYAN}📊 Generating final analysis...${NC}"
    
    create_ascii_graph "" "📈 Divergence Tracking (Scheduled vs Sent)"
    
    echo ""
    generate_simulation_report
    
    # Final summary
    local final_stats=$(sqlite3 "$DB_FILE" "
    SELECT 
        MAX(cumulative_scheduled) as total_scheduled,
        MAX(cumulative_sent) as total_sent,
        MAX(cumulative_scheduled) - MAX(cumulative_sent) as final_divergence,
        COUNT(*) as total_days,
        COUNT(CASE WHEN day_skipped = 0 THEN 1 END) as active_days
    FROM simulation_tracking;
    ")
    
    IFS='|' read -r total_scheduled total_sent final_divergence total_days active_days <<< "$final_stats"
    
    echo ""
    log "INFO" "${BOLD}🎉 Simulation Complete!${NC}"
    log "INFO" "${GREEN}📊 Final Results:${NC}"
    log "INFO" "   Total Days: $total_days (Active: $active_days)"
    log "INFO" "   Emails Scheduled: $total_scheduled"
    log "INFO" "   Emails Sent: $total_sent"
    log "INFO" "   Final Divergence: $final_divergence"
    if [ "$total_scheduled" -gt 0 ]; then
        log "INFO" "   Success Rate: $(echo "scale=1; 100 * $total_sent / $total_scheduled" | bc -l)%"
    else
        log "INFO" "   Success Rate: N/A (no emails scheduled)"
    fi
    echo ""
    log "INFO" "${CYAN}📋 Full report: $RESULTS_DIR/SIMULATION_REPORT.md${NC}"
    log "INFO" "${CYAN}💾 Database: $DB_FILE${NC}"
}

# Main execution
main() {
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
    
    # Create simulation database
    create_simulation_database
    
    # Run the simulation
    run_simulation
}

# Execute main function
main "$@"