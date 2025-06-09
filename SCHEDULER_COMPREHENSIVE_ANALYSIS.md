# Email Scheduler System - Comprehensive Technical Analysis

## Executive Summary

The Email Scheduler System is a sophisticated business rule engine that manages automated email and SMS campaigns for multiple organizations with up to 3 million contacts. It operates in Central Time (CT) and implements complex state-specific regulations, load balancing, and campaign management capabilities.

## 1. System Architecture & Core Components

### 1.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Email Scheduler Engine                       │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Scheduling    │  │  Business Rules │  │ Load Balancing  │  │
│  │     Logic       │  │     Engine      │  │     Engine      │  │
│  │                 │  │                 │  │                 │  │
│  │ • Anniversary   │  │ • State Rules   │  │ • Volume Caps   │  │
│  │ • Campaign      │  │ • Exclusions    │  │ • Smoothing     │  │
│  │ • Follow-up     │  │ • Timing        │  │ • Distribution  │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Database      │  │  Configuration  │  │ Audit & Error   │  │
│  │   Operations    │  │    Manager      │  │    Handling     │  │
│  │                 │  │                 │  │                 │  │
│  │ • SQLite        │  │ • State Rules   │  │ • Checkpoints   │  │
│  │ • Batch Ops     │  │ • Timing Vars   │  │ • Run Tracking  │  │
│  │ • Smart Updates │  │ • Campaigns     │  │ • Recovery      │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Processing Model

- **Single Instance**: No concurrent schedulers (prevents race conditions)
- **Time Zone**: All operations in Central Time (CT)
- **Database Strategy**: Work with SQLite replica, sync results back to main database
- **Reprocessing Strategy**: Clear all pre-scheduled and skipped emails before each run
- **Batch Processing**: Process up to 10,000 contacts per batch for performance

## 2. Core Business Logic Components

### 2.1 Email Type Taxonomy

The system handles two main categories with sophisticated subcategorization:

#### Anniversary-Based Emails (Recurring Annual)
- **Birthday**: 14 days before contact's birthday (configurable)
- **Effective Date**: 30 days before policy anniversary (configurable) 
- **AEP (Annual Enrollment Period)**: September 15th annually (configurable)
- **Post Window**: Day after exclusion window ends (recovery emails)

#### Campaign-Based Emails (Flexible Configuration)
- **Rate Increase**: Premium change notifications
- **Initial Blast**: System introduction emails
- **Seasonal Promotions**: Time-bound marketing campaigns
- **Custom Campaigns**: Configurable business campaigns

#### Follow-up Emails (Behavior-Driven)
- **Cold Follow-up**: No engagement from initial email
- **Clicked No HQ**: Clicked link but didn't answer health questions
- **HQ No Yes**: Answered health questions with no conditions
- **HQ With Yes**: Answered health questions with conditions

### 2.2 Contact Data Model

```ocaml
type contact = {
  id: int;                              (* Unique identifier *)
  email: string;                        (* Required: valid email address *)
  zip_code: string option;              (* Required for state determination *)
  state: state option;                  (* Required for exclusion rules *)
  birthday: Date_time.date option;      (* Optional: needed for birthday emails *)
  effective_date: Date_time.date option; (* Optional: needed for effective date emails *)
  carrier: string option;               (* Insurance carrier code *)
  failed_underwriting: bool;            (* Health questions failure flag *)
}
```

**Data Validation Rules:**
- Contacts without email addresses are skipped
- ZIP code required for state determination (unless organization allows universal campaigns without location)
- State must be determinable from ZIP code for exclusion rule application
- Failed underwriting contacts may be excluded based on organization/campaign settings

### 2.3 Campaign System Architecture

The campaign system uses a two-tier model for maximum flexibility:

#### Campaign Types (Reusable Patterns)
```ocaml
type campaign_type_config = {
  name: string;                         (* e.g., 'rate_increase', 'seasonal_promo' *)
  respect_exclusion_windows: bool;      (* Apply state rules? *)
  enable_followups: bool;               (* Generate follow-up emails? *)
  days_before_event: int;               (* Timing relative to trigger *)
  target_all_contacts: bool;            (* Universal vs. targeted *)
  priority: int;                        (* Lower numbers = higher priority *)
  active: bool;                         (* Can this type be used? *)
  spread_evenly: bool;                  (* Distribute across date range? *)
  skip_failed_underwriting: bool;       (* Exclude failed underwriting? *)
}
```

#### Campaign Instances (Specific Executions)
```ocaml
type campaign_instance = {
  id: int;
  campaign_type: string;                (* References campaign_types.name *)
  instance_name: string;                (* e.g., 'spring_2024_promo' *)
  email_template: string option;        (* Template for email system *)
  sms_template: string option;          (* Template for SMS system *)
  active_start_date: Date_time.date option; (* When active *)
  active_end_date: Date_time.date option;   (* When expires *)
  spread_start_date: Date_time.date option; (* Spread window start *)
  spread_end_date: Date_time.date option;   (* Spread window end *)
  target_states: string option;        (* State targeting: "CA,NY" or "ALL" *)
  target_carriers: string option;      (* Carrier targeting: "BCBS,UHC" or "ALL" *)
  metadata: string option;             (* JSON for overrides *)
}
```

## 3. State-Based Exclusion Rules Engine

### 3.1 Rule Categories

#### Birthday Window Rules (8 states)
- **CA**: 30 days before → 60 days after birthday
- **ID**: 0 days before → 63 days after birthday  
- **KY**: 0 days before → 60 days after birthday
- **MD**: 0 days before → 30 days after birthday
- **NV**: 0 days before → 60 days after (uses month start)
- **OK**: 0 days before → 60 days after birthday
- **OR**: 0 days before → 31 days after birthday
- **VA**: 0 days before → 30 days after birthday

#### Effective Date Window Rules (1 state)
- **MO**: 30 days before → 33 days after effective date anniversary

#### Year-Round Exclusion Rules (4 states)
- **CT, MA, NY, WA**: No marketing emails sent year-round

### 3.2 Pre-Window Exclusion Extension

**Critical Business Rule**: All exclusion windows are extended 60 days BEFORE their start date.

```
Example: CA Birthday exclusion for March 1st birthday
Standard window: Jan 30 (30 days before) → May 1 (60 days after)
Actual window: Dec 1 (60 days before Jan 30) → May 1 (60 days after)
```

**Business Rationale**: Ensures emails aren't sent just prior to statutory exclusion windows, preventing new policy effective dates from falling within exclusion periods.

### 3.3 Special Processing Rules

#### Nevada Month Start Rule
Nevada uses the first day of the birth month instead of actual birth date:
```
Birth Date: March 15th → Window starts March 1st
```

#### Year-Spanning Windows
Algorithm handles exclusion windows that cross calendar years:
```ocaml
let in_exclusion_window check_date window event_date =
  let window_start = add_days event_date (-window.before_days - pre_window_extension) in
  let window_end = add_days event_date window.after_days in
  (* Handle year boundary crossing logic *)
  check_date >= window_start && check_date <= window_end
```

## 4. Load Balancing & Volume Distribution

### 4.1 Volume Management Configuration

```ocaml
type load_balancing_config = {
  daily_send_percentage_cap: float;     (* Default: 0.07 (7% of contacts) *)
  ed_daily_soft_limit: int;            (* Default: 15 emails *)
  ed_smoothing_window_days: int;       (* Default: 5 days (±2) *)
  catch_up_spread_days: int;           (* Default: 7 days *)
  overage_threshold: float;            (* Default: 1.2 (120% of cap) *)
  total_contacts: int;                 (* For capacity calculations *)
}
```

### 4.2 Effective Date Smoothing Algorithm

Effective date emails cluster on month starts (many policies effective 1st of month). The smoothing algorithm:

1. **Cluster Detection**: Count effective date emails per day
2. **Threshold Check**: Exceeds soft limit (15 emails or 30% of daily cap)?
3. **Jitter Application**: Use deterministic hash for distribution
4. **Window Redistribution**: Spread across ±2 days from original date

```ocaml
let calculate_jitter ~contact_id ~event_type ~year ~window_days =
  let hash_input = Printf.sprintf "%d_%s_%d" contact_id event_type year in
  let hash_value = Hashtbl.hash hash_input in
  let jitter = (hash_value mod window_days) - (window_days / 2) in
  jitter
```

### 4.3 Daily Cap Enforcement

When any day exceeds organizational daily cap (7% of contacts):

1. **Overflow Detection**: Identify days > 120% of cap
2. **Priority Preservation**: Sort by email priority (lower number = higher priority)
3. **Next-Day Migration**: Move excess to following day
4. **Cascade Prevention**: Ensure next day doesn't become overloaded
5. **Catch-up Distribution**: If no future capacity, spread across 7-day window

### 4.4 Load Balancing Pipeline

```
Raw Schedules
      ↓
[Effective Date Smoothing] → Redistribute ED clusters across ±2 days
      ↓
[Daily Cap Enforcement] → Move excess emails to next available day
      ↓
[Catch-up Distribution] → Spread overflows across 7-day window
      ↓
Balanced Schedules
```

## 5. Database Operations & Transaction Management

### 5.1 Smart Update Algorithm

The system uses intelligent schedule comparison to preserve audit trails:

```ocaml
let schedule_content_changed existing_record new_schedule =
  (* Compare essential fields: type, date, time, status, skip_reason *)
  (* Ignore metadata fields: run_id, timestamps for audit preservation *)
  existing_record.email_type <> new_email_type_str ||
  existing_record.scheduled_date <> new_scheduled_date_str ||
  existing_record.status <> new_status_str ||
  existing_record.skip_reason <> new_skip_reason
```

**Benefits:**
- Preserves original scheduler_run_id for unchanged schedules
- Maintains audit trail across multiple scheduler runs
- Reduces database writes by ~70% in typical scenarios
- Enables debugging of schedule changes over time

### 5.2 Transaction Boundaries

```sql
BEGIN IMMEDIATE;  -- Prevent concurrent writes

-- 1. Create audit checkpoint
INSERT INTO scheduler_checkpoints (...);

-- 2. Clear existing schedules in batches
DELETE FROM email_schedules WHERE status IN ('pre-scheduled', 'skipped') 
AND contact_id IN (SELECT id FROM contacts LIMIT 10000);

-- 3. Process and insert new schedules
INSERT OR IGNORE INTO email_schedules (...) SELECT ... LIMIT 10000;

-- 4. Update checkpoint with results
UPDATE scheduler_checkpoints SET status = 'completed', ...;

COMMIT;
```

### 5.3 Performance Optimizations

#### Batch Processing
- Process contacts in 10,000-contact chunks
- Use prepared statements for all queries
- Batch INSERTs up to 2,000 records per transaction

#### Strategic Indexing
```sql
CREATE INDEX idx_contacts_state_birthday ON contacts(state, birthday);
CREATE INDEX idx_contacts_state_effective ON contacts(state, effective_date);
CREATE INDEX idx_campaigns_active ON campaign_instances(active_start_date, active_end_date);
CREATE INDEX idx_schedules_lookup ON email_schedules(contact_id, email_type, scheduled_send_date);
```

## 6. Configuration Management System

### 6.1 Timing Constants (Configurable)
```yaml
timing_constants:
  send_time_hour: 8                     # Send time: 08:30 CT
  send_time_minute: 30
  birthday_days_before: 14              # Days before birthday
  effective_date_days_before: 30        # Days before effective date
  pre_window_exclusion_days: 60         # Extension for exclusion windows
  effective_date_first_email_months: 12 # Minimum months since effective date
```

### 6.2 Organization-Level Configuration
```yaml
organization:
  enable_post_window_emails: true       # Send recovery emails after exclusions
  exclude_failed_underwriting_global: false # Skip failed underwriting globally
  send_without_zipcode_for_universal: true  # Allow universal campaigns without location
```

### 6.3 AEP Configuration
```yaml
aep_config:
  default_dates:
    - month: 9                          # September
      day: 15                           # 15th
  years: [2024, 2025, 2026, 2027]      # Active years
```

## 7. Data Flow & Decision Points

### 7.1 Main Scheduling Flow

```
Start Scheduler Run
        ↓
Generate Unique Run ID (run_YYYYMMDD_HHMMSS)
        ↓
Get Total Contact Count → Configure Load Balancing
        ↓
Clear Previous Pre-scheduled/Skipped Emails
        ↓
┌─────────────────┐    ┌─────────────────┐
│  Process        │    │  Process        │
│  Anniversary    │    │  Campaign       │
│  Emails         │    │  Emails         │
│                 │    │                 │
│ • Birthday      │    │ • Active        │
│ • Effective Date│    │   Instances     │
│ • AEP          │    │ • Contact       │
│ • Post Window  │    │   Targeting     │
└─────────────────┘    └─────────────────┘
        ↓                      ↓
        └──────┬──────────────┘
               ↓
Apply Exclusion Rules (if respect_exclusions=true)
        ↓
┌─────────────────────────────────────┐
│         Load Balancing              │
│                                     │
│ 1. Effective Date Smoothing         │
│ 2. Daily Cap Enforcement            │
│ 3. Catch-up Distribution            │
└─────────────────────────────────────┘
        ↓
Smart Database Update (preserve audit trails)
        ↓
Complete Audit Checkpoint
        ↓
End Scheduler Run
```

### 7.2 Critical Decision Points

#### 1. Contact Validation
```ocaml
let is_contact_valid_for_scheduling config campaign_instance contact =
  (* Basic email validation *)
  if contact.email = "" then false
  else
    (* Check targeting requirements *)
    let requires_location = (* campaign has specific targeting *) in
    if requires_location then
      contact.zip_code <> None || contact.state <> None
    else
      config.organization.send_without_zipcode_for_universal
```

#### 2. Exclusion Rule Application
```ocaml
let should_skip_email contact email_type check_date =
  match email_type with
  | Campaign c when not c.respect_exclusions -> false  (* Bypass rules *)
  | Anniversary PostWindow -> false                    (* Always send recovery *)
  | _ -> (* Apply full exclusion evaluation *)
      match check_exclusion_window contact check_date with
      | NotExcluded -> false
      | Excluded _ -> true
```

#### 3. Campaign Date Calculation
```ocaml
let calculate_campaign_send_date campaign_config contact_campaign =
  if campaign_config.spread_evenly then
    (* Deterministic distribution across spread window *)
    calculate_spread_date contact.id spread_start_date spread_end_date
  else
    (* Standard timing: trigger_date + days_before_event *)
    add_days contact_campaign.trigger_date campaign_config.days_before_event
```

## 8. Expected Inputs and Outputs

### 8.1 System Inputs

#### Database Tables
1. **contacts**: Contact information with email, location, dates
2. **campaign_types**: Reusable campaign configurations  
3. **campaign_instances**: Specific campaign executions with templates
4. **contact_campaigns**: Contact-to-campaign targeting associations

#### Configuration Files
1. **State rules YAML**: Exclusion window definitions per state
2. **Timing configuration**: Send times, days before events
3. **Load balancing parameters**: Volume caps, smoothing windows
4. **Organization settings**: Global policies and overrides

#### Runtime Parameters
- Lookahead days (default: 90)
- Lookback days (default: 7) 
- Batch size (default: 10,000)

### 8.2 System Outputs

#### Primary Output: email_schedules Table
```sql
CREATE TABLE email_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id INTEGER NOT NULL,
    email_type TEXT NOT NULL,                 -- 'birthday', 'campaign_rate_increase_123', etc.
    scheduled_send_date DATE NOT NULL,
    scheduled_send_time TIME DEFAULT '08:30:00',
    status TEXT NOT NULL,                     -- 'pre-scheduled', 'skipped'
    skip_reason TEXT,                         -- Exclusion reason if skipped
    priority INTEGER DEFAULT 10,
    campaign_instance_id INTEGER,             -- For campaign emails
    email_template TEXT,                      -- Template identifier
    sms_template TEXT,                        -- SMS template identifier  
    scheduler_run_id TEXT,                    -- Audit trail
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

#### Audit Outputs: scheduler_checkpoints Table
```sql
CREATE TABLE scheduler_checkpoints (
    id INTEGER PRIMARY KEY,
    run_timestamp DATETIME NOT NULL,
    scheduler_run_id TEXT UNIQUE NOT NULL,
    contacts_processed INTEGER,
    emails_scheduled INTEGER,              -- Count of pre-scheduled
    emails_skipped INTEGER,                -- Count of skipped  
    status TEXT NOT NULL,                 -- 'started', 'completed', 'failed'
    error_message TEXT,
    completed_at DATETIME
);
```

#### Volume Distribution Statistics
- Daily email counts by type
- Load balancing redistribution metrics
- Exclusion window hit rates
- Campaign targeting effectiveness

### 8.3 Expected Volume Outputs

For an organization with 1 million contacts:
- **Daily Capacity**: ~70,000 emails (7% cap)
- **Anniversary Emails**: ~2,000-5,000 per day (varies by season)
- **Campaign Emails**: Variable based on active campaigns
- **Effective Date Peak**: ~500-1,000 emails on month starts (before smoothing)
- **Exclusion Skip Rate**: 15-25% depending on state distribution

## 9. Comprehensive Test Cases

### Test Case Category 1: State Exclusion Rules

#### TC001: California Birthday Exclusion
```yaml
Description: Verify CA birthday exclusion window with pre-window extension
Setup:
  contact:
    id: 1001
    state: CA
    birthday: 2024-03-01
    email: test@example.com
  target_date: 2024-01-30  # 30 days before birthday
Expected:
  status: Skipped
  reason: "Birthday exclusion window for CA"
  explanation: "Jan 30 is within pre-extended window (Dec 1 - May 1)"
```

#### TC002: Nevada Month Start Rule
```yaml
Description: Verify NV uses first day of birth month
Setup:
  contact:
    state: NV  
    birthday: 2024-03-15  # 15th of March
  target_date: 2024-02-15  # 15 days before birth month
Expected:
  status: Skipped
  reason: "Birthday exclusion window for NV" 
  explanation: "NV window starts March 1st, not March 15th"
```

#### TC003: Missouri Effective Date Window
```yaml
Description: Verify MO effective date exclusion
Setup:
  contact:
    state: MO
    effective_date: 2024-06-01
  target_date: 2024-05-15  # 16 days before anniversary
Expected:
  status: Skipped
  reason: "Effective date exclusion window for MO"
  explanation: "Within 30 days before effective date anniversary"
```

#### TC004: Year-Round Exclusion States
```yaml
Description: Verify CT/MA/NY/WA year-round exclusion
Setup:
  contact:
    state: NY
    birthday: 2024-06-01
  target_date: 2024-12-01  # Any date
Expected:
  status: Skipped
  reason: "Year-round exclusion for NY"
  explanation: "NY prohibits all marketing emails"
```

### Test Case Category 2: Campaign System

#### TC005: Campaign Exclusion Bypass
```yaml
Description: Campaign with respect_exclusions=false bypasses state rules
Setup:
  contact:
    state: CA
    birthday: 2024-03-01
  campaign:
    type: initial_blast
    respect_exclusions: false
  target_date: 2024-02-01  # Within CA exclusion window
Expected:
  status: PreScheduled
  explanation: "Campaign bypasses exclusion rules"
```

#### TC006: Multiple Campaign Instances
```yaml
Description: Multiple rate increase campaigns with different templates
Setup:
  campaign_instances:
    - id: 1, type: rate_increase, template: rate_v1, active: 2024-Q1
    - id: 2, type: rate_increase, template: rate_v2, active: 2024-Q2
  contact_campaign:
    contact_id: 1001
    instance_id: 1
    trigger_date: 2024-02-15
Expected:
  email_type: "campaign_rate_increase_1"
  template: "rate_v1" 
  campaign_instance_id: 1
```

#### TC007: Campaign Priority Conflicts
```yaml
Description: Higher priority campaign takes precedence on same date
Setup:
  campaigns_same_date:
    - type: rate_increase, priority: 1, date: 2024-03-01
    - type: seasonal_promo, priority: 5, date: 2024-03-01
Expected:
  selected_campaign: rate_increase
  explanation: "Lower priority number = higher precedence"
```

#### TC008: Spread Campaign Distribution
```yaml
Description: Spread campaign distributes contacts across date range
Setup:
  campaign:
    spread_evenly: true
    spread_start: 2024-03-01
    spread_end: 2024-03-07  # 7 days
  contacts: [1001, 1002, 1003, 1004, 1005]
Expected:
  distribution: "Contacts distributed across Mar 1-7 using contact_id % 7"
  consistency: "Same contact gets same date on re-run"
```

### Test Case Category 3: Load Balancing

#### TC009: Effective Date Smoothing
```yaml
Description: Smooth clustered effective date emails
Setup:
  effective_date_emails_march_1: 50  # Exceeds 15 email soft limit
  smoothing_window: 5 days
Expected:
  distribution: "Emails spread across Feb 27 - Mar 3"
  algorithm: "Deterministic jitter based on contact_id hash"
  preservation: "No emails moved to past dates"
```

#### TC010: Daily Cap Enforcement  
```yaml
Description: Redistribute when daily cap exceeded
Setup:
  total_contacts: 100000  # 7% cap = 7000 emails/day
  march_1_scheduled: 8500  # Exceeds 120% threshold (8400)
Expected:
  march_1_final: 7000
  march_2_additional: 1500
  priority_preservation: "Higher priority emails kept on March 1"
```

#### TC011: Catch-up Distribution
```yaml
Description: Distribute overflow across catch-up window
Setup:
  overflow_emails: 1000
  catch_up_days: 7
  no_future_capacity: true
Expected:
  distribution: "~143 emails per day across next 7 days"
  start_date: "Tomorrow (avoid same-day delivery)"
```

### Test Case Category 4: Anniversary Emails

#### TC012: Birthday Email Timing
```yaml
Description: Birthday email scheduled 14 days before
Setup:
  contact:
    birthday: 2024-03-15
  config:
    birthday_days_before: 14
Expected:
  scheduled_date: 2024-03-01
  email_type: "birthday"
  template: "birthday_template"
```

#### TC013: Leap Year Handling
```yaml
Description: February 29th birthday in non-leap year
Setup:
  contact:
    birthday: 2024-02-29  # Leap year birthday
  current_year: 2025  # Non-leap year
Expected:
  anniversary_date: 2025-02-28
  scheduled_date: 2025-02-14  # 14 days before Feb 28
```

#### TC014: Effective Date Minimum Threshold
```yaml
Description: Skip effective date emails if too recent
Setup:
  contact:
    effective_date: 2024-01-01
  config:
    effective_date_first_email_months: 12
  current_date: 2024-06-01  # Only 5 months since effective
Expected:
  status: "No email scheduled"
  reason: "Below 12-month minimum threshold"
```

#### TC015: Post-Window Recovery Email
```yaml
Description: Schedule recovery email after exclusion window
Setup:
  contact:
    state: CA
    birthday: 2024-03-01
  exclusion_window_end: 2024-05-01
Expected:
  post_window_email:
    scheduled_date: 2024-05-02
    email_type: "post_window"
    explanation: "Recovery email day after exclusion ends"
```

### Test Case Category 5: Follow-up Emails

#### TC016: Follow-up Type Selection
```yaml
Description: Select follow-up type based on user behavior
Setup:
  initial_email: birthday, sent: 2024-03-01
  user_behavior:
    clicked_link: true
    answered_health_questions: true
    has_medical_conditions: true
Expected:
  followup_type: "followup_hq_with_yes"
  scheduled_date: 2024-03-03  # 2 days after initial
  priority: "Highest follow-up priority"
```

#### TC017: Campaign Follow-up Inheritance
```yaml
Description: Follow-up inherits campaign priority and metadata
Setup:
  initial_campaign:
    type: rate_increase
    priority: 1
    enable_followups: true
  user_behavior: no_engagement
Expected:
  followup:
    type: "followup_cold"
    priority: 1  # Inherited from campaign
    campaign_instance_id: original_campaign_id
```

### Test Case Category 6: Database Operations

#### TC018: Smart Update Preservation
```yaml
Description: Preserve audit trail for unchanged schedules
Setup:
  existing_schedule:
    contact_id: 1001
    email_type: birthday
    scheduled_date: 2024-03-01
    scheduler_run_id: run_20240201_080000
  new_schedule: identical_content
Expected:
  action: "Skip database update"
  preserved_run_id: "run_20240201_080000"
  log_message: "Content unchanged - preserving original scheduler_run_id"
```

#### TC019: Batch Transaction Rollback
```yaml
Description: Rollback batch on transaction failure
Setup:
  batch_size: 1000
  failure_at_record: 750
Expected:
  action: "Rollback entire batch"
  schedules_saved: 0
  error_logged: true
  retry_mechanism: "Exponential backoff"
```

### Test Case Category 7: Configuration Edge Cases

#### TC020: Multiple AEP Dates
```yaml
Description: Handle multiple AEP dates per year
Setup:
  aep_config:
    dates:
      - month: 9, day: 15  # Primary AEP
      - month: 10, day: 1  # Secondary enrollment
Expected:
  schedules_created: 2
  email_types: ["aep_september", "aep_october"]
```

#### TC021: Invalid ZIP Code Handling
```yaml
Description: Skip contacts with invalid/missing ZIP codes
Setup:
  contact:
    zip_code: null
    state: null
    email: valid@example.com
  campaign: requires_location_targeting
Expected:
  status: Skipped
  reason: "Missing location data for targeted campaign"
```

### Test Case Category 8: Performance & Scale

#### TC022: Large Contact Volume
```yaml
Description: Process 1 million contacts efficiently
Setup:
  contact_count: 1000000
  batch_size: 10000
Expected:
  processing_time: "< 30 minutes"
  memory_usage: "< 2GB"
  database_operations: "Batched prepared statements"
  checkpoint_frequency: "Per batch"
```

#### TC023: Concurrent Read Safety
```yaml
Description: Handle concurrent database reads during processing
Setup:
  scheduler_running: true
  simultaneous_queries: "Email sender reading schedules"
Expected:
  data_consistency: "No dirty reads"
  lock_mechanism: "SQLite WAL mode"
  performance_impact: "Minimal"
```

### Test Case Category 9: Error Handling & Recovery

#### TC024: Partial Processing Recovery
```yaml
Description: Resume processing after partial failure
Setup:
  total_batches: 100
  failed_at_batch: 75
  checkpoint_status: batch_74_completed
Expected:
  resume_from: batch_75
  schedules_preserved: "Batches 1-74"
  audit_trail: "Clear failure point documentation"
```

#### TC025: Configuration Validation
```yaml
Description: Validate configuration on startup
Setup:
  invalid_config:
    daily_cap_percentage: 2.5  # > 100%
    birthday_days_before: -5   # Negative
Expected:
  startup_result: Failed
  error_message: "Invalid configuration: daily_cap_percentage must be 0.0-1.0"
  safe_defaults: "Load fallback configuration"
```

### Test Case Category 10: Integration Scenarios

#### TC026: Multi-State Contact Distribution
```yaml
Description: Process contacts across all state rule types
Setup:
  contact_distribution:
    birthday_window_states: 8_states * 1000_contacts
    effective_date_states: 1_state * 500_contacts  
    year_round_exclusion: 4_states * 2000_contacts
    no_restrictions: 37_states * 10000_contacts
Expected:
  total_processed: 418500_contacts
  skipped_percentage: ~18%  # Year-round + active exclusions
  scheduled_percentage: ~82%
```

#### TC027: Campaign Lifecycle Management
```yaml
Description: Handle campaign activation/deactivation cycles
Setup:
  timeline:
    2024-01-01: Campaign A activates
    2024-02-15: Campaign B activates (same type)
    2024-03-31: Campaign A expires
    2024-06-30: Campaign B expires
Expected:
  jan_schedules: "Only Campaign A"
  feb_mar_schedules: "Both campaigns active"
  apr_jun_schedules: "Only Campaign B"  
  jul_schedules: "No campaign schedules"
```

#### TC028: Template Resolution Priority
```yaml
Description: Resolve email templates based on campaign instances
Setup:
  campaign_instance:
    email_template: "custom_rate_increase_v2"
    sms_template: "rate_sms_v2"
  anniversary_email:
    email_template: "birthday_template"
Expected:
  campaign_email_template: "custom_rate_increase_v2"
  campaign_sms_template: "rate_sms_v2"
  anniversary_template: "birthday_template"
  fallback_behavior: "Use system defaults if templates missing"
```

## 10. Key Success Metrics

### Operational Metrics
- **Processing Time**: < 30 minutes for 1M contacts
- **Memory Usage**: < 2GB peak during processing
- **Database Efficiency**: > 70% write reduction via smart updates
- **Exclusion Accuracy**: 100% compliance with state rules
- **Load Distribution**: ±10% variance from target daily volumes

### Business Metrics  
- **Regulatory Compliance**: 0% violations of state exclusion rules
- **Campaign Flexibility**: Support unlimited campaign types via configuration
- **Audit Trail**: 100% trackability of scheduling decisions
- **Recovery Capability**: Complete recovery from any failure point
- **Template Integration**: Seamless handoff to email/SMS sending systems

---

*This comprehensive analysis provides the foundation for implementing, testing, and maintaining the Email Scheduler System with full understanding of its business logic, technical architecture, and operational requirements.*