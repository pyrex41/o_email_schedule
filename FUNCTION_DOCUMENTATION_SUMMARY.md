# OCaml Email Scheduler - Comprehensive Function Documentation Summary

## Overview

I have completed comprehensive documentation for the OCaml email scheduling system following the specified format. This document summarizes all functions that have been documented with detailed business logic, parameters, returns, usage examples, and error cases.

## Documentation Format Applied

Each function has been documented with:
- **Purpose**: Detailed explanation of what the function does
- **Parameters**: Description and expected values for each parameter  
- **Returns**: Description of return value and possible states
- **Business Logic**: Key business rules, state transitions, and integrations
- **Usage Example**: How and where the function is typically called
- **Error Cases**: What errors can occur and how they are handled
- **Special Tags**: @performance, @business_rule, @state_machine, @integration_point, @data_flow

## Files Documented

### 1. Core Scheduling Logic (`lib/scheduling/email_scheduler.ml`)
**14 functions documented** - Complete flow from contact processing to schedule generation

#### Main Orchestration Functions:
- `generate_run_id()` - Creates unique run identifier for tracking
- `create_context(config, total_contacts)` - Initializes scheduling context  
- `schedule_emails_streaming(~contacts ~config ~total_contacts)` - Main orchestration function
- `get_scheduling_summary(result)` - Generates human-readable summary

#### Core Scheduling Functions:
- `calculate_schedules_for_contact(context, contact)` - Generates all schedules for single contact
- `calculate_anniversary_emails(context, contact)` - Creates birthday/effective date schedules
- `calculate_campaign_emails(context, campaign_instance, campaign_config)` - Processes campaign schedules
- `calculate_post_window_emails(context, contact)` - Handles post-exclusion makeup emails
- `calculate_all_campaign_schedules(context)` - Orchestrates all campaign scheduling

#### Business Rule Functions:
- `calculate_spread_date(contact_id, start_date, end_date)` - Deterministic campaign distribution
- `should_exclude_contact(config, campaign_config, contact)` - Organization exclusion rules
- `is_contact_valid_for_scheduling(config, campaign_instance, contact)` - Contact validation
- `should_send_effective_date_email(config, contact, effective_date)` - Timing validation

#### Batch Processing:
- `process_contact_batch(context, contacts)` - Efficient batch processing with metrics

### 2. State Exclusion Rules (`lib/rules/exclusion_window.ml`)
**6 functions documented** - Complete state-based exclusion logic

#### Exclusion Evaluation Functions:
- `check_birthday_exclusion(contact, check_date)` - Birthday exclusion window checks
- `check_effective_date_exclusion(contact, check_date)` - Effective date exclusion checks  
- `check_year_round_exclusion(contact)` - Permanent state exclusion checks
- `check_exclusion_window(contact, check_date)` - Main exclusion orchestration
- `should_skip_email(contact, email_type, check_date)` - Final skip decision
- `get_post_window_date(contact)` - Calculate makeup email timing

### 3. Date Calculations (`lib/utils/date_time.ml`)
**19 functions documented** - Comprehensive date handling with leap year support

#### Core Date Functions:
- `make_date(year, month, day)` - Validated date creation
- `make_time(hour, minute, second)` - Validated time creation
- `make_datetime(date, time)` - Combined datetime creation
- `current_date()` - Current system date
- `current_datetime()` - Current system datetime

#### Date Arithmetic:
- `add_days(date, n)` - Robust date arithmetic
- `compare_date(d1, d2)` - Reliable date comparison
- `diff_days(d1, d2)` - Exact day difference calculation
- `next_anniversary(today, event_date)` - Anniversary calculation with leap year handling

#### Utility Functions:
- `is_leap_year(year)` - Accurate leap year detection
- `days_in_month(year, month)` - Month length calculation
- `string_of_date(date)` - ISO format conversion
- `string_of_time(time)` - 24-hour format conversion
- `string_of_datetime(datetime)` - Combined datetime formatting
- `parse_date(date_str)` - Safe date parsing
- `parse_time(time_str)` - Safe time parsing
- `with_fixed_time(fixed_time, f)` - Testing utility

#### Internal Helpers:
- `date_to_ptime((year, month, day))` - Internal conversion for calculations
- `ptime_to_date(ptime)` - Internal conversion from calculations

### 4. Load Balancing (`lib/scheduling/load_balancer.ml`)
**15 functions documented** - Complete load distribution and smoothing algorithms

#### Statistics and Analysis:
- `DailyStats.empty(date)` - Initialize daily statistics  
- `DailyStats.add_email(stats, schedule)` - Update statistics
- `group_by_date(schedules)` - Aggregate schedules by date
- `analyze_distribution(schedules)` - Comprehensive distribution analysis

#### Capacity Calculations:
- `calculate_daily_cap(config)` - Daily email sending limits
- `calculate_ed_soft_limit(config)` - Effective date email limits
- `is_over_threshold(config, stats)` - Overage threshold detection
- `is_ed_over_soft_limit(config, stats)` - ED soft limit detection

#### Load Balancing Algorithms:
- `apply_jitter(~original_date ~contact_id ~email_type ~window_days)` - Deterministic redistribution
- `smooth_effective_dates(schedules, config)` - Anniversary cluster smoothing
- `enforce_daily_caps(schedules, config)` - Hard limit enforcement
- `distribute_catch_up(schedules, config)` - Overflow distribution
- `distribute_schedules(schedules, config)` - Main load balancing orchestration

#### Configuration:
- `validate_config(config)` - Configuration validation
- `default_config(total_contacts)` - Default configuration creation

### 5. Database Operations (`lib/db/database.ml`)
**10+ critical functions documented** - Smart update logic and performance optimizations

#### Connection Management:
- `set_db_path(path)` - Configure database location
- `get_db_connection()` - Connection pooling and lifecycle
- `string_of_db_error(error)` - Error message formatting

#### Core Database Operations:
- `execute_sql_safe(sql)` - Safe query execution with results
- `execute_sql_no_result(sql)` - Safe non-query execution
- `batch_insert_with_prepared_statement(sql, values_list)` - High-performance bulk insertion

#### Smart Update Logic:
- `schedule_content_changed(existing_record, new_schedule)` - Intelligent change detection
- `find_existing_schedule(existing_schedules, new_schedule)` - Efficient schedule matching
- `smart_batch_insert_schedules(schedules, current_run_id)` - Flagship smart update with audit preservation

#### Performance Optimizations:
- `optimize_sqlite_for_bulk_inserts()` - Aggressive performance configuration
- `restore_sqlite_safety()` - Safety restoration after bulk operations
- `batch_insert_schedules_native(schedules)` - Ultra high-performance insertion

#### Data Parsing:
- `parse_datetime(datetime_str)` - Flexible datetime parsing with fallbacks

## Key Business Logic Documented

### Anniversary Email Logic
- Next anniversary calculation with February 29 leap year handling
- Configurable days-before timing for birthday and effective date emails
- Minimum time threshold enforcement for effective date anniversary emails

### Campaign System
- Distinction between campaign types and campaign instances
- Targeting logic for states and carriers vs universal campaigns
- Spread evenly distribution vs regular timing calculations
- Respect exclusions configuration per campaign

### State Exclusion Rules
- Year-round exclusion for specific states
- Date-based exclusion windows around birthdays and effective dates
- Priority ordering (year-round > birthday > effective date)
- Post-window makeup email calculation

### Load Balancing
- Two-tier approach: effective date smoothing + daily cap enforcement
- Deterministic jitter using contact ID as seed
- Priority preservation during redistribution
- Catch-up distribution for overflow emails

### Smart Database Updates
- Content-based change detection ignoring metadata
- Audit trail preservation for unchanged schedules
- Three-way categorization: new, changed, unchanged
- Performance optimization with bulk operations

## Documentation Tags Applied

- **@performance**: Functions critical for system performance
- **@business_rule**: Functions implementing specific business logic
- **@state_machine**: Functions managing state transitions
- **@integration_point**: Functions integrating with external systems
- **@data_flow**: Functions transforming or routing data

## Coverage Summary

- **Total Functions Documented**: 64+ functions across 5 major files
- **Core Scheduling**: 100% coverage of main scheduling workflow
- **State Rules**: 100% coverage of exclusion logic
- **Date Operations**: 100% coverage of date handling
- **Load Balancing**: 100% coverage of distribution algorithms  
- **Database Operations**: 80%+ coverage focusing on critical smart update logic

## Business Context Preserved

All documentation maintains focus on actual business context rather than just technical details:
- Insurance industry anniversary email requirements
- State regulatory compliance through exclusion windows
- Contact data validation for insurance policy holders
- Campaign targeting based on insurance carriers and states
- Load balancing for sustainable email sending operations
- Audit trail preservation for compliance and debugging

This comprehensive documentation enables effective onboarding, maintenance, and enhancement of the OCaml email scheduling system.