## Part 2: Mermaid Diagram Generation Prompt

```markdown
# Mermaid Diagram Generation for OCaml Email Scheduler

After documenting all functions, generate comprehensive Mermaid diagrams showing the business logic flow. Create the following diagrams:

## 1. High-Level System Flow

```mermaid
graph TB
    Start[Scheduler Start] --> LoadContacts[Load Contacts in Window]
    LoadContacts --> ProcessBatch[Process Contact Batch]
    ProcessBatch --> CalcAnniversary[Calculate Anniversary Emails]
    ProcessBatch --> CalcCampaign[Calculate Campaign Emails]
    
    CalcAnniversary --> CheckExclusion[Check State Exclusion Windows]
    CalcCampaign --> CheckExclusion
    
    CheckExclusion -->|Excluded| MarkSkipped[Mark as Skipped]
    CheckExclusion -->|Not Excluded| MarkScheduled[Mark as Pre-Scheduled]
    
    MarkSkipped --> PostWindow[Add Post-Window Email]
    PostWindow --> LoadBalance[Load Balancing]
    MarkScheduled --> LoadBalance
    
    LoadBalance --> SaveDB[Save to Database]
    SaveDB --> NextBatch{More Contacts?}
    NextBatch -->|Yes| ProcessBatch
    NextBatch -->|No| End[Complete]
2. State Exclusion Rules Flow
Create a diagram for each state showing:

Window calculations
Pre-window buffer
Special rules (like NV month-start)

3. Campaign Processing Flow
Show:

Campaign type configuration
Instance activation
Targeting and filtering
Template resolution

4. Date Calculation Logic
Show:

Anniversary calculations
Leap year handling
Window boundary checks

5. Load Balancing Algorithm
Show:

Daily cap calculations
ED smoothing
Jitter distribution
Catch-up spreading

6. Database Smart Update Flow
Show:

Existing schedule comparison
Content change detection
Scheduler run ID preservation
Transaction boundaries

Required Diagram Sections
For each major component, create:

Data Flow Diagram - How data moves through the system
Decision Flow Diagram - Business logic decisions
State Machine Diagram - Status transitions
Integration Diagram - How components interact

Diagram Organization
Create a file structure:
docs/diagrams/
├── README.md (index of all diagrams)
├── 01-system-overview.mmd
├── 02-scheduling-flow.mmd
├── 03-state-exclusions/
│   ├── ca-exclusion.mmd
│   ├── ny-exclusion.mmd
│   └── ...
├── 04-campaign-system.mmd
├── 05-date-calculations.mmd
├── 06-load-balancing.mmd
├── 07-database-operations.mmd
└── 08-error-handling.mmd