open Dsl
open Date_time
open Types
open Date_calc

type exclusion_result = 
  | NotExcluded
  | Excluded of { reason: string; window_end: Date_time.date option }

(** 
 * [check_birthday_exclusion]: Checks if a date falls within birthday exclusion window
 * 
 * Purpose:
 *   Determines if email should be excluded due to state-specific birthday exclusion
 *   rules that prevent sending emails during sensitive periods around birthdays.
 * 
 * Parameters:
 *   - contact: Contact record containing state and birthday information
 *   - check_date: Date to evaluate against exclusion window
 * 
 * Returns:
 *   exclusion_result indicating exclusion status with reason and window end date
 * 
 * Business Logic:
 *   - Requires both state and birthday data to apply exclusion
 *   - Looks up state-specific window configuration for birthday emails
 *   - Calculates next birthday anniversary relative to check date
 *   - Determines if check date falls within configured exclusion window
 *   - Provides specific exclusion reason including state information
 * 
 * Usage Example:
 *   Called by check_exclusion_window as part of comprehensive exclusion evaluation
 * 
 * Error Cases:
 *   - Returns NotExcluded if state or birthday data missing
 *   - Returns NotExcluded if no exclusion window configured for state
 * 
 * @business_rule @state_machine
 *)
let check_birthday_exclusion contact check_date =
  match contact.state, contact.birthday with
  | Some state, Some birthday ->
      begin match get_window_for_email_type state (Anniversary Birthday) with
      | Some window ->
          let next_bday = next_anniversary check_date birthday in
          if in_exclusion_window check_date window next_bday then
            let window_end = add_days next_bday window.after_days in
            Excluded { 
              reason = Printf.sprintf "Birthday exclusion window for %s" (string_of_state state);
              window_end = Some window_end 
            }
          else
            NotExcluded
      | None -> NotExcluded
      end
  | _ -> NotExcluded

(** 
 * [check_effective_date_exclusion]: Checks if date falls within effective date exclusion window
 * 
 * Purpose:
 *   Determines if email should be excluded due to state-specific effective date exclusion
 *   rules that prevent sending emails during sensitive periods around policy anniversaries.
 * 
 * Parameters:
 *   - contact: Contact record containing state and effective_date information
 *   - check_date: Date to evaluate against exclusion window
 * 
 * Returns:
 *   exclusion_result indicating exclusion status with reason and window end date
 * 
 * Business Logic:
 *   - Requires both state and effective date data to apply exclusion
 *   - Looks up state-specific window configuration for effective date emails
 *   - Calculates next effective date anniversary relative to check date
 *   - Determines if check date falls within configured exclusion window
 *   - Provides specific exclusion reason including state information
 * 
 * Usage Example:
 *   Called by check_exclusion_window as part of comprehensive exclusion evaluation
 * 
 * Error Cases:
 *   - Returns NotExcluded if state or effective_date data missing
 *   - Returns NotExcluded if no exclusion window configured for state
 * 
 * @business_rule @state_machine
 *)
let check_effective_date_exclusion contact check_date =
  match contact.state, contact.effective_date with
  | Some state, Some ed ->
      begin match get_window_for_email_type state (Anniversary EffectiveDate) with
      | Some window ->
          let next_ed = next_anniversary check_date ed in
          if in_exclusion_window check_date window next_ed then
            let window_end = add_days next_ed window.after_days in
            Excluded { 
              reason = Printf.sprintf "Effective date exclusion window for %s" (string_of_state state);
              window_end = Some window_end 
            }
          else
            NotExcluded
      | None -> NotExcluded
      end
  | _ -> NotExcluded

(** 
 * [check_year_round_exclusion]: Checks if contact's state has year-round email exclusion
 * 
 * Purpose:
 *   Identifies states with permanent exclusion policies that prevent all anniversary
 *   emails regardless of date, typically due to regulatory restrictions.
 * 
 * Parameters:
 *   - contact: Contact record containing state information
 * 
 * Returns:
 *   exclusion_result indicating if state has year-round exclusion policy
 * 
 * Business Logic:
 *   - Checks if contact's state is configured for year-round exclusion
 *   - Returns permanent exclusion with no end date for applicable states
 *   - Provides state-specific exclusion reason for audit purposes
 *   - Takes precedence over date-based exclusion windows
 * 
 * Usage Example:
 *   Called first by check_exclusion_window to check for permanent exclusions
 * 
 * Error Cases:
 *   - Returns NotExcluded if contact has no state information
 *   - Returns NotExcluded if state not configured for year-round exclusion
 * 
 * @business_rule @state_machine
 *)
let check_year_round_exclusion contact =
  match contact.state with
  | Some state when is_year_round_exclusion state ->
      Excluded { 
        reason = Printf.sprintf "Year-round exclusion for %s" (string_of_state state);
        window_end = None 
      }
  | _ -> NotExcluded

(** 
 * [check_exclusion_window]: Main exclusion evaluation function for comprehensive rule checking
 * 
 * Purpose:
 *   Orchestrates all exclusion rule evaluations in priority order to determine if an
 *   email should be excluded for a contact on a specific date.
 * 
 * Parameters:
 *   - contact: Contact record with state, birthday, and effective_date information
 *   - check_date: Date to evaluate against all applicable exclusion rules
 * 
 * Returns:
 *   exclusion_result with first applicable exclusion or NotExcluded if none apply
 * 
 * Business Logic:
 *   - Evaluates exclusions in priority order (year-round, birthday, effective date)
 *   - Returns first exclusion match without checking subsequent rules
 *   - Provides comprehensive state-based compliance checking
 *   - Ensures regulatory compliance across all anniversary email types
 * 
 * Usage Example:
 *   Called by should_skip_email and email scheduling functions for exclusion decisions
 * 
 * Error Cases:
 *   - Returns NotExcluded if contact lacks required data for any rule evaluation
 *   - Handles missing state/date information gracefully
 * 
 * @business_rule @integration_point
 *)
let check_exclusion_window contact check_date =
  match check_year_round_exclusion contact with
  | Excluded _ as result -> result
  | NotExcluded ->
      match check_birthday_exclusion contact check_date with
      | Excluded _ as result -> result
      | NotExcluded -> check_effective_date_exclusion contact check_date

(** 
 * [should_skip_email]: Determines if specific email type should be skipped for contact
 * 
 * Purpose:
 *   Makes final decision on email exclusion considering both exclusion rules and
 *   email type-specific policies like campaign respect_exclusions settings.
 * 
 * Parameters:
 *   - contact: Contact record for exclusion rule evaluation
 *   - email_type: Type of email being considered (Campaign, Anniversary, etc.)
 *   - check_date: Scheduled date for the email
 * 
 * Returns:
 *   Boolean indicating if email should be skipped (true) or sent (false)
 * 
 * Business Logic:
 *   - Campaign emails with respect_exclusions=false bypass all exclusion rules
 *   - PostWindow anniversary emails always bypass exclusion rules
 *   - All other emails subject to standard exclusion window evaluation
 *   - Provides final gatekeeper for email sending decisions
 * 
 * Usage Example:
 *   Called by email scheduling functions before creating email schedules
 * 
 * Error Cases:
 *   - Defaults to exclusion rule evaluation for unknown email types
 *   - Returns false (don't skip) if exclusion evaluation returns NotExcluded
 * 
 * @business_rule @integration_point
 *)
let should_skip_email contact email_type check_date =
  match email_type with
  | Campaign c when not c.respect_exclusions -> false
  | Anniversary PostWindow -> false
  | _ ->
      match check_exclusion_window contact check_date with
      | NotExcluded -> false
      | Excluded _ -> true

(** 
 * [get_post_window_date]: Calculates when post-exclusion window email can be sent
 * 
 * Purpose:
 *   Determines the earliest date when a make-up email can be sent after exclusion
 *   windows end, enabling recovery of missed anniversary communications.
 * 
 * Parameters:
 *   - contact: Contact record for exclusion window evaluation
 * 
 * Returns:
 *   Option date representing earliest post-window send date, or None if no exclusions
 * 
 * Business Logic:
 *   - Evaluates all current exclusion windows (birthday and effective date)
 *   - Finds the latest ending exclusion window to avoid conflicts
 *   - Adds one day buffer after window end for post-window email
 *   - Enables recovery communication after exclusion periods
 * 
 * Usage Example:
 *   Called by calculate_post_window_emails to schedule make-up communications
 * 
 * Error Cases:
 *   - Returns None if no active exclusion windows found
 *   - Handles missing exclusion window end dates gracefully
 * 
 * @business_rule @data_flow
 *)
let get_post_window_date contact =
  let today = current_date () in
  let exclusions = [
    check_birthday_exclusion contact today;
    check_effective_date_exclusion contact today
  ] in
  
  let latest_window_end = 
    List.fold_left (fun acc exc ->
      match exc, acc with
      | Excluded { window_end = Some end_date; _ }, None -> Some end_date
      | Excluded { window_end = Some end_date; _ }, Some acc_date ->
          if compare_date end_date acc_date > 0 then Some end_date else Some acc_date
      | _ -> acc
    ) None exclusions
  in
  
  match latest_window_end with
  | Some end_date -> Some (add_days end_date 1)
  | None -> None