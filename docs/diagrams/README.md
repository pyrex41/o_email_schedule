# OCaml Email Scheduler - Mermaid Diagrams

This directory contains comprehensive Mermaid diagrams documenting the business logic flow of the OCaml Email Scheduler system.

## Diagram Index

### 1. System Overview
- **[01-system-overview.mmd](01-system-overview.mmd)** - High-level system architecture and data flow

### 2. Core Scheduling Flow
- **[02-scheduling-flow.mmd](02-scheduling-flow.mmd)** - Main scheduling orchestration and contact processing

### 3. State Exclusion Rules
- **[03-state-exclusions/README.md](03-state-exclusions/README.md)** - State-specific exclusion rules index
- **[03-state-exclusions/exclusion-logic.mmd](03-state-exclusions/exclusion-logic.mmd)** - Exclusion window evaluation logic
- **[03-state-exclusions/state-rules.mmd](03-state-exclusions/state-rules.mmd)** - State-specific business rules

### 4. Campaign System
- **[04-campaign-system.mmd](04-campaign-system.mmd)** - Campaign processing and targeting logic

### 5. Date Calculations
- **[05-date-calculations.mmd](05-date-calculations.mmd)** - Anniversary calculations and date logic

### 6. Load Balancing
- **[06-load-balancing.mmd](06-load-balancing.mmd)** - Email distribution and capacity management

### 7. Database Operations
- **[07-database-operations.mmd](07-database-operations.mmd)** - Smart update and transaction logic

### 8. Error Handling
- **[08-error-handling.mmd](08-error-handling.mmd)** - Error types and recovery mechanisms

## How to Use These Diagrams

1. **Start with 01-system-overview.mmd** for high-level understanding
2. **Review 02-scheduling-flow.mmd** for main process flow
3. **Dive into specific subsystems** based on your area of interest
4. **Use state exclusion diagrams** for compliance and regulatory understanding
5. **Reference error handling** for debugging and troubleshooting

## Diagram Types Legend

- **Data Flow Diagrams** - Show how data moves through the system
- **Decision Flow Diagrams** - Show business logic decisions
- **State Machine Diagrams** - Show status transitions
- **Integration Diagrams** - Show how components interact

## Key Business Concepts

- **Anniversary Emails**: Birthday and effective date celebrations
- **Campaign Emails**: Marketing campaigns with targeting rules
- **Exclusion Windows**: State-specific email blocking periods
- **Load Balancing**: Even distribution to prevent overload
- **Post-Window Emails**: Recovery emails after exclusion periods

## Technical Architecture

The system is built in OCaml with these key modules:
- `Types` - Core domain models
- `Email_scheduler` - Main scheduling orchestration
- `Exclusion_window` - State-based business rules
- `Load_balancer` - Email distribution algorithms
- `Database` - Persistence and smart updates