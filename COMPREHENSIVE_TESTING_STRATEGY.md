# Comprehensive Testing Strategy for Email Scheduler

## Overview
This document outlines a thorough testing strategy for the email scheduler system, focusing on campaigns, birthday exclusion rules, and arbitrary date handling. The testing approach combines automated database scenarios, edge case validation, and systematic coverage of all business rules.

## Testing Categories

### 1. Campaign Testing

#### A. Campaign Type Coverage
- **AEP Campaigns**: October 15 - December 7 enrollment periods
- **Initial Blast Campaigns**: Spread over configurable date ranges
- **Newsletter Campaigns**: Regular recurring campaigns
- **Custom Campaigns**: User-defined campaigns with various settings

#### B. Campaign Priority Testing
- **Priority Conflicts**: Multiple campaigns targeting same contacts
- **Anniversary vs Campaign**: Birthday/effective date emails vs campaigns
- **Exclusion Respect**: Campaigns that respect vs ignore exclusion windows

#### C. Campaign Date Range Testing
- **Spread Distribution**: Even distribution across campaign date ranges
- **Boundary Dates**: Start/end date edge cases
- **Overlapping Campaigns**: Multiple active campaigns with overlapping periods

### 2. Birthday Exclusion Rules Testing

#### A. State-Specific Windows
- **CA**: 30 days before, 60 days after birthday
- **ID**: 0 days before, 63 days after birthday  
- **KY**: 0 days before, 60 days after birthday
- **MD**: 0 days before, 30 days after birthday
- **NV**: 0 days before, 60 days after (month-start alignment)
- **OK**: 0 days before, 60 days after birthday
- **OR**: 0 days before, 31 days after birthday
- **VA**: 0 days before, 30 days after birthday
- **MO**: Effective date exclusion: 30 days before, 33 days after
- **Year-round exclusions**: CT, MA, NY, WA

#### B. Edge Cases
- **Leap Year Birthdays**: February 29th handling
- **Month Boundaries**: Birthday on first/last day of month
- **Year Transitions**: Birthday exclusions across year boundaries
- **Multiple Anniversaries**: Overlapping birthday and effective date exclusions

### 3. Arbitrary Date Handling

#### A. Date Range Testing
- **Past Dates**: Historical scheduling scenarios
- **Future Dates**: Long-term scheduling validation
- **Current Date**: Real-time scheduling accuracy

#### B. Date Arithmetic
- **Anniversary Calculations**: Next anniversary from any arbitrary date
- **Exclusion Windows**: Window calculations across date boundaries
- **Buffer Days**: Pre/post exclusion buffer handling

#### C. Calendar Edge Cases
- **Leap Years**: February 29th anniversary calculations
- **Month Lengths**: 28, 29, 30, 31 day month handling
- **DST Transitions**: Time zone handling if applicable

## Automated Testing Framework

### 1. Database Scenario Generator

```bash
# Generate test databases with various scenarios
./generate_test_scenarios.sh --campaigns --birthdays --dates
```

Features:
- **Contact Generation**: Random contacts with distributed states/dates
- **Campaign Setup**: Automated campaign instance creation
- **Data Validation**: Constraint checking and referential integrity

### 2. Scheduler Validation

```bash
# Run scheduler against test scenarios and validate results
./validate_scheduler_results.sh --database test_scenario.db --expected results.json
```

Features:
- **Result Validation**: Compare actual vs expected scheduling results
- **Rule Compliance**: Verify exclusion rules are properly applied
- **Performance Metrics**: Track scheduling performance across scenarios

### 3. Regression Testing

```bash
# Comprehensive regression test suite
./run_regression_tests.sh --full-coverage
```

Features:
- **Golden Master**: Compare against known-good results
- **Edge Case Matrix**: Systematic testing of boundary conditions
- **Performance Benchmarks**: Ensure performance doesn't degrade

## Test Scenarios

### Scenario 1: Multi-State Campaign with Birthday Conflicts
- **Contacts**: 100 contacts across all states
- **Campaigns**: AEP campaign during birthday exclusion periods
- **Validation**: Verify state-specific exclusions are respected

### Scenario 2: Leap Year Anniversary Handling
- **Contacts**: Born February 29th in various leap years
- **Test Dates**: Non-leap years and subsequent leap years
- **Validation**: Proper anniversary date calculation

### Scenario 3: Campaign Priority Matrix
- **Campaigns**: Multiple overlapping campaigns with different priorities
- **Contacts**: Same contacts eligible for multiple campaigns
- **Validation**: Highest priority campaign emails are scheduled

### Scenario 4: Historical Data Processing
- **Date Range**: Past 2 years of data
- **Scenarios**: Retroactive scheduling validation
- **Validation**: Proper handling of historical anniversary dates

### Scenario 5: State Exclusion Boundary Testing
- **Test Cases**: Emails scheduled on exact boundary dates
- **States**: All states with exclusion windows
- **Validation**: Precise exclusion window enforcement

## Implementation Tools

### 1. SQLite-Based Test Harness
```sql
-- Generate comprehensive test data
.read generate_test_contacts.sql
.read setup_campaign_scenarios.sql
.read validate_scheduling_results.sql
```

### 2. OCaml Test Generators
```ocaml
(* Property-based testing for date calculations *)
let test_anniversary_calculation = ...
let test_exclusion_windows = ...
let test_campaign_priority = ...
```

### 3. Shell Script Automation
```bash
# Full test suite execution
./comprehensive_test_suite.sh
```

## Success Criteria

### 1. Campaign Testing
- ✅ All campaign types schedule correctly
- ✅ Priority handling works as expected
- ✅ Date range distribution is even
- ✅ Exclusion respect settings are honored

### 2. Birthday Rules
- ✅ All state exclusion windows work correctly
- ✅ Year-round exclusions prevent all emails
- ✅ Edge cases (leap years, boundaries) handled properly
- ✅ Multiple exclusion windows don't conflict

### 3. Date Handling
- ✅ Arbitrary date inputs produce correct results
- ✅ Historical and future date processing works
- ✅ Calendar edge cases are handled correctly
- ✅ Performance remains acceptable across date ranges

### 4. Integration
- ✅ All components work together seamlessly
- ✅ Database integrity is maintained
- ✅ No regression in existing functionality
- ✅ Performance benchmarks are met

## Continuous Testing

### 1. Automated Test Runs
- **Schedule**: Daily regression tests
- **Triggers**: Code changes, database schema updates
- **Reports**: Automated test result summaries

### 2. Test Data Refresh
- **Monthly**: Update test datasets
- **Quarterly**: Review and expand test scenarios
- **Annually**: Full test strategy review

### 3. Performance Monitoring
- **Benchmarks**: Track scheduler performance over time
- **Scaling**: Test with increasing data sizes
- **Optimization**: Identify and address performance bottlenecks

This comprehensive testing strategy ensures thorough validation of all scheduler components while providing automated tools for continuous testing and validation.