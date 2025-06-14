# Massive Performance Test Report

**Generated:** Fri Jun 13 09:26:05 PM UTC 2025  
**Contacts:** 1000  
**Batch Size:** 500  
**Database:** massive_performance_test.db  

## Executive Summary



## Detailed Performance Metrics

### Contact Generation Performance


### Scheduler Execution Performance


## Database Statistics

### Contact Distribution
- **CA:** 144 contacts (14.4%), 17 failed underwriting
- **TX:** 114 contacts (11.4%), 10 failed underwriting
- **FL:** 71 contacts (7.1%), 4 failed underwriting
- **PA:** 52 contacts (5.2%), 8 failed underwriting
- **NY:** 50 contacts (5.0%), 5 failed underwriting
- **OH:** 46 contacts (4.6%), 3 failed underwriting
- **IL:** 42 contacts (4.2%), 2 failed underwriting
- **GA:** 27 contacts (2.7%), 5 failed underwriting
- **MI:** 27 contacts (2.7%), 4 failed underwriting
- **LA:** 20 contacts (2.0%), 2 failed underwriting
- **RI:** 20 contacts (2.0%), 3 failed underwriting
- **NM:** 18 contacts (1.8%), 1 failed underwriting
- **UT:** 18 contacts (1.8%), 1 failed underwriting
- **NV:** 17 contacts (1.7%), 1 failed underwriting
- **VT:** 17 contacts (1.7%), 3 failed underwriting

### Email Schedule Distribution  
- **birthday:** 1000 total, 686 scheduled, 314 skipped (31.4%)
- **campaign_mega_newsletter_2:** 1000 total, 823 scheduled, 177 skipped (17.7%)
- **campaign_renewal_blast_4:** 1000 total, 825 scheduled, 175 skipped (17.5%)
- **effective_date:** 992 total, 797 scheduled, 195 skipped (19.7%)
- **post_window:** 92 total, 92 scheduled, 0 skipped (0.0%)

### Campaign Performance
- **Massive Newsletter 2025** (mega_newsletter): 100 contacts enrolled, 100 schedules (1.0 per contact)
- **Birthday Mega Campaign** (birthday_mega_special): 20 contacts enrolled, 0 schedules (0.0 per contact)
- **Renewal Reminder Blast** (renewal_blast): 10 contacts enrolled, 10 schedules (1.0 per contact)
- **Default AEP 2025** (aep): 0 contacts enrolled, 0 schedules (0.0 per contact)
- **Urgent Compliance Update** (compliance_alert): 0 contacts enrolled, 0 schedules (0.0 per contact)

## Performance Benchmarks

### Memory Usage Analysis

Memory usage tracked during execution:

- Process Memory: 2MB min, 2MB max, 2.0MB avg
- System Memory: 8.3% min, 8.3% max, 8.3% avg"


## Scale Comparison

### Performance Scaling Analysis
Contacts per Second: 0\nSchedules per Second: 0\nMemory per Contact: 0.00MB\nSchedules per Contact: 0.00\nTime per 1000 Contacts: 0.00s

### Database Efficiency
Database Size: 1MB\nContacts per MB: 1000\nSchedules per MB: 4084

## Bottleneck Analysis

Based on the performance metrics:



## Recommendations

### Production Deployment
1. **Memory Allocation**: Ensure at least MB available RAM
2. **Execution Time**: Budget 0.0 minutes for similar contact volumes
3. **Database Optimization**: Current setup handles 0 contacts/second efficiently

### Scaling Considerations  
- **Linear Scaling**: Performance appears to scale linearly with contact count
- **Memory Efficiency**: System uses approximately 0.00MB per 1000 contacts
- **Optimal Batch Size**: Current batch size of 500 performs well

## Raw Data Files

- Performance Database: `massive_performance_test.db`
- Performance Metrics: `performance_metrics` table
- Memory Usage Log: `performance_results_20250613_212556/memory_usage.csv`
- Full Report: `performance_results_20250613_212556/MASSIVE_PERFORMANCE_REPORT.md`

