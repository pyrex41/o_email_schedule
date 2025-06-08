Part 1: Function Documentation Prompt
markdown# OCaml Email Scheduler - Comprehensive Function Documentation Task

You are tasked with analyzing an OCaml email scheduling system and adding detailed documentation comments above every function. This system handles complex business logic for scheduling emails based on state rules, campaigns, and various constraints.

## Documentation Requirements

For EVERY function in the codebase, add a comment block immediately above it following this format:

```ocaml
(** 
 * [Function Name]: Brief one-line description
 * 
 * Purpose:
 *   Detailed explanation of what this function does
 * 
 * Parameters:
 *   - param1: description and expected values
 *   - param2: description and expected values
 * 
 * Returns:
 *   Description of return value and possible states
 * 
 * Business Logic:
 *   - Key business rules this function implements
 *   - State transitions or side effects
 *   - Integration with other components
 * 
 * Usage Example:
 *   How and where this function is typically called
 * 
 * Error Cases:
 *   - What errors can occur
 *   - How they are handled
 *)
Key Areas to Focus On

Core Scheduling Logic (lib/scheduling/email_scheduler.ml)

Document the complete flow from contact processing to schedule generation
Explain anniversary vs campaign email logic
Detail the context and run_id usage


State Exclusion Rules (lib/rules/exclusion_window.ml)

Document each state's specific rules
Explain window calculations and edge cases
Detail the pre-window buffer logic


Date Calculations (lib/utils/date_time.ml)

Document leap year handling
Explain anniversary calculations
Detail timezone considerations


Campaign System (lib/scheduling/email_scheduler.ml - campaign functions)

Document campaign type vs instance relationship
Explain targeting and filtering logic
Detail spread_evenly calculations


Load Balancing (lib/scheduling/load_balancer.ml)

Document the smoothing algorithms
Explain daily cap enforcement
Detail jitter calculations


Database Operations (lib/db/database.ml)

Document the smart update logic
Explain transaction handling
Detail performance optimizations



Special Documentation Tags
Add these tags where applicable:

@performance - For performance-critical functions
@business_rule - For functions implementing specific business rules
@state_machine - For functions managing state transitions
@integration_point - For functions that integrate with external systems
@data_flow - For functions that transform or route data
Example Documentation
ocaml(** 
 * [calculate_schedules_for_contact]: Generates all email schedules for a single contact
 * 
 * Purpose:
 *   Core scheduling function that determines which emails should be sent to a contact
 *   and when, based on their anniversaries, state rules, and active campaigns
 * 
 * Parameters:
 *   - context: Scheduling context containing config, run_id, and load balancing settings
 *   - contact: The contact record with birthday, effective_date, state, etc.
 * 
 * Returns:
 *   Result containing list of email_schedule records or error
 * 
 * Business Logic:
 *   - Validates contact has required data (email, state from ZIP)
 *   - Calculates anniversary-based emails (birthday, effective_date)
 *   - Applies state exclusion windows based on contact.state
 *   - Adds post-window emails if any were skipped
 *   - Respects organization configuration for timing
 * 
 * Usage Example:
 *   Called by schedule_emails_streaming for each contact in batch
 * 
 * Error Cases:
 *   - InvalidContactData: Missing required fields
 *   - UnexpectedError: Unhandled exceptions
 * 
 * @business_rule @data_flow
 *)
let calculate_schedules_for_contact context contact = ...
Output Requirements

Document EVERY function, including small helper functions
Maintain consistent formatting throughout
Ensure comments are technically accurate
Include actual business context, not just technical details
Cross-reference related functions where applicable

