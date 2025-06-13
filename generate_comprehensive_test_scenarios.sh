#!/bin/bash

# Comprehensive Test Scenario Generator for Email Scheduler
# Creates multiple test databases with various scenarios for thorough testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Comprehensive Test Scenario Generator${NC}"
echo "=========================================="

# Helper function to apply base schema
setup_base_schema() {
    local db_file="$1"
    
    echo -e "  ${CYAN}📋 Setting up base schema...${NC}"
    
    # Apply migrations
    if [ -f "migrations/003_add_campaign_tables.sql" ]; then
        sqlite3 "$db_file" < migrations/003_add_campaign_tables.sql
    fi
    
    # Create contacts table if it doesn't exist
    sqlite3 "$db_file" "
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

    -- Create required indexes
    CREATE UNIQUE INDEX IF NOT EXISTS idx_email_schedules_unique ON email_schedules (contact_id, email_type, scheduled_send_date);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_status ON email_schedules (status);
    CREATE INDEX IF NOT EXISTS idx_email_schedules_date ON email_schedules (scheduled_send_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_state ON contacts (state);
    CREATE INDEX IF NOT EXISTS idx_contacts_birth_date ON contacts (birth_date);
    CREATE INDEX IF NOT EXISTS idx_contacts_effective_date ON contacts (effective_date);
    "
}

# Scenario 1: Birthday Rule Matrix Testing
generate_birthday_rule_matrix() {
    local db_file="test_birthday_matrix.db"
    rm -f "$db_file"
    
    echo -e "\n${PURPLE}🎂 Scenario 1: Birthday Rule Matrix Testing${NC}"
    echo "============================================="
    
    setup_base_schema "$db_file"
    
    sqlite3 "$db_file" "
    -- Generate contacts for all states with exclusion rules
    INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES
    -- CA: 30 days before, 60 days after birthday
    (1, 'ca_test1@test.com', 'CA', '1955-03-15', '2020-01-10'),  -- Birthday in March
    (2, 'ca_test2@test.com', 'CA', '1960-07-01', '2021-02-15'),  -- Birthday on July 1st (boundary)
    (3, 'ca_test3@test.com', 'CA', '1950-12-31', '2019-12-31'),  -- Birthday on Dec 31st (year boundary)
    
    -- ID: 0 days before, 63 days after birthday  
    (4, 'id_test1@test.com', 'ID', '1958-06-15', '2022-03-20'),
    (5, 'id_test2@test.com', 'ID', '1962-02-28', '2023-01-05'),  -- Non-leap year Feb 28
    (6, 'id_test3@test.com', 'ID', '1952-02-29', '2020-02-29'),  -- Leap year birthday
    
    -- KY: 0 days before, 60 days after birthday
    (7, 'ky_test1@test.com', 'KY', '1945-09-10', '2018-05-15'),
    (8, 'ky_test2@test.com', 'KY', '1965-01-01', '2024-01-01'),  -- New Year birthday
    
    -- MD: 0 days before, 30 days after birthday
    (9, 'md_test1@test.com', 'MD', '1957-08-20', '2021-06-10'),
    (10, 'md_test2@test.com', 'MD', '1940-04-30', '2019-04-30'), -- April 30th boundary
    
    -- NV: 0 days before, 60 days after (month-start alignment)
    (11, 'nv_test1@test.com', 'NV', '1963-05-15', '2022-07-20'),
    (12, 'nv_test2@test.com', 'NV', '1955-11-30', '2020-10-15'), -- November 30th boundary
    
    -- OK: 0 days before, 60 days after birthday
    (13, 'ok_test1@test.com', 'OK', '1948-10-05', '2017-12-25'),
    
    -- OR: 0 days before, 31 days after birthday
    (14, 'or_test1@test.com', 'OR', '1959-07-20', '2023-08-15'),
    
    -- VA: 0 days before, 30 days after birthday
    (15, 'va_test1@test.com', 'VA', '1966-12-25', '2024-11-10'), -- Christmas birthday
    
    -- MO: Effective date exclusion (30 days before, 33 days after)
    (16, 'mo_test1@test.com', 'MO', '1961-03-10', '2022-06-15'),
    (17, 'mo_test2@test.com', 'MO', '1953-08-25', '2019-02-28'), -- Effective date Feb 28
    
    -- Year-round exclusions: CT, MA, NY, WA
    (18, 'ct_test1@test.com', 'CT', '1944-01-15', '2018-03-20'),
    (19, 'ma_test1@test.com', 'MA', '1967-09-05', '2025-01-10'),
    (20, 'ny_test1@test.com', 'NY', '1956-11-11', '2021-11-11'), -- Same birth/effective date
    (21, 'wa_test1@test.com', 'WA', '1949-06-30', '2020-06-30'),
    
    -- States with no exclusions
    (22, 'tx_test1@test.com', 'TX', '1964-04-15', '2023-07-01'),
    (23, 'fl_test1@test.com', 'FL', '1951-08-10', '2019-09-15'),
    (24, 'az_test1@test.com', 'AZ', '1958-12-05', '2022-03-25');
    "
    
    echo -e "  ${GREEN}✅ Generated $db_file with 24 contacts covering all birthday exclusion rules${NC}"
    echo -e "  ${YELLOW}📊 Coverage: All states with exclusions + leap year + boundary dates${NC}"
}

# Scenario 2: Campaign Priority Matrix
generate_campaign_priority_matrix() {
    local db_file="test_campaign_priority.db"
    rm -f "$db_file"
    
    echo -e "\n${PURPLE}🎯 Scenario 2: Campaign Priority Matrix${NC}"
    echo "======================================="
    
    setup_base_schema "$db_file"
    
    sqlite3 "$db_file" "
    -- Create multiple campaign types with different priorities
    INSERT INTO campaign_types (
        name, respect_exclusion_windows, enable_followups, days_before_event,
        target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
    ) VALUES 
    ('high_priority_blast', 0, 0, 0, 1, 10, 1, 1, 0),  -- High priority, ignores exclusions
    ('aep_special', 1, 1, 7, 1, 20, 1, 1, 1),          -- Medium priority, respects exclusions
    ('newsletter', 1, 0, 0, 1, 60, 1, 1, 0),           -- Low priority
    ('urgent_compliance', 0, 0, 0, 1, 5, 1, 0, 0);     -- Highest priority, no spread
    
    -- Create campaign instances with overlapping date ranges
    INSERT INTO campaign_instances (
        campaign_type, instance_name,
        active_start_date, active_end_date,  
        spread_start_date, spread_end_date,
        metadata
    ) VALUES
    ('high_priority_blast', 'Q2 2025 High Priority Blast',
     '2025-06-01', '2025-06-30', '2025-06-01', '2025-06-30',
     '{\"description\": \"High priority campaign ignoring exclusions\"}'),
     
    ('aep_special', 'AEP 2024 Special Campaign', 
     '2024-10-15', '2024-12-07', '2024-10-15', '2024-12-07',
     '{\"description\": \"AEP campaign respecting exclusions\"}'),
     
    ('newsletter', 'Monthly Newsletter June 2025',
     '2025-06-15', '2025-06-30', '2025-06-20', '2025-06-25', 
     '{\"description\": \"Low priority newsletter\"}'),
     
    ('urgent_compliance', 'Urgent Compliance Alert',
     '2025-06-10', '2025-06-12', '2025-06-10', '2025-06-10',
     '{\"description\": \"Urgent compliance - highest priority\"}');
    
    -- Create test contacts with overlapping eligibility
    INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES
    (1, 'multi1@test.com', 'CA', '1955-06-15', '2022-06-20'),  -- Birthday conflicts with campaigns
    (2, 'multi2@test.com', 'TX', '1960-07-01', '2021-12-15'),  -- No exclusions, eligible for all
    (3, 'multi3@test.com', 'NY', '1950-08-10', '2020-05-25'),  -- Year-round exclusion state
    (4, 'multi4@test.com', 'ID', '1965-06-25', '2023-01-10'),  -- ID exclusions
    (5, 'multi5@test.com', 'FL', '1958-03-15', '2019-11-30'),  -- No exclusions
    (6, 'multi6@test.com', 'VA', '1962-06-10', '2024-02-14'),  -- VA exclusions
    (7, 'multi7@test.com', 'MO', '1951-04-20', '2020-06-15'),  -- MO effective date exclusions
    (8, 'multi8@test.com', 'WA', '1957-09-05', '2018-07-22');  -- Year-round exclusion
    
    -- Enroll all contacts in all campaigns to test priority handling
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci;
    "
    
    echo -e "  ${GREEN}✅ Generated $db_file with 4 campaigns and 8 contacts${NC}"
    echo -e "  ${YELLOW}📊 Coverage: Priority conflicts + exclusion respect variations${NC}"
}

# Scenario 3: Date Boundary and Leap Year Testing  
generate_date_boundary_matrix() {
    local db_file="test_date_boundaries.db"
    rm -f "$db_file"
    
    echo -e "\n${PURPLE}📅 Scenario 3: Date Boundary and Leap Year Testing${NC}"
    echo "=================================================="
    
    setup_base_schema "$db_file"
    
    sqlite3 "$db_file" "
    INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES
    -- Leap year scenarios
    (1, 'leap1@test.com', 'CA', '1952-02-29', '2020-02-29'),   -- Born leap year, effective leap year
    (2, 'leap2@test.com', 'TX', '1956-02-29', '2023-03-01'),   -- Born leap year, effective non-leap
    (3, 'leap3@test.com', 'ID', '1960-02-29', '2021-02-28'),   -- Born leap year, effective day before
    (4, 'leap4@test.com', 'FL', '1964-02-29', '2022-03-01'),   -- Born leap year, effective day after
    
    -- Month boundary scenarios
    (5, 'month1@test.com', 'CA', '1955-01-31', '2020-01-31'),  -- January 31st
    (6, 'month2@test.com', 'NV', '1960-04-30', '2021-04-30'),  -- April 30th  
    (7, 'month3@test.com', 'OK', '1965-06-30', '2022-06-30'),  -- June 30th
    (8, 'month4@test.com', 'MD', '1950-09-30', '2019-09-30'),  -- September 30th
    (9, 'month5@test.com', 'OR', '1958-11-30', '2023-11-30'),  -- November 30th
    
    -- Year boundary scenarios  
    (10, 'year1@test.com', 'VA', '1962-12-31', '2024-12-31'),  -- December 31st
    (11, 'year2@test.com', 'KY', '1957-01-01', '2020-01-01'),  -- January 1st
    (12, 'year3@test.com', 'TX', '1963-12-30', '2021-01-02'),  -- Cross-year dates
    
    -- February edge cases (non-leap years)
    (13, 'feb1@test.com', 'CA', '1955-02-28', '2021-02-28'),   -- Feb 28 non-leap
    (14, 'feb2@test.com', 'ID', '1959-02-28', '2022-03-01'),   -- Feb 28 to Mar 1
    (15, 'feb3@test.com', 'MO', '1961-03-01', '2023-02-28'),   -- Mar 1 to Feb 28
    
    -- Time zone edge cases (if applicable)
    (16, 'tz1@test.com', 'WA', '1954-03-15', '2024-03-15'),    -- Around DST
    (17, 'tz2@test.com', 'NY', '1966-11-15', '2023-11-15'),    -- Around DST end
    
    -- Historical dates (far past)
    (18, 'hist1@test.com', 'FL', '1920-05-15', '1980-05-15'),  -- Very old dates
    (19, 'hist2@test.com', 'AZ', '1935-08-20', '1995-08-20'),  -- Historical
    
    -- Future dates  
    (20, 'fut1@test.com', 'TX', '1980-06-15', '2030-06-15'),   -- Future effective date
    (21, 'fut2@test.com', 'CA', '1985-09-25', '2035-09-25');   -- Far future
    "
    
    echo -e "  ${GREEN}✅ Generated $db_file with 21 contacts covering date edge cases${NC}"
    echo -e "  ${YELLOW}📊 Coverage: Leap years + month boundaries + year transitions${NC}"
}

# Scenario 4: Mixed Real-World Scenario
generate_mixed_realistic_scenario() {
    local db_file="test_mixed_realistic.db"
    rm -f "$db_file"
    
    echo -e "\n${PURPLE}🌍 Scenario 4: Mixed Real-World Scenario${NC}"
    echo "======================================="
    
    setup_base_schema "$db_file"
    
    sqlite3 "$db_file" "
    -- Create realistic campaign mix
    INSERT INTO campaign_types (
        name, respect_exclusion_windows, enable_followups, days_before_event,
        target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
    ) VALUES 
    ('aep', 1, 1, 7, 1, 20, 1, 1, 1),
    ('welcome_series', 1, 1, 0, 1, 40, 1, 1, 0),
    ('birthday_special', 0, 0, 3, 0, 15, 1, 0, 0),
    ('quarterly_update', 1, 0, 0, 1, 50, 1, 1, 0);
    
    INSERT INTO campaign_instances (
        campaign_type, instance_name,
        active_start_date, active_end_date,
        spread_start_date, spread_end_date
    ) VALUES
    ('aep', 'AEP 2024', '2024-10-15', '2024-12-07', '2024-10-15', '2024-12-07'),
    ('welcome_series', 'Q2 2025 Welcome', '2025-05-01', '2025-07-31', '2025-05-15', '2025-07-15'),
    ('birthday_special', 'Birthday Celebration 2025', '2025-01-01', '2025-12-31', '2025-01-01', '2025-12-31'),
    ('quarterly_update', 'Q2 2025 Update', '2025-06-01', '2025-06-30', '2025-06-15', '2025-06-20');
    
    -- Generate realistic contact distribution (100 contacts)
    INSERT INTO contacts (id, email, state, birth_date, effective_date, failed_underwriting) VALUES"
    
    # Generate 100 realistic contacts with distribution across states
    local states=("CA" "TX" "FL" "NY" "PA" "IL" "OH" "GA" "NC" "MI" "NJ" "VA" "WA" "AZ" "MA" "TN" "IN" "MD" "MO" "WI")
    local birth_years=(1945 1950 1955 1960 1965)
    local effective_years=(2018 2019 2020 2021 2022 2023 2024)
    
    for i in {1..100}; do
        local state=${states[$((RANDOM % ${#states[@]}))]}
        local birth_year=${birth_years[$((RANDOM % ${#birth_years[@]}))]}
        local birth_month=$(printf "%02d" $((RANDOM % 12 + 1)))
        local birth_day=$(printf "%02d" $((RANDOM % 28 + 1)))  # Avoid Feb 29 issues
        local eff_year=${effective_years[$((RANDOM % ${#effective_years[@]}))]}
        local eff_month=$(printf "%02d" $((RANDOM % 12 + 1)))
        local eff_day=$(printf "%02d" $((RANDOM % 28 + 1)))
        local failed_uw=$((RANDOM % 10 == 0 ? 1 : 0))  # 10% failed underwriting
        
        sqlite3 "$db_file" "
        INSERT INTO contacts (id, email, state, birth_date, effective_date, failed_underwriting) VALUES
        ($i, 'realistic${i}@test.com', '$state', '$birth_year-$birth_month-$birth_day', '$eff_year-$eff_month-$eff_day', $failed_uw);
        "
    done
    
    # Enroll contacts in campaigns realistically
    sqlite3 "$db_file" "
    -- Enroll everyone in AEP and quarterly update
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci 
    WHERE ci.campaign_type IN ('aep', 'quarterly_update');
    
    -- Enroll newer contacts (2023-2024) in welcome series
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active' 
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'welcome_series'
    AND c.effective_date >= '2023-01-01';
    
    -- Enroll random 30% in birthday special
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'birthday_special'
    AND (c.id % 3 = 0);  -- Every 3rd contact
    "
    
    echo -e "  ${GREEN}✅ Generated $db_file with 100 realistic contacts and 4 campaigns${NC}"
    echo -e "  ${YELLOW}📊 Coverage: Realistic distribution + campaign enrollment patterns${NC}"
}

# Scenario 5: Performance and Scaling Test
generate_performance_scenario() {
    local db_file="test_performance.db"
    rm -f "$db_file"
    
    echo -e "\n${PURPLE}⚡ Scenario 5: Performance and Scaling Test${NC}"
    echo "==========================================="
    
    setup_base_schema "$db_file"
    
    echo -e "  ${CYAN}Generating 1000 contacts for performance testing...${NC}"
    
    sqlite3 "$db_file" "
    -- Create single high-volume campaign
    INSERT INTO campaign_types (
        name, respect_exclusion_windows, enable_followups, days_before_event,
        target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting  
    ) VALUES ('performance_test', 1, 0, 0, 1, 30, 1, 1, 0);
    
    INSERT INTO campaign_instances (
        campaign_type, instance_name,
        active_start_date, active_end_date,
        spread_start_date, spread_end_date
    ) VALUES ('performance_test', 'Performance Test Campaign',
              '2025-06-01', '2025-06-30', '2025-06-01', '2025-06-30');
    "
    
    # Generate 1000 contacts for performance testing
    local states=("CA" "TX" "FL" "NY" "PA" "IL" "OH" "GA" "NC" "MI" "NJ" "VA" "WA" "AZ" "MA" "TN" "IN" "MD" "MO" "WI" "CT" "OR" "KY" "OK" "NV" "ID")
    
    echo -e "  ${CYAN}Inserting contacts in batches...${NC}"
    
    for batch in {1..10}; do
        echo -n "    Batch $batch/10..."
        
        local batch_sql="INSERT INTO contacts (id, email, state, birth_date, effective_date) VALUES "
        local values=""
        
        for i in {1..100}; do
            local contact_id=$(( (batch - 1) * 100 + i ))
            local state=${states[$((RANDOM % ${#states[@]}))]}
            local birth_year=$((1945 + RANDOM % 25))  # 1945-1970
            local birth_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local birth_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            local eff_year=$((2018 + RANDOM % 7))      # 2018-2024
            local eff_month=$(printf "%02d" $((RANDOM % 12 + 1)))
            local eff_day=$(printf "%02d" $((RANDOM % 28 + 1)))
            
            if [ $i -gt 1 ]; then
                values+=", "
            fi
            values+="($contact_id, 'perf${contact_id}@test.com', '$state', '$birth_year-$birth_month-$birth_day', '$eff_year-$eff_month-$eff_day')"
        done
        
        sqlite3 "$db_file" "${batch_sql}${values};"
        echo " ✅"
    done
    
    # Enroll all contacts in the performance test campaign
    sqlite3 "$db_file" "
    INSERT INTO contact_campaigns (contact_id, campaign_instance_id, status)
    SELECT c.id, ci.id, 'active'
    FROM contacts c
    CROSS JOIN campaign_instances ci
    WHERE ci.campaign_type = 'performance_test';
    "
    
    echo -e "  ${GREEN}✅ Generated $db_file with 1000 contacts for performance testing${NC}"
    echo -e "  ${YELLOW}📊 Coverage: High volume + distributed states + campaign enrollment${NC}"
}

# Generate all test scenarios
generate_all_scenarios() {
    echo -e "\n${BLUE}🚀 Generating All Test Scenarios${NC}"
    echo "================================="
    
    generate_birthday_rule_matrix
    generate_campaign_priority_matrix  
    generate_date_boundary_matrix
    generate_mixed_realistic_scenario
    generate_performance_scenario
    
    echo -e "\n${GREEN}🎉 All Test Scenarios Generated Successfully!${NC}"
    echo "=============================================="
    echo ""
    echo "Generated test databases:"
    echo "  📁 test_birthday_matrix.db     - Birthday exclusion rule testing"
    echo "  📁 test_campaign_priority.db   - Campaign priority and conflict testing"
    echo "  📁 test_date_boundaries.db     - Date edge cases and leap year testing"
    echo "  📁 test_mixed_realistic.db     - Real-world mixed scenario (100 contacts)"
    echo "  📁 test_performance.db         - Performance testing (1000 contacts)"
    echo ""
    echo "Usage:"
    echo "  ./validate_test_scenarios.sh                    # Run all validations"
    echo "  dune exec campaign_aware_scheduler test_*.db    # Test individual scenarios"
    echo "  ./run_comprehensive_tests.sh                    # Full test suite"
}

# Command line argument processing
case "${1:-all}" in
    "birthday"|"1")
        generate_birthday_rule_matrix
        ;;
    "campaign"|"priority"|"2")
        generate_campaign_priority_matrix
        ;;
    "dates"|"boundaries"|"3")
        generate_date_boundary_matrix
        ;;
    "realistic"|"mixed"|"4")
        generate_mixed_realistic_scenario
        ;;
    "performance"|"scale"|"5")
        generate_performance_scenario
        ;;
    "all"|*)
        generate_all_scenarios
        ;;
esac

echo -e "\n${CYAN}💡 Next Steps:${NC}"
echo "1. Run individual schedulers: dune exec campaign_aware_scheduler <db_file>"
echo "2. Validate results: ./validate_test_scenarios.sh"
echo "3. Performance testing: time dune exec campaign_aware_scheduler test_performance.db"
echo "4. Compare outputs: ./compare_scheduler_results.sh"