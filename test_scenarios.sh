#!/bin/bash

# Test Scenarios for Email Scheduler Business Logic
# Creates minimal test databases with specific scenarios

set -e

echo "🧪 Email Scheduler Business Logic Test Suite"
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper function to run scheduler and show results
run_test_scenario() {
    local test_name="$1"
    local db_file="$2"
    
    echo -e "\n${BLUE}📊 Running scheduler for: $test_name${NC}"
    echo "Database: $db_file"
    
    # Run the high-performance scheduler
    DATABASE_PATH="$db_file" dune exec high_performance_scheduler "$db_file" 2>/dev/null || true
    
    # Show results
    echo -e "\n${GREEN}📋 Generated Email Schedules:${NC}"
    sqlite3 "$db_file" "
    SELECT 
        c.email,
        es.email_type,
        es.scheduled_send_date,
        es.status,
        es.skip_reason
    FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    ORDER BY es.scheduled_send_date, c.email;
    " | while IFS='|' read email type date status reason; do
        if [ "$status" = "skipped" ]; then
            echo -e "  ${YELLOW}⚠️  $email - $type on $date (SKIPPED: $reason)${NC}"
        else
            echo -e "  ${GREEN}✅ $email - $type on $date ($status)${NC}"
        fi
    done
    
    # Show summary
    echo -e "\n${BLUE}📈 Summary:${NC}"
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

# Test 1: Upcoming Birthday Anniversaries
echo -e "\n${RED}🎂 Test 1: Upcoming Birthday Anniversaries${NC}"
echo "================================================"

DB1="test_birthdays.db"
rm -f "$DB1"

# Apply the campaign migration to create required tables
sqlite3 "$DB1" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB1" "
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

-- Insert test contacts with birthdays in next 60 days (all 65+)
INSERT INTO contacts (id, email, birth_date, state) VALUES
    (1, 'alice@test.com', '1955-07-15', 'TX'),  -- Birthday in ~35 days, age 70
    (2, 'bob@test.com', '1950-06-25', 'CA'),    -- Birthday in ~15 days, age 75
    (3, 'charlie@test.com', '1957-08-10', 'NY'), -- Birthday in ~60 days, age 68
    (4, 'diana@test.com', '1953-05-01', 'FL');   -- Birthday already passed this year, age 72
"

echo -e "${BLUE}👥 Test Contacts:${NC}"
sqlite3 "$DB1" "
SELECT 
    email,
    birth_date,
    state,
    'Birthday: ' || birth_date || ' (Age ' || (2025 - substr(birth_date, 1, 4)) || ')' as info
FROM contacts ORDER BY birth_date;
" | while IFS='|' read email bdate state info; do
    echo "  📧 $email ($state) - $info"
done

run_test_scenario "Birthday Anniversaries" "$DB1"

# Test 2: Effective Date Anniversaries  
echo -e "\n${RED}📅 Test 2: Effective Date Anniversaries${NC}"
echo "==============================================="

DB2="test_effective_dates.db"
rm -f "$DB2"

# Apply the campaign migration to create required tables
sqlite3 "$DB2" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB2" "
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

-- Insert test contacts with effective dates (all 65+)
INSERT INTO contacts (id, email, birth_date, effective_date, state) VALUES
    (1, 'policy1@test.com', '1952-01-01', '2022-07-01', 'TX'),  -- Age 73, 3-year anniversary
    (2, 'policy2@test.com', '1948-01-01', '2023-06-15', 'CA'),  -- Age 77, 2-year anniversary
    (3, 'policy3@test.com', '1955-01-01', '2024-08-20', 'NY'),  -- Age 70, 1-year anniversary
    (4, 'policy4@test.com', '1950-01-01', '2021-05-10', 'FL');  -- Age 75, 4-year anniversary
"

echo -e "${BLUE}👥 Test Contacts:${NC}"
sqlite3 "$DB2" "
SELECT 
    email,
    effective_date,
    state,
    'Policy effective: ' || effective_date || ' (' || (2025 - substr(effective_date, 1, 4)) || ' years)' as info
FROM contacts ORDER BY effective_date;
" | while IFS='|' read email edate state info; do
    echo "  📧 $email ($state) - $info"
done

run_test_scenario "Effective Date Anniversaries" "$DB2"

# Test 3: State Exclusion Windows
echo -e "\n${RED}🚫 Test 3: State Exclusion Windows${NC}"
echo "======================================="

DB3="test_exclusions.db"
rm -f "$DB3"

# Apply the campaign migration to create required tables
sqlite3 "$DB3" < migrations/003_add_campaign_tables.sql

sqlite3 "$DB3" "
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

-- Insert contacts in states with known exclusion windows (all 65+)
INSERT INTO contacts (id, email, birth_date, state) VALUES
    (1, 'ca_resident@test.com', '1955-07-15', 'CA'),   -- Age 70, CA has 30-day birthday exclusion
    (2, 'ny_resident@test.com', '1950-07-15', 'NY'),   -- Age 75, NY has year-round exclusions
    (3, 'tx_resident@test.com', '1957-07-15', 'TX'),   -- Age 68, TX should be fine
    (4, 'fl_resident@test.com', '1953-07-15', 'FL');   -- Age 72, FL should be fine
"

echo -e "${BLUE}👥 Test Contacts (all with same birthday July 15):${NC}"
sqlite3 "$DB3" "
SELECT 
    email,
    state,
    birth_date,
    CASE state
        WHEN 'CA' THEN 'California - HAS 30-day birthday exclusion window'
        WHEN 'NY' THEN 'New York - HAS year-round exclusions for some types'
        ELSE state || ' - No special exclusions'
    END as exclusion_info
FROM contacts ORDER BY state;
" | while IFS='|' read email state bdate info; do
    echo "  📧 $email - $info"
done

run_test_scenario "State Exclusion Windows" "$DB3"

echo -e "\n${GREEN}🧪 Test Suite Complete!${NC}"
echo "======================================="
echo "Review the results above to verify business logic is working correctly."
echo ""
echo "Expected behaviors:"
echo "- Birthday emails should be scheduled ~14 days before birthday"
echo "- Effective date emails should be scheduled ~30 days before anniversary"
echo "- CA residents may have birthday emails skipped due to exclusion windows"
echo "- NY residents may have certain email types excluded"
echo "- Other states should process normally"