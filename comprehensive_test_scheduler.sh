#!/bin/bash

# Comprehensive Test Scheduler
# Uses the full scheduling system that handles both anniversaries AND campaigns

set -e

echo "🚀 Comprehensive Campaign + Anniversary Test Scheduler"
echo "====================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

if [ $# -ne 2 ]; then
    echo "Usage: $0 <database_path> <test_description>"
    echo "Example: $0 test_initial_blast.db 'Initial Blast Campaign Test'"
    exit 1
fi

DB_PATH="$1"
TEST_DESC="$2"

echo -e "${BLUE}🗃️  Database: $DB_PATH${NC}"
echo -e "${BLUE}📝 Test: $TEST_DESC${NC}"
echo ""

# Show test setup
echo -e "${PURPLE}📋 Test Data Overview:${NC}"

echo -e "\n${BLUE}👥 Contacts:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    c.email,
    c.state,
    COALESCE(c.birth_date, 'N/A') as birthday,
    COALESCE(c.effective_date, 'N/A') as policy_date,
    'Age ' || (2025 - substr(COALESCE(c.birth_date, '2000-01-01'), 1, 4)) as age
FROM contacts c
ORDER BY c.email;
" | while IFS='|' read email state birthday policy age; do
    echo "  📧 $email ($state) - Birthday: $birthday, Policy: $policy ($age)"
done

echo -e "\n${BLUE}📊 Campaign Types:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    name,
    priority,
    days_before_event,
    CASE respect_exclusion_windows WHEN 1 THEN 'YES' ELSE 'NO' END as respects_exclusions,
    CASE active WHEN 1 THEN 'ACTIVE' ELSE 'INACTIVE' END as status
FROM campaign_types
ORDER BY priority;
" | while IFS='|' read name priority days exclusions status; do
    echo "  📊 $name: Priority $priority, $days days before, Exclusions: $exclusions ($status)"
done

echo -e "\n${BLUE}📅 Campaign Instances:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    ci.campaign_type,
    ci.instance_name,
    ci.active_start_date,
    ci.active_end_date,
    COALESCE(ci.target_states, 'ALL') as states
FROM campaign_instances ci
ORDER BY ci.active_start_date;
" | while IFS='|' read type instance start_date end_date states; do
    echo "  📅 $instance ($type): $start_date to $end_date, States: $states"
done

echo -e "\n${BLUE}🎯 Campaign Enrollments:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    c.email,
    ci.campaign_type,
    ci.instance_name,
    cc.status
FROM contact_campaigns cc
JOIN contacts c ON cc.contact_id = c.id  
JOIN campaign_instances ci ON cc.campaign_instance_id = ci.id
ORDER BY c.email, ci.campaign_type;
" | while IFS='|' read email campaign instance status; do
    echo "  🎯 $email enrolled in $instance ($campaign) - $status"
done

# Use the main demo scheduler which calls schedule_emails_streaming (handles both anniversaries and campaigns)
echo -e "\n${GREEN}🚀 Running Comprehensive Scheduler...${NC}"
echo "Using the full schedule_emails_streaming function that handles both anniversaries AND campaigns"
echo ""

# Set the database path and run the main demo scheduler
DATABASE_PATH="$DB_PATH" dune exec scheduler

echo -e "\n${GREEN}📋 Generated Email Schedules:${NC}"

# Show all generated schedules with details
sqlite3 "$DB_PATH" "
SELECT 
    c.email,
    c.state,
    es.email_type,
    es.scheduled_send_date,
    es.status,
    COALESCE(es.skip_reason, 'N/A') as skip_reason,
    CASE 
        WHEN es.email_type IN ('birthday', 'effective_date', 'post_window') THEN 'Anniversary'
        ELSE 'Campaign'
    END as category
FROM email_schedules es
JOIN contacts c ON es.contact_id = c.id
ORDER BY es.scheduled_send_date, c.email, es.email_type;
" | while IFS='|' read email state type date status reason category; do
    if [ "$status" = "skipped" ]; then
        echo -e "  ${YELLOW}⚠️  $email ($state) - $type on $date [$category] (SKIPPED: $reason)${NC}"
    else
        if [ "$category" = "Campaign" ]; then
            echo -e "  ${PURPLE}🎯 $email ($state) - $type on $date [$category] ($status)${NC}"
        else
            echo -e "  ${GREEN}✅ $email ($state) - $type on $date [$category] ($status)${NC}"
        fi
    fi
done

# Summary by email type and category
echo -e "\n${BLUE}📈 Summary by Email Type:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    es.email_type,
    es.status,
    COUNT(*) as count,
    CASE 
        WHEN es.email_type IN ('birthday', 'effective_date', 'post_window') THEN 'Anniversary'
        ELSE 'Campaign'
    END as category
FROM email_schedules es
GROUP BY es.email_type, es.status, category
ORDER BY category, es.email_type, es.status;
" | while IFS='|' read type status count category; do
    echo "  [$category] $type: $count $status"
done

# Summary by category
echo -e "\n${BLUE}📊 Summary by Category:${NC}"
sqlite3 "$DB_PATH" "
SELECT 
    CASE 
        WHEN es.email_type IN ('birthday', 'effective_date', 'post_window') THEN 'Anniversary'
        ELSE 'Campaign'
    END as category,
    es.status,
    COUNT(*) as count
FROM email_schedules es
GROUP BY category, es.status
ORDER BY category, es.status;
" | while IFS='|' read category status count; do
    echo "  $category emails: $count $status"
done

echo -e "\n${GREEN}✅ Comprehensive Test Complete!${NC}"
echo "========================================"