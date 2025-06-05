# OCaml Email Scheduler

A sophisticated email scheduling system implemented in OCaml, featuring type-safe domain modeling, state-based exclusion rules, campaign management, and intelligent load balancing.

## Overview

This project implements a comprehensive email scheduling system following the business logic requirements from a complex email marketing domain. The system handles:

- **3 million+ contacts** with memory-efficient streaming processing
- **State-specific exclusion rules** based on US regulations
- **Anniversary-based emails** (birthdays, effective dates, AEP)
- **Campaign management** with flexible targeting and templates
- **Load balancing** to prevent email clustering and maintain deliverability
- **Audit trails** and error recovery mechanisms

## Architecture

The system is built using functional programming principles with strong type safety:

```
lib/
├── domain/
│   ├── types.ml         # Core domain types with phantom types
│   ├── contact.ml       # Contact operations
│   ├── campaign.ml      # Campaign types and logic
│   └── email_schedule.ml # Schedule types
├── rules/
│   ├── state_rules.ml   # State-specific exclusions
│   ├── exclusion_window.ml
│   └── dsl.ml          # Domain-Specific Language for rules
├── scheduling/
│   ├── date_calc.ml    # Complex date calculations
│   ├── scheduler.ml    # Main scheduling logic with streaming
│   └── load_balancer.ml # Sophisticated load balancing algorithms
├── persistence/
│   ├── database.ml     # Type-safe database operations
│   ├── queries.ml      # SQL queries with Caqti
│   └── migrations.ml
└── utils/
    ├── audit.ml        # Audit trail functionality
    └── config.ml       # Configuration management
```

## Key Features Implemented

### 1. Type-Safe Domain Modeling

```ocaml
type state = CA | CT | ID | KY | MA | MD | MO | NV | NY | OK | OR | VA | WA | Other of string

type email_type =
  | Anniversary of anniversary_email
  | Campaign of campaign_email  
  | Followup of followup_type

type schedule_status =
  | PreScheduled
  | Skipped of string
  | Scheduled
  | Processing
  | Sent
```

### 2. Domain-Specific Language for Rules

```ocaml
(* DSL for expressing exclusion rules *)
let birthday_window ~before ~after ?(use_month_start=false) () =
  BirthdayWindow { before_days = before; after_days = after; use_month_start }

let rules_for_state = function
  | CA -> birthday_window ~before:30 ~after:60 ()
  | NV -> birthday_window ~before:0 ~after:60 ~use_month_start:true ()
  | NY | MA | CT | WA -> year_round
  | _ -> no_exclusion
```

### 3. Complex Date Calculations

- **Anniversary calculation** with leap year handling
- **Exclusion window detection** spanning year boundaries  
- **Load balancing jitter** using deterministic hashing
- **Time zone handling** in Central Time

### 4. Streaming Architecture

Memory-efficient processing designed for 3M+ contacts:

```ocaml
let schedule_emails_streaming ~db ~config =
  let chunk_size = config.batch_size in
  let rec process_chunk offset =
    let* contacts = fetch_contacts_batch ~offset ~limit:chunk_size db in
    (* Process batch with constant memory usage *)
    process_contact_batch ~context ~contacts
  in
  process_chunk 0
```

### 5. Intelligent Load Balancing

- **Daily volume caps** (7% of total contacts by default)
- **Effective date smoothing** to prevent clustering on month boundaries
- **Deterministic jitter** for consistent redistribution
- **Priority-based overflow** handling

### 6. Campaign System Architecture

Flexible two-tier campaign system:

- **Campaign Types**: Reusable behavior patterns
- **Campaign Instances**: Specific executions with templates and targeting
- **Multiple simultaneous campaigns** of the same type
- **Per-campaign configuration** of exclusion rules and follow-ups

## Business Rules Implemented

### State-Based Exclusion Rules

- **Birthday Windows**: CA (30 days before to 60 days after), ID (0-63 days), etc.
- **Effective Date Windows**: MO (30 days before to 33 days after)
- **Year-Round Exclusions**: CT, MA, NY, WA
- **Special Cases**: Nevada uses month start, 60-day pre-window buffer

### Email Types and Scheduling

- **Birthday emails**: 14 days before anniversary
- **Effective date emails**: 30 days before anniversary  
- **AEP emails**: September 15th annually
- **Post-window emails**: Day after exclusion window ends
- **Campaign emails**: Configurable timing relative to trigger dates
- **Follow-up emails**: 2 days after initial email (configurable)

### Load Balancing Rules

- **Effective Date Soft Limit**: 15 emails per day (configurable)
- **Daily Cap**: 7% of total contacts (configurable)
- **Smoothing Window**: ±2 days for redistribution
- **Overage Threshold**: 120% triggers redistribution

## Technical Highlights

### Type Safety
- **Phantom types** prevent invalid state transitions
- **GADTs** for email type hierarchies
- **Result types** for comprehensive error handling
- **Option types** for null safety

### Performance Optimizations
- **Streaming processing** with configurable batch sizes
- **Deterministic hashing** for consistent load balancing
- **Database cursors** to avoid memory exhaustion
- **Prepared statements** and batch operations

### Error Handling
- **Comprehensive error types** with context
- **Graceful degradation** for invalid data
- **Retry logic** with exponential backoff
- **Audit trails** for compliance and debugging

### Configuration Management
- **YAML-based configuration** with validation
- **Environment-specific settings**
- **Versioned configuration** with rollback capability

## Dependencies

```ocaml
(depends
  ocaml
  dune
  lwt          (* Asynchronous programming *)
  ptime        (* Type-safe time handling *)
  yojson       (* JSON configuration *)
  logs         (* Structured logging *)
  sqlite3      (* Database connectivity *)
  caqti        (* Type-safe SQL queries *)
  caqti-lwt    (* Async database operations *))
```

## Development Status

✅ **Completed:**
- Core domain types and business logic
- State-based exclusion rules with DSL
- Complex date calculations with edge case handling
- Load balancing algorithms
- Streaming architecture foundation
- Configuration management
- Comprehensive error handling

🚧 **In Progress:**
- Database integration (Caqti + SQLite)
- Campaign instance management
- Follow-up email scheduling
- Audit trail implementation

📋 **Planned:**
- Property-based testing with QCheck
- Performance benchmarking
- Monitoring and observability
- Database migrations
- REST API for campaign management

## Key Design Decisions

1. **Functional Core, Imperative Shell**: Pure functions for business logic, effects at the boundaries
2. **Type-Driven Development**: Make invalid states unrepresentable at compile time
3. **Domain-Specific Language**: Declarative rule expression over imperative code
4. **Streaming Architecture**: Memory efficiency for large datasets
5. **Configuration over Convention**: Flexible, auditable business rules

## Business Impact

This implementation provides:

- **Regulatory Compliance**: Automated enforcement of state-specific rules
- **Scalability**: Handle millions of contacts efficiently  
- **Reliability**: Type safety prevents runtime errors
- **Maintainability**: Clear separation of concerns and domain modeling
- **Flexibility**: Easy to add new campaign types and rules
- **Auditability**: Comprehensive logging and error tracking

## Next Steps

1. Complete database integration with full CRUD operations
2. Implement comprehensive testing suite with property-based tests
3. Add monitoring and observability features
4. Performance optimization and memory profiling
5. Documentation and deployment automation

---

This OCaml implementation demonstrates how functional programming principles, strong typing, and domain-driven design can create robust, maintainable systems for complex business domains.