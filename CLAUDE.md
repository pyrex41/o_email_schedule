# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an OCaml-based email scheduling system that manages automated email and SMS campaigns. The system handles:
- Anniversary-based emails (birthdays, policy effective dates, AEP, post-window)
- Campaign-based emails with flexible configuration
- State-specific exclusion windows and regulatory compliance
- Processing up to 3 million contacts efficiently
- Complex date calculations in Central Time (CT)

The project uses Dune as its build system and follows OCaml best practices.

## Build and Development Commands

```bash
# Build the project
dune build

# Run the main executable
dune exec scheduler

# Run tests
dune test

# Run tests with coverage
dune test --instrument-with bisect_ppx

# Build documentation
dune build @doc

# Clean build artifacts
dune clean

# Format code (if ocamlformat is configured)
dune build @fmt --auto-promote

# Check code formatting
dune build @fmt
```

## Project Architecture

### Module Structure
The implementation should follow this architecture as outlined in `prompt.md`:

- **lib/domain/** - Core domain types and business entities
  - `types.ml` - Core type definitions (states, email types, contacts)
  - `contact.ml` - Contact operations
  - `campaign.ml` - Campaign types and logic
  - `email_schedule.ml` - Schedule types

- **lib/rules/** - Business rule engine
  - `state_rules.ml` - State-specific exclusion windows
  - `exclusion_window.ml` - Exclusion window calculations
  - `dsl.ml` - Domain-specific language for rules

- **lib/scheduling/** - Core scheduling logic
  - `date_calc.ml` - Date calculations and timezone handling
  - `scheduler.ml` - Main scheduling algorithm
  - `load_balancer.ml` - Load distribution logic

- **lib/persistence/** - Database layer
  - `database.ml` - Database operations using Caqti
  - `queries.ml` - SQL query definitions
  - `migrations.ml` - Schema migrations

### Key Dependencies
The project uses these OCaml libraries (defined in dune-project):
- `sqlite3` and `caqti` for database access
- `lwt` for asynchronous programming
- `ptime` and `timedesc` for date/time handling
- `yojson` for JSON configuration
- `logs` for structured logging
- `alcotest` for testing

### Database Schema
The system works with an SQLite database (`org-206.sqlite3`) containing:
- `contacts` table with customer information
- `email_schedules` table for scheduling
- Campaign and tracking tables as defined in `business_logic.md`

## Important Business Rules

1. **Time Zone**: All operations use Central Time (CT)
2. **State Exclusions**: Complex exclusion windows per state (see `business_logic.md`)
3. **Email Priorities**: Strict priority system with state exclusions taking precedence
4. **Anniversary Timing**: 
   - Birthday emails: 14 days before
   - Effective date emails: 30 days before
   - AEP emails: September annually
5. **Campaign System**: Two-tier architecture with campaign types and instances

## Development Guidelines

1. **Type Safety**: Use OCaml's type system extensively - create variants for states, email types, and statuses
2. **Error Handling**: Use Result types for operations that can fail
3. **Performance**: Implement streaming/batching for large contact lists (10k batch size)
4. **Testing**: Write comprehensive tests for date calculations and state rules
5. **Logging**: Use structured logging for audit trails

## Current Implementation Status

The project is currently scaffolded with:
- Basic Dune configuration
- Empty library structure in `lib/`
- Placeholder main executable in `bin/main.ml`
- Empty test file in `test/test_scheduler.ml`

The actual implementation of the email scheduling logic needs to be built following the specifications in `business_logic.md` and the architecture outlined in `prompt.md`.