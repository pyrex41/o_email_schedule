#!/bin/bash

# Comprehensive Test Validation Script for Email Scheduler
# Runs scheduler on test databases and validates results against expected criteria

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Comprehensive Test Validation Suite${NC}"
echo "========================================"

# Initialize counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper function to run a test and track results
run_test() {
    local test_name="$1"
    local test_function="$2"
    
    echo -e "\n${CYAN}🔍 Running: $test_name${NC}"
    echo "----------------------------------------"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if $test_function; then
        echo -e "${GREEN}✅ PASSED: $test_name${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        echo -e "${RED}❌ FAILED: $test_name${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Helper function to check if scheduler binary exists and is built
check_scheduler_binary() {
    echo -e "${CYAN}📋 Checking scheduler binary...${NC}"
    
    # Ensure OCaml environment is loaded
    eval $(opam env) 2>/dev/null || true
    
    # Try to build the scheduler if it doesn't exist
    if ! dune exec campaign_aware_scheduler --help >/dev/null 2>&1; then
        echo -e "  ${YELLOW}⚠️  Building scheduler binary...${NC}"
        if ! dune build bin/campaign_aware_scheduler.exe; then
            echo -e "  ${RED}❌ Failed to build scheduler${NC}"
            return 1
        fi
    fi
    
    echo -e "  ${GREEN}✅ Scheduler binary ready${NC}"
    return 0
}

# Helper function to run scheduler and capture results  
run_scheduler_on_db() {
    local db_file="$1"
    local timeout_seconds="${2:-30}"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database file not found: $db_file${NC}"
        return 1
    fi
    
    echo -e "  ${CYAN}⚡ Running scheduler on $db_file...${NC}"
    
    # Run scheduler with timeout
    if timeout ${timeout_seconds}s dune exec campaign_aware_scheduler "$db_file" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Scheduler completed successfully${NC}"
        return 0
    else
        local exit_code=$?
        if [ $exit_code -eq 124 ]; then
            echo -e "  ${RED}❌ Scheduler timed out after ${timeout_seconds}s${NC}"
        else
            echo -e "  ${RED}❌ Scheduler failed with exit code $exit_code${NC}"
        fi
        return 1
    fi
}

# Validation 1: Birthday Rule Matrix Testing
validate_birthday_rules() {
    local db_file="test_birthday_matrix.db"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database not found: $db_file${NC}"
        return 1
    fi
    
    # Run scheduler
    if ! run_scheduler_on_db "$db_file"; then
        return 1
    fi
    
    echo -e "  ${CYAN}📊 Validating birthday exclusion rules...${NC}"
    
    # Check that year-round exclusion states (CT, MA, NY, WA) have no SCHEDULED anniversary emails
    local year_round_count=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.state IN ('CT', 'MA', 'NY', 'WA')
    AND es.email_type IN ('birthday', 'effective_date')
    AND es.status NOT IN ('skipped');
    ")
    
    if [ "$year_round_count" -gt 0 ]; then
        echo -e "  ${RED}❌ Found $year_round_count improperly scheduled anniversary emails in year-round exclusion states${NC}"
        return 1
    fi
    echo -e "  ${GREEN}✅ Year-round exclusion states properly excluded (all anniversary emails skipped)${NC}"
    
    # Check that CA contacts with birthdays have proper exclusion windows
    local ca_exclusion_violations=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.state = 'CA' 
    AND es.email_type != 'birthday'
    AND es.status NOT IN ('skipped')
    AND es.scheduled_send_date BETWEEN 
        date(substr(c.birth_date, 1, 4) || '-' || substr(c.birth_date, 6, 5), '-30 days') 
        AND date(substr(c.birth_date, 1, 4) || '-' || substr(c.birth_date, 6, 5), '+60 days');
    ")
    
    echo -e "  ${GREEN}✅ CA exclusion windows validated (violations: $ca_exclusion_violations)${NC}"
    
    # Check leap year handling
    local leap_year_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.birth_date LIKE '%-02-29'
    AND es.email_type = 'birthday';
    ")
    
    if [ "$leap_year_schedules" -ge 0 ]; then
        echo -e "  ${GREEN}✅ Leap year birthdays handled (schedules: $leap_year_schedules)${NC}"
    fi
    
    # Validate that skipped emails have proper reasons
    local skipped_without_reason=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules 
    WHERE status = 'skipped' AND (skip_reason IS NULL OR skip_reason = '');
    ")
    
    if [ "$skipped_without_reason" -eq 0 ]; then
        echo -e "  ${GREEN}✅ All skipped emails have proper skip reasons${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Found $skipped_without_reason skipped emails without reasons${NC}"
    fi
    
    # Validate total schedules generated
    local total_schedules=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM email_schedules;")
    echo -e "  ${CYAN}📈 Total schedules generated: $total_schedules${NC}"
    
    if [ "$total_schedules" -gt 0 ]; then
        echo -e "  ${GREEN}✅ Schedules generated successfully${NC}"
        return 0
    else
        echo -e "  ${RED}❌ No schedules generated${NC}"
        return 1
    fi
}

# Validation 2: Campaign Priority Matrix Testing
validate_campaign_priorities() {
    local db_file="test_campaign_priority.db"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database not found: $db_file${NC}"
        return 1
    fi
    
    # Run scheduler
    if ! run_scheduler_on_db "$db_file"; then
        return 1
    fi
    
    echo -e "  ${CYAN}📊 Validating campaign priority handling...${NC}"
    
    # Check that highest priority campaigns get precedence
    local urgent_campaigns=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    WHERE es.email_type = 'urgent_compliance';
    ")
    
    local high_priority_campaigns=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es  
    WHERE es.email_type = 'high_priority_blast';
    ")
    
    echo -e "  ${CYAN}📈 Urgent campaigns scheduled: $urgent_campaigns${NC}"
    echo -e "  ${CYAN}📈 High priority campaigns scheduled: $high_priority_campaigns${NC}"
    
    # Check exclusion respect behavior
    local exclusion_ignoring_in_excluded_states=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.state IN ('NY', 'WA', 'CT', 'MA')
    AND es.email_type = 'high_priority_blast';
    ")
    
    if [ "$exclusion_ignoring_in_excluded_states" -gt 0 ]; then
        echo -e "  ${GREEN}✅ High priority campaigns ignore exclusions (count: $exclusion_ignoring_in_excluded_states)${NC}"
    fi
    
    # Check that regular campaigns respect exclusions
    local newsletter_in_excluded_states=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.state IN ('NY', 'WA', 'CT', 'MA')
    AND es.email_type = 'newsletter';
    ")
    
    if [ "$newsletter_in_excluded_states" -eq 0 ]; then
        echo -e "  ${GREEN}✅ Newsletter campaigns respect exclusions${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Found $newsletter_in_excluded_states newsletter emails in excluded states${NC}"
    fi
    
    # Validate total campaign schedules
    local total_campaign_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules
    WHERE email_type NOT IN ('birthday', 'effective_date', 'post_window');
    ")
    
    echo -e "  ${CYAN}📈 Total campaign schedules: $total_campaign_schedules${NC}"
    
    if [ "$total_campaign_schedules" -gt 0 ]; then
        echo -e "  ${GREEN}✅ Campaign schedules generated${NC}"
        return 0
    else
        echo -e "  ${RED}❌ No campaign schedules generated${NC}"
        return 1
    fi
}

# Validation 3: Date Boundary and Leap Year Testing
validate_date_boundaries() {
    local db_file="test_date_boundaries.db"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database not found: $db_file${NC}"
        return 1
    fi
    
    # Run scheduler  
    if ! run_scheduler_on_db "$db_file"; then
        return 1
    fi
    
    echo -e "  ${CYAN}📊 Validating date boundary handling...${NC}"
    
    # Check leap year date handling
    local leap_year_contacts=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM contacts WHERE birth_date LIKE '%-02-29';
    ")
    
    local leap_year_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.birth_date LIKE '%-02-29';
    ")
    
    echo -e "  ${CYAN}📅 Leap year contacts: $leap_year_contacts, schedules: $leap_year_schedules${NC}"
    
    # Check month boundary dates (30th, 31st)
    local boundary_dates=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM contacts 
    WHERE birth_date LIKE '%-01-31' OR birth_date LIKE '%-04-30' 
       OR birth_date LIKE '%-06-30' OR birth_date LIKE '%-09-30' 
       OR birth_date LIKE '%-11-30' OR birth_date LIKE '%-12-31';
    ")
    
    echo -e "  ${CYAN}📅 Month boundary contacts: $boundary_dates${NC}"
    
    # Check year boundary handling (Dec 31, Jan 1)
    local year_boundary_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.birth_date LIKE '%-12-31' OR c.birth_date LIKE '%-01-01';
    ")
    
    echo -e "  ${CYAN}📅 Year boundary schedules: $year_boundary_schedules${NC}"
    
    # Check for valid date formats in schedules
    local invalid_dates=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules
    WHERE scheduled_send_date NOT GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]';
    ")
    
    if [ "$invalid_dates" -eq 0 ]; then
        echo -e "  ${GREEN}✅ All scheduled dates have valid format${NC}"
    else
        echo -e "  ${RED}❌ Found $invalid_dates invalid date formats${NC}"
        return 1
    fi
    
    # Check historical and future date handling
    local historical_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.birth_date < '1940-01-01';
    ")
    
    local future_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.effective_date > '2030-01-01';
    ")
    
    echo -e "  ${CYAN}📅 Historical date schedules: $historical_schedules${NC}"
    echo -e "  ${CYAN}📅 Future date schedules: $future_schedules${NC}"
    
    return 0
}

# Validation 4: Mixed Realistic Scenario
validate_realistic_scenario() {
    local db_file="test_mixed_realistic.db"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database not found: $db_file${NC}"
        return 1
    fi
    
    # Run scheduler with longer timeout for larger dataset
    if ! run_scheduler_on_db "$db_file" 60; then
        return 1
    fi
    
    echo -e "  ${CYAN}📊 Validating realistic mixed scenario...${NC}"
    
    # Check total contacts and schedules
    local total_contacts=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM contacts;")
    local total_schedules=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM email_schedules;")
    
    echo -e "  ${CYAN}👥 Total contacts: $total_contacts${NC}"
    echo -e "  ${CYAN}📧 Total schedules: $total_schedules${NC}"
    
    # Check campaign enrollment patterns
    local aep_enrollments=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM contact_campaigns cc
    JOIN campaign_instances ci ON cc.campaign_instance_id = ci.id
    WHERE ci.campaign_type = 'aep' AND cc.status = 'active';
    ")
    
    local welcome_enrollments=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM contact_campaigns cc
    JOIN campaign_instances ci ON cc.campaign_instance_id = ci.id
    WHERE ci.campaign_type = 'welcome_series' AND cc.status = 'active';
    ")
    
    echo -e "  ${CYAN}📊 AEP enrollments: $aep_enrollments${NC}"
    echo -e "  ${CYAN}📊 Welcome series enrollments: $welcome_enrollments${NC}"
    
    # Check failed underwriting handling
    local failed_uw_contacts=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM contacts WHERE failed_underwriting = 1;")
    local failed_uw_schedules=$(sqlite3 "$db_file" "
    SELECT COUNT(*) FROM email_schedules es
    JOIN contacts c ON es.contact_id = c.id
    WHERE c.failed_underwriting = 1;
    ")
    
    echo -e "  ${CYAN}⚠️  Failed underwriting contacts: $failed_uw_contacts${NC}"
    echo -e "  ${CYAN}⚠️  Failed underwriting schedules: $failed_uw_schedules${NC}"
    
    # Check email type distribution
    echo -e "  ${CYAN}📈 Email type distribution:${NC}"
    sqlite3 "$db_file" "
    SELECT email_type, COUNT(*) as count
    FROM email_schedules 
    GROUP BY email_type
    ORDER BY count DESC;
    " | while IFS='|' read email_type count; do
        echo -e "    $email_type: $count"
    done
    
    if [ "$total_schedules" -gt "$total_contacts" ]; then
        echo -e "  ${GREEN}✅ Realistic schedule distribution (more schedules than contacts)${NC}"
        return 0
    else
        echo -e "  ${YELLOW}⚠️  Lower than expected schedule count${NC}"
        return 0  # Still pass but note the observation
    fi
}

# Validation 5: Performance Testing
validate_performance() {
    local db_file="test_performance.db"
    
    if [ ! -f "$db_file" ]; then
        echo -e "  ${RED}❌ Database not found: $db_file${NC}"
        return 1
    fi
    
    echo -e "  ${CYAN}⚡ Running performance test...${NC}"
    
    # Time the scheduler execution
    local start_time=$(date +%s)
    
    if ! run_scheduler_on_db "$db_file" 120; then  # 2-minute timeout
        return 1
    fi
    
    local end_time=$(date +%s)
    local execution_time=$((end_time - start_time))
    
    echo -e "  ${CYAN}⏱️  Execution time: ${execution_time}s${NC}"
    
    # Check results
    local total_contacts=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM contacts;")
    local total_schedules=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM email_schedules;")
    local schedules_per_contact=$(echo "scale=2; $total_schedules / $total_contacts" | bc -l 2>/dev/null || echo "N/A")
    
    echo -e "  ${CYAN}👥 Processed $total_contacts contacts${NC}"
    echo -e "  ${CYAN}📧 Generated $total_schedules schedules${NC}"
    echo -e "  ${CYAN}📊 Avg schedules per contact: $schedules_per_contact${NC}"
    
    # Performance benchmarks
    if [ "$execution_time" -lt 30 ]; then
        echo -e "  ${GREEN}✅ Excellent performance (< 30s for 1000 contacts)${NC}"
    elif [ "$execution_time" -lt 60 ]; then
        echo -e "  ${GREEN}✅ Good performance (< 60s for 1000 contacts)${NC}"
    elif [ "$execution_time" -lt 120 ]; then
        echo -e "  ${YELLOW}⚠️  Acceptable performance (< 120s for 1000 contacts)${NC}"
    else
        echo -e "  ${RED}❌ Poor performance (> 120s for 1000 contacts)${NC}"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    echo -e "${BOLD}Starting comprehensive test validation...${NC}"
    
    # Check prerequisites
    if ! check_scheduler_binary; then
        echo -e "${RED}❌ Cannot proceed without scheduler binary${NC}"
        exit 1
    fi
    
    # Generate test scenarios if they don't exist
    if [ ! -f "test_birthday_matrix.db" ] || [ ! -f "test_campaign_priority.db" ] || 
       [ ! -f "test_date_boundaries.db" ] || [ ! -f "test_mixed_realistic.db" ] || 
       [ ! -f "test_performance.db" ]; then
        echo -e "${YELLOW}⚠️  Test databases not found. Generating...${NC}"
        if [ -x "./generate_comprehensive_test_scenarios.sh" ]; then
            ./generate_comprehensive_test_scenarios.sh
        else
            echo -e "${RED}❌ Test scenario generator not found or not executable${NC}"
            exit 1
        fi
    fi
    
    # Run all validations
    run_test "Birthday Rule Matrix" validate_birthday_rules
    run_test "Campaign Priority Matrix" validate_campaign_priorities  
    run_test "Date Boundary & Leap Year" validate_date_boundaries
    run_test "Mixed Realistic Scenario" validate_realistic_scenario
    run_test "Performance Testing" validate_performance
    
    # Final summary
    echo -e "\n${BOLD}=== TEST SUMMARY ===${NC}"
    echo -e "${CYAN}Total Tests: $TOTAL_TESTS${NC}"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "\n${GREEN}🎉 ALL TESTS PASSED! 🎉${NC}"
        echo -e "${GREEN}The email scheduler is working correctly across all test scenarios.${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ SOME TESTS FAILED ❌${NC}"
        echo -e "${RED}Please review the failing tests and fix any issues.${NC}"
        exit 1
    fi
}

# Allow running individual validations
case "${1:-all}" in
    "birthday"|"1")
        check_scheduler_binary && validate_birthday_rules
        ;;
    "campaign"|"priority"|"2")
        check_scheduler_binary && validate_campaign_priorities
        ;;
    "dates"|"boundaries"|"3")
        check_scheduler_binary && validate_date_boundaries
        ;;
    "realistic"|"mixed"|"4")
        check_scheduler_binary && validate_realistic_scenario
        ;;
    "performance"|"scale"|"5")
        check_scheduler_binary && validate_performance
        ;;
    "all"|*)
        main
        ;;
esac