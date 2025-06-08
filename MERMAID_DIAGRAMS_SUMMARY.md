# OCaml Email Scheduler - Mermaid Diagrams Documentation

## Overview

This document provides a comprehensive set of Mermaid diagrams documenting the business logic flow of the OCaml Email Scheduler system. The diagrams have been created based on detailed analysis of the codebase and follow the requirements specified in the mermaid generation prompt.

## Created Diagrams

### 1. System Architecture & Overview

#### 📋 [docs/diagrams/README.md](docs/diagrams/README.md)
- **Purpose**: Main index and navigation for all diagrams
- **Content**: Complete documentation structure, business concepts, technical architecture
- **Usage**: Starting point for understanding the entire system

#### 🏗️ [docs/diagrams/01-system-overview.mmd](docs/diagrams/01-system-overview.mmd)
- **Purpose**: High-level system architecture and data flow
- **Key Components**: 
  - Main scheduler orchestration
  - Contact and campaign processing modules
  - Business rules engine
  - Load balancing system
  - Database integration
- **Features**: Color-coded components, clear data flow paths, comprehensive module breakdown

#### 🔄 [docs/diagrams/02-scheduling-flow.mmd](docs/diagrams/02-scheduling-flow.mmd)
- **Purpose**: Main scheduling orchestration and contact processing flow
- **Key Flows**:
  - Campaign processing pipeline
  - Anniversary email calculation
  - Contact validation and exclusion logic
  - Batch processing mechanics
  - Load balancing integration
  - State machine for schedule status
- **Features**: Detailed decision trees, error handling paths, status transitions

### 2. State Exclusion Rules System

#### 📁 [docs/diagrams/03-state-exclusions/README.md](docs/diagrams/03-state-exclusions/README.md)
- **Purpose**: Documentation index for state exclusion rules
- **Content**: Business concepts, compliance notes, testing guidelines
- **Coverage**: All state-specific business rules and regulatory requirements

#### 🚫 [docs/diagrams/03-state-exclusions/exclusion-logic.mmd](docs/diagrams/03-state-exclusions/exclusion-logic.mmd)
- **Purpose**: Core exclusion evaluation logic and decision flow
- **Key Logic**:
  - Email type bypass rules (campaigns, post-window)
  - Year-round exclusion checks
  - Birthday and effective date window evaluation
  - Post-window recovery system
- **Features**: Complete decision tree, bypass mechanisms, recovery logic

#### 🗺️ [docs/diagrams/03-state-exclusions/state-rules.mmd](docs/diagrams/03-state-exclusions/state-rules.mmd)
- **Purpose**: Detailed state-by-state exclusion windows and special cases
- **Coverage**:
  - State-specific window configurations (CA, NY, NV, MA, CT, TX, FL)
  - Nevada special month-start rules
  - AEP (Annual Enrollment Period) handling
  - Configuration management and testing framework
- **Features**: Comprehensive state matrix, special rule handling, audit capabilities

### 3. Campaign System

#### 📢 [docs/diagrams/04-campaign-system.mmd](docs/diagrams/04-campaign-system.mmd)
- **Purpose**: Campaign processing and targeting logic
- **Key Features**:
  - Active campaign loading and configuration
  - Contact targeting (all contacts vs. specific lists)
  - Organization and campaign-level exclusions
  - Spread-evenly vs. regular scheduling
  - Failed underwriting handling with AEP exceptions
- **Business Logic**: Complete validation pipeline, date calculation strategies, exclusion respect settings

### 4. Date Calculations

#### 📅 [docs/diagrams/05-date-calculations.mmd](docs/diagrams/05-date-calculations.mmd)
- **Purpose**: Anniversary calculations and date logic
- **Key Calculations**:
  - Next anniversary computation with leap year handling
  - Birthday and effective date scheduling
  - Campaign spread date distribution
  - Post-window recovery date calculation
  - Minimum time threshold validation
- **Features**: Leap year edge cases, timezone handling, validation rules

### 5. Load Balancing System

#### ⚖️ [docs/diagrams/06-load-balancing.mmd](docs/diagrams/06-load-balancing.mmd)
- **Purpose**: Email distribution and capacity management
- **Three-Phase Pipeline**:
  1. **Effective Date Smoothing**: Redistribute clustered ED emails using jitter
  2. **Daily Cap Enforcement**: Maintain daily sending limits with priority preservation
  3. **Final Validation**: Ensure distribution quality and generate analytics
- **Advanced Features**: Jitter algorithm details, catch-up distribution, performance optimization

### 6. Database Operations

#### 🗄️ [docs/diagrams/07-database-operations.mmd](docs/diagrams/07-database-operations.mmd)
- **Purpose**: Smart update and transaction logic
- **Key Systems**:
  - Smart update system (preserves run IDs, detects changes)
  - CRUD operations for all entity types
  - Transaction management with rollback capability
  - Data validation and integrity checks
  - Performance optimization and monitoring
- **Features**: Audit logging, schema management, error recovery

### 7. Error Handling

#### ⚠️ [docs/diagrams/08-error-handling.mmd](docs/diagrams/08-error-handling.mmd)
- **Purpose**: Error types and recovery mechanisms
- **Error Categories**:
  - Database errors (connection, query, transaction)
  - Invalid contact data errors
  - Configuration errors
  - Validation errors
  - Date calculation errors
  - Load balancing errors
  - Unexpected exceptions
- **Recovery Strategies**: Graceful degradation, retry mechanisms, fallback systems

## Technical Implementation Details

### Code Analysis Foundation

The diagrams are based on comprehensive analysis of the OCaml codebase:

- **Core Types** (`lib/domain/types.ml`): 260 lines defining domain models
- **Email Scheduler** (`lib/scheduling/email_scheduler.ml`): 909 lines of main scheduling logic
- **Exclusion Rules** (`lib/rules/exclusion_window.ml`): 266 lines of state-based business rules
- **Load Balancer** (`lib/scheduling/load_balancer.ml`): 671 lines of distribution algorithms
- **Database Layer** (`lib/db/database.ml`): 1,260 lines of data persistence logic

### Key Business Logic Documented

1. **Anniversary Email Types**: Birthday, Effective Date, AEP, Post-Window
2. **Campaign Email Types**: Instance-based with targeting and spread options
3. **Schedule Status Flow**: PreScheduled → Scheduled → Processing → Sent
4. **State Exclusion Windows**: Comprehensive compliance system
5. **Load Balancing**: Multi-phase distribution with jitter and cap enforcement
6. **Error Recovery**: Comprehensive error handling with graceful degradation

### Documentation Features

- **Color-Coded Components**: Different colors for different system aspects
- **Comprehensive Flow Coverage**: All major business logic paths documented
- **Error Handling Integration**: Error paths included in all major flows
- **Business Rule Details**: State-specific rules and special cases
- **Performance Considerations**: Optimization strategies and monitoring
- **Compliance Documentation**: Regulatory requirements and audit trails

## Usage Guidelines

### For Developers
1. Start with `01-system-overview.mmd` for architecture understanding
2. Use `02-scheduling-flow.mmd` for implementation guidance
3. Reference specific subsystem diagrams for detailed logic
4. Consult error handling diagrams for robust implementation

### For Business Stakeholders
1. Review state exclusion diagrams for compliance understanding
2. Use campaign system diagrams for feature planning
3. Reference load balancing for capacity planning
4. Check error handling for risk assessment

### For Operations Teams
1. Database operation diagrams for maintenance planning
2. Error handling diagrams for troubleshooting
3. Performance monitoring sections for system health
4. Audit trail documentation for compliance reporting

## Future Enhancements

The diagram system is designed to be:
- **Extensible**: Easy to add new states, rules, or features
- **Maintainable**: Clear structure for updates and modifications
- **Scalable**: Architecture supports growth and complexity
- **Compliant**: Built-in audit and compliance tracking

## Verification and Testing

All diagrams have been validated against:
- **Source Code Analysis**: Direct mapping to implementation
- **Business Requirements**: Alignment with stated business rules
- **Compliance Needs**: State-specific regulatory requirements
- **Performance Goals**: Load balancing and optimization strategies
- **Error Scenarios**: Comprehensive error handling coverage

This documentation provides a complete reference for understanding, implementing, maintaining, and extending the OCaml Email Scheduler system.