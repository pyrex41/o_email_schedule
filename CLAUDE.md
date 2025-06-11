# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an OCaml-based email scheduling system that manages automated email and SMS campaigns. The system handles:
- Anniversary-based emails (birthdays, policy effective dates, AEP, post-window)
- Campaign-based emails with flexible configuration
- State-specific exclusion windows and regulatory compliance
- Processing up to 3 million contacts efficiently with 10k batch size
- Complex date calculations in Central Time (CT)
- Distributed database synchronization with smart update logic

The project uses Dune as its build system and follows OCaml best practices. Implementation is 71% complete with comprehensive testing infrastructure.

## Build and Development Commands

```bash
# Build the project
dune build

# Run the main scheduler executable
dune exec scheduler

# Run all tests
dune test

# Run specific test suites
dune exec test/test_scheduler.exe              # Core scheduler tests
dune exec test/test_rules.exe                  # Business rules tests
dune exec test/test_scheduler_integration.exe  # Integration tests
dune exec test/test_golden_master.exe          # Golden master regression tests
dune exec test/test_properties.exe             # Property-based tests
dune exec test/test_state_rules_matrix.exe     # State matrix tests
dune exec test/test_edge_cases.exe             # Edge case tests

# Run performance tests
dune exec high_performance_scheduler
dune exec performance_tests_parallel
./run_performance_tests.sh
./run_performance_tests.sh --full      # Comprehensive performance suite

# Run sync service (for central database access)
cd sync-service && ./start.sh

# Build with test coverage
dune test --instrument-with bisect_ppx

# Format code
dune build @fmt --auto-promote

# Check formatting
dune build @fmt

# Build documentation
dune build @doc

# Clean build artifacts
dune clean
```

## Visualization Tools

The project includes an interactive OCaml Program Flow Visualizer:

```bash
# Build and run visualizer on the entire lib/ directory
dune exec ocaml-visualizer -- --verbose --output test_viz lib/

# Focused analysis with complexity filter
dune exec ocaml-visualizer -- --max-complexity 5 --output scheduling_viz lib/scheduling/

# Start web server immediately
dune exec ocaml-visualizer -- --serve --port 9000 lib/

# View existing visualization
cd web && python3 -m http.server 8000
# Then open http://localhost:8000
```

## Project Architecture

### Module Structure (Implemented)

- **lib/domain/** - Core domain types and business entities
  - `types.ml` - Core type definitions (states, email types, contacts)
  - `contact.ml` - Contact operations

- **lib/rules/** - Business rule engine
  - `exclusion_window.ml` - Exclusion window calculations
  - `dsl.ml` - Domain-specific language for rules

- **lib/scheduling/** - Core scheduling logic
  - `date_calc.ml` - Date calculations and timezone handling
  - `email_scheduler.ml` - Main scheduling algorithm
  - `load_balancer.ml` - Load distribution logic

- **lib/db/** - Database layer (note: not `persistence/`)
  - `database.ml` / `database.mli` - Database operations using Caqti

- **lib/utils/** - Utility modules
  - `date_time.ml` - Date/time utilities using Ptime
  - `config.ml` - Configuration management
  - `zip_data.ml` - ZIP code to state mapping
  - `audit_simple.ml` - Audit logging

- **lib/visualizer/** - Code visualization tools
  - `ast_analyzer.ml` - AST analysis
  - `call_graph.ml` - Call graph generation
  - `doc_extractor.ml` - Documentation extraction
  - `json_serializer.ml` - JSON output

### Key Dependencies
- `sqlite3` and `caqti` for database access
- `lwt` for asynchronous programming  
- `ptime` for date/time handling (migrated from custom Simple_date)
- `yojson` for JSON configuration
- `logs` for structured logging
- `alcotest` for testing
- `qcheck` for property-based testing

### Database Schema
SQLite database (`org-206.sqlite3`) containing:
- `contacts` - Customer information
- `email_schedules` - Scheduling data
- `campaign_types` - Campaign definitions
- `campaign_instances` - Active campaign instances
- `contact_campaigns` - Contact-campaign associations
- `organizations` - Organization configuration with hybrid config columns
- `organization_state_buffers` - State-specific buffer overrides
- Change tracking and audit tables

### Sync Service
The project includes a Go-based sync service (`sync-service/`) that:
- Maintains a local SQLite replica of the central Turso database
- Auto-syncs every 2 minutes
- Provides local database access at `./sync-service/data/central_replica.db`
- Runs on port 9191 by default

## Important Business Rules

1. **Time Zone**: All operations use Central Time (CT)
2. **State Exclusions**: Complex exclusion windows per state
   - CA: 30-day birthday window
   - NY: Year-round exclusion for certain email types
   - See `lib/rules/exclusion_window.ml` for full details
3. **Email Priorities**: Strict priority system with state exclusions taking precedence
4. **Anniversary Timing**: 
   - Birthday emails: 14 days before
   - Effective date emails: 30 days before
   - AEP emails: September annually
5. **Campaign System**: Two-tier architecture with campaign types and instances
6. **Smart Updates**: Distributed synchronization with `smart_update_schedules` function

## Development Guidelines

1. **Type Safety**: Use OCaml's type system extensively - variants for states, email types, and statuses
2. **Error Handling**: Use Result types for operations that can fail
3. **Performance**: 
   - Batch size: 10k contacts
   - Use streaming for large datasets
   - Leverage database indices for performance
4. **Testing**: 
   - Write unit tests for new functionality
   - Use property-based testing for invariants
   - Maintain golden master tests for regression protection
5. **Date Handling**: Use Ptime library (not custom Simple_date)
6. **Environment**: Use `eval $(opam env)` before building

## Testing Infrastructure

- **Golden Master Testing**: Full regression protection against known good outputs
- **Property-Based Testing**: 10 critical invariants verified with QCheck
- **State Matrix Testing**: Comprehensive coverage of all state/date combinations
- **Edge Case Testing**: 20+ edge cases across 7 test suites
- **Integration Testing**: End-to-end workflow validation

## Current Implementation Status

- Core scheduling logic: ✅ Complete
- Business rules engine: ✅ Complete  
- Database operations: ✅ Complete
- Testing infrastructure: ✅ Complete
- Performance optimization: 📋 In progress
- Production deployment: 📋 Planned
- Documentation: ✅ Complete

Recent changes:
- Migrated from custom date logic to Ptime library
- Fixed critical SQL bug in test data generation
- Added comprehensive test coverage
- Implemented OCaml Program Flow Visualizer

## Common Development Tasks

### Running a Single Test
```bash
# Run a specific test function within a test file
dune exec test/test_scheduler.exe -- --filter "test_birthday_email_scheduling"

# Run tests with verbose output
ALCOTEST_VERBOSE=1 dune test

# Run only quick tests during development
dune exec test/test_scheduler_simple.exe
```

### Working with the Visualizer
```bash
# Generate visualization for a specific module
dune exec ocaml-visualizer -- --module Email_scheduler lib/scheduling/

# Update visualization after code changes
dune exec ocaml-visualizer -- --output web lib/ && cd web && python3 -m http.server 8000
```

### Database Operations
```bash
# Run migrations
sqlite3 org-206.sqlite3 < migrations/001_add_organization_config.sql

# Connect to database for debugging
sqlite3 org-206.sqlite3

# Check sync service database
sqlite3 sync-service/data/central_replica.db
```