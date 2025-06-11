#!/bin/bash

# Advanced Campaign Testing for Email Scheduler
# Tests AEP campaigns and custom campaigns with exclusion rules

set -e

echo "🚀 Advanced Campaign Testing Suite"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Helper function to show campaign info
show_campaign_info() {
    local db_file="$1"
    echo -e "\n${PURPLE}📋 Campaign Configuration:${NC}"
    
    # Show campaign types
    sqlite3 "$db_file" "
    SELECT 
        name,
        priority,
        days_before_event,
        CASE respect_exclusion_windows WHEN 1 THEN 'YES' ELSE 'NO' END as respects_exclusions,
        CASE active WHEN 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as status
    FROM campaign_types;
    " | while IFS='|' read name priority days exclusions status; do
        echo "  📊 $name: Priority $priority, $days days before event, Respects exclusions: $exclusions ($status)"
    done
    
    # Show campaign instances
    sqlite3 "$db_file" "
    SELECT 
        campaign_type,
        instance_name,
        active_start_date,
        active_end_date,
        target_states
    FROM campaign_instances;
    " | while IFS='|' read type instance start_date end_date states; do
        if [ "$states" = "" ]; then
            states="ALL STATES"
        fi
        echo "  📅 $instance ($type): $start_date to $end_date, targeting: $states"
    done
}

# Helper function to run scheduler and show results
run_campaign_test() {
    local test_name="$1"
    local db_file="$2"
    
    echo -e "\n${BLUE}📊 Running scheduler for: $test_name${NC}"
    show_campaign_info "$db_file"
    
    # Run the scheduler
    DATABASE_PATH="$db_file" dune exec high_performance_scheduler "$db_file" 2>/dev/null || true
    
    # Show results
    echo -e "\n${GREEN}📋 Generated Email Schedules:${NC}"
    sqlite3 "$db_file" "
    SELECT 
        c.email,
        c.state,
        es.email_type,
        es.scheduled_send_date,
        es.status,
        COALESCE(es.skip_reason, 'N/A') as skip_reason
    FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    ORDER BY es.scheduled_send_date, c.email;
    " | while IFS='|' read email state type date status reason; do
        if [ "$status" = "skipped" ]; then
            echo -e "  ${YELLOW}⚠️  $email ($state) - $type on $date (SKIPPED: $reason)${NC}"
        else
            echo -e "  ${GREEN}✅ $email ($state) - $type on $date ($status)${NC}"
        fi
    done
    
    # Show summary by email type
    echo -e "\n${BLUE}📈 Summary by Email Type:${NC}"
    sqlite3 "$db_file" "
    SELECT 
        email_type,
        status,
        COUNT(*) as count
    FROM email_schedules 
    GROUP BY email_type, status
    ORDER BY email_type, status;
    " | while IFS='|' read type status count; do
        echo "  $type: $count $status"
    done
}

# Test 4: AEP Campaign (simulating October dates)
echo -e "\n${RED}🗳️  Test 4: AEP Campaign (Simulated October)${NC}"
echo "=============================================="

DB4="test_aep_campaign.db"
rm -f "$DB4"

# Apply migrations to get campaign tables
sqlite3 "$DB4" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB4" "
-- Create contacts table
CREATE TABLE contacts (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    birth_date TEXT,
    effective_date TEXT,
    state TEXT,
    zip_code TEXT,
    current_carrier TEXT
);

CREATE TABLE email_schedules (
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

-- Create required indexes
CREATE UNIQUE INDEX idx_email_schedules_unique ON email_schedules (contact_id, email_type, scheduled_send_date);
CREATE INDEX idx_email_schedules_status ON email_schedules (status);
CREATE INDEX idx_email_schedules_date ON email_schedules (scheduled_send_date);

-- Insert test contacts for AEP
INSERT INTO contacts (id, email, state, birth_date) VALUES
    (1, 'senior1@test.com', 'TX', '1950-03-15'),
    (2, 'senior2@test.com', 'CA', '1955-08-20'),  -- CA exclusions
    (3, 'senior3@test.com', 'FL', '1960-12-10'),
    (4, 'senior4@test.com', 'NY', '1945-06-05'),  -- NY exclusions
    (5, 'senior5@test.com', 'AZ', '1958-09-25');

-- Modify the default AEP campaign to be active for testing
-- Simulate AEP period (October 15 - December 7)
UPDATE campaign_instances 
SET active_start_date = '2024-10-15',
    active_end_date = '2024-12-07',
    spread_start_date = '2024-10-15',
    spread_end_date = '2024-12-07'
WHERE campaign_type = 'aep';

-- Add contact_campaigns entries to enroll everyone in AEP
INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status) 
SELECT 
    c.id,
    ci.id,
    'active'
FROM contacts c
CROSS JOIN campaign_instances ci 
WHERE ci.campaign_type = 'aep';
"

echo -e "${BLUE}👥 Test Contacts for AEP:${NC}"
sqlite3 "$DB4" "
SELECT 
    email,
    state,
    birth_date,
    'Senior (' || (2025 - substr(birth_date, 1, 4)) || ' years old)' as age_info
FROM contacts ORDER BY state;
" | while IFS='|' read email state bdate info; do
    echo "  📧 $email ($state) - $info"
done

run_campaign_test "AEP Campaign" "$DB4"

# Test 5: Custom Initial Blast Campaign
echo -e "\n${RED}📢 Test 5: Custom Initial Blast Campaign${NC}"
echo "========================================="

DB5="test_initial_blast.db"
rm -f "$DB5"

# Apply migrations to get campaign tables
sqlite3 "$DB5" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB5" "
-- Create contacts table
CREATE TABLE contacts (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    birth_date TEXT,
    effective_date TEXT,
    state TEXT,
    zip_code TEXT,
    current_carrier TEXT
);

CREATE TABLE email_schedules (
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

-- Create required indexes
CREATE UNIQUE INDEX idx_email_schedules_unique ON email_schedules (contact_id, email_type, scheduled_send_date);
CREATE INDEX idx_email_schedules_status ON email_schedules (status);
CREATE INDEX idx_email_schedules_date ON email_schedules (scheduled_send_date);

-- Create custom 'initial_blast' campaign type
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'initial_blast', 1, 0, 0, 1, 25, 1, 1, 0
);

-- Create campaign instance for initial_blast spread over 30 days
INSERT INTO campaign_instances (
    campaign_type, instance_name, 
    active_start_date, active_end_date,
    spread_start_date, spread_end_date,
    metadata
) VALUES (
    'initial_blast', 'Welcome Email Blast Q2 2025',
    '2025-06-01', '2025-07-01',
    '2025-06-01', '2025-06-30',
    '{\"description\": \"Initial welcome email blast spread over 30 days\"}'
);

-- Insert diverse test contacts (all 65+)
INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES
    (1, 'new1@test.com', 'TX', '1955-07-15', '2023-06-15'),  -- Age 70, TX, no exclusions expected
    (2, 'new2@test.com', 'CA', '1950-07-10', '2022-06-20'),  -- Age 75, CA, might have birthday exclusion
    (3, 'new3@test.com', 'NY', '1940-07-05', '2021-06-10'),  -- Age 85, NY, might have exclusions
    (4, 'new4@test.com', 'FL', '1953-12-25', '2024-01-01'),  -- Age 72, FL, no birthday conflict
    (5, 'new5@test.com', 'AZ', '1957-08-30', '2020-08-15'),  -- Age 68, AZ, no conflicts
    (6, 'new6@test.com', 'CA', '1945-06-10', '2019-05-20');  -- Age 80, CA, birthday very close to campaign

-- Enroll everyone in the initial_blast campaign
INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
SELECT 
    c.id,
    ci.id,
    'active'
FROM contacts c
CROSS JOIN campaign_instances ci 
WHERE ci.campaign_type = 'initial_blast';
"

echo -e "${BLUE}👥 Test Contacts for Initial Blast:${NC}"
sqlite3 "$DB5" "
SELECT 
    email,
    state,
    birth_date,
    effective_date,
    'Birthday: ' || substr(birth_date, 6) || ', Policy: ' || substr(effective_date, 6) as dates
FROM contacts ORDER BY state, email;
" | while IFS='|' read email state bdate edate info; do
    echo "  📧 $email ($state) - $info"
done

run_campaign_test "Initial Blast Campaign" "$DB5"

# Test 6: Mixed Scenario - Anniversaries + Campaigns + Exclusions
echo -e "\n${RED}🎭 Test 6: Mixed Scenario (Anniversaries + Campaigns + Exclusions)${NC}"
echo "=================================================================="

DB6="test_mixed_scenario.db"
rm -f "$DB6"

# Apply migrations
sqlite3 "$DB6" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB6" "
-- Create contacts table
CREATE TABLE contacts (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    birth_date TEXT,
    effective_date TEXT,
    state TEXT,
    zip_code TEXT,
    current_carrier TEXT
);

CREATE TABLE email_schedules (
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

-- Create required indexes
CREATE UNIQUE INDEX idx_email_schedules_unique ON email_schedules (contact_id, email_type, scheduled_send_date);
CREATE INDEX idx_email_schedules_status ON email_schedules (status);
CREATE INDEX idx_email_schedules_date ON email_schedules (scheduled_send_date);

-- Add a low-priority campaign
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'newsletter', 1, 0, 0, 1, 60, 1, 1, 0
);

INSERT INTO campaign_instances (
    campaign_type, instance_name,
    active_start_date, active_end_date,
    spread_start_date, spread_end_date
) VALUES (
    'newsletter', 'Monthly Newsletter June 2025',
    '2025-06-01', '2025-06-30',
    '2025-06-15', '2025-06-25'
);

-- Insert contacts with overlapping anniversaries and campaign eligibility (all 65+)
INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES
    (1, 'complex1@test.com', 'CA', '1955-07-01', '2022-06-15'),  -- Age 70, Birthday and effective date in summer, CA exclusions
    (2, 'complex2@test.com', 'TX', '1950-06-20', '2023-07-10'),  -- Age 75, Multiple summer anniversaries, no exclusions
    (3, 'complex3@test.com', 'NY', '1940-08-15', '2021-06-01');  -- Age 85, NY exclusions, summer anniversaries

-- Enroll in newsletter campaign
INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
SELECT 
    c.id,
    ci.id,
    'active'
FROM contacts c
CROSS JOIN campaign_instances ci 
WHERE ci.campaign_type = 'newsletter';
"

echo -e "${BLUE}👥 Test Contacts for Mixed Scenario:${NC}"
sqlite3 "$DB6" "
SELECT 
    email,
    state,
    birth_date || ' (birthday)' as birthday,
    effective_date || ' (policy)' as policy,
    'Enrolled in newsletter campaign' as campaign_info
FROM contacts ORDER BY email;
" | while IFS='|' read email state bday policy campaign; do
    echo "  📧 $email ($state)"
    echo "      🎂 $bday"
    echo "      📋 $policy" 
    echo "      📧 $campaign"
done

run_campaign_test "Mixed Scenario" "$DB6"

echo -e "\n${GREEN}🎉 Advanced Campaign Testing Complete!${NC}"
echo "===================================================="
echo ""
echo "Summary of what was tested:"
echo "✅ AEP campaigns with state exclusion considerations"
echo "✅ Custom initial_blast campaign spread over 30 days"
echo "✅ Mixed scenarios with competing email types and priorities"
echo "✅ Exclusion window handling across different states"
echo "✅ Campaign enrollment and targeting logic"
echo ""
echo "Review the results to ensure:"
echo "- High priority emails (birthdays, effective dates) take precedence"
echo "- Exclusion windows are respected based on state rules"
echo "- Campaigns are properly spread across their date ranges"
echo "- No conflicts between anniversary emails and campaigns"