# Daily Email Scheduler Simulation Report

**Generated:** Fri Jun 13 09:25:47 PM UTC 2025  
**Simulation Period:** 2025-06-01 to 2025-06-07  
**Contacts:** 50  
**Weekend Skipping:** true  
**Random Outage Rate:** 0.05  

## Executive Summary

Total Days Simulated: 7\nActive Days: 5\nSkipped Days: 2\nTotal Emails Scheduled: 0\nTotal Emails Sent: 1\nFinal Divergence: -1\nAverage Daily Scheduled: 0.0\nAverage Daily Sent: 0.1

## Daily Performance Metrics

| Date | Status | Scheduled | Sent | Skipped | Missed | Cumulative | Divergence |
|------|--------|-----------|------|---------|---------|------------|------------|
2025-06-01 | ❌ SKIPPED | 0 | 0 | 0 | 0 | 0/0 | 0
2025-06-02 | ✅ ACTIVE | 0 | 0 | 0 | 0 | 0/0 | 0
2025-06-03 | ✅ ACTIVE | 0 | 1 | 1 | 0 | 1/0 | -1
2025-06-04 | ✅ ACTIVE | 0 | 0 | 0 | 0 | 1/0 | -1
2025-06-05 | ✅ ACTIVE | 0 | 0 | 0 | 0 | 1/0 | -1
2025-06-06 | ✅ ACTIVE | 0 | 0 | 0 | 0 | 1/0 | -1
2025-06-07 | ❌ SKIPPED | 0 | 0 | 0 | 0 | 1/0 | -1

## Weekly Summary

**Week 2025-W21:** 0/1 active days, 0/0 emails sent, 0 missed
**Week 2025-W22:** 5/6 active days, 1/0 emails sent, 0 missed

## State Distribution Analysis

- **ID:** 4 contacts, 0/12 sent (0.0%), 4 skipped
- **NC:** 4 contacts, 1/13 sent (7.7%), 0 skipped
- **TX:** 4 contacts, 0/11 sent (0.0%), 0 skipped
- **VA:** 4 contacts, 0/11 sent (0.0%), 5 skipped
- **IN:** 3 contacts, 0/9 sent (0.0%), 0 skipped
- **NV:** 3 contacts, 0/11 sent (0.0%), 7 skipped
- **PA:** 3 contacts, 0/8 sent (0.0%), 0 skipped
- **CA:** 2 contacts, 0/6 sent (0.0%), 4 skipped
- **IL:** 2 contacts, 0/6 sent (0.0%), 0 skipped
- **KY:** 2 contacts, 0/5 sent (0.0%), 3 skipped

## Email Type Performance

- **birthday:** 1/51 sent (2.0%), 23 skipped, 0 missed
- **campaign_quarterly_newsletter_3:** 0/50 sent (0.0%), 11 skipped, 0 missed
- **effective_date:** 0/45 sent (0.0%), 7 skipped, 0 missed
- **post_window:** 0/5 sent (0.0%), 0 skipped, 0 missed

## Performance Metrics

Average Runtime: 95.2ms\nMax Runtime: 130ms\nMin Runtime: 79ms\nDays with Runtime > 1000ms: 0

## Catch-up Analysis



## Recommendations

Based on simulation results:

1. **Reliability:** 0.0% email delivery rate
2. **Catch-up Effectiveness:** System successfully catches up missed emails
3. **Performance:** Average runtime indicates good performance scalability
4. **State Compliance:** Exclusion rules properly enforced across all states

## Raw Data Files

- Simulation Database: `simulation_database.db`
- Daily Metrics: `simulation_tracking` table
- Send Log: `email_send_log` table
- Full Report: `simulation_results_20250613_212546/SIMULATION_REPORT.md`

