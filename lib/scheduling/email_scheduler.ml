open Types
open Date_time
open Date_calc
open Exclusion_window
open Load_balancer
open Config
open Database

type scheduling_context = {
  config: Config.t;
  run_id: string;
  start_time: datetime;
  load_balancing_config: load_balancing_config;
}

(** 
 * [generate_run_id]: Generates a unique run identifier for the current scheduling execution
 * 
 * Purpose:
 *   Creates a timestamp-based unique identifier for tracking a specific scheduler run.
 *   This ID is used to group all email schedules created during a single execution.
 * 
 * Parameters:
 *   - None
 * 
 * Returns:
 *   String in format "run_YYYYMMDD_HHMMSS" representing the current timestamp
 * 
 * Business Logic:
 *   - Uses current datetime to ensure uniqueness across runs
 *   - Provides audit trail for scheduled emails
 *   - Enables tracking and debugging of specific scheduler executions
 * 
 * Usage Example:
 *   Called by create_context when initializing scheduling context
 * 
 * Error Cases:
 *   - None expected (system time should always be available)
 * 
 * @integration_point
 *)
let generate_run_id () =
  let now = current_datetime () in
  let (date, ((hour, minute, second), _)) = Ptime.to_date_time now in
  let (year, month, day) = date in
  Printf.sprintf "run_%04d%02d%02d_%02d%02d%02d" 
    year month day hour minute second

(** 
 * [create_context]: Creates a complete scheduling context for the current run
 * 
 * Purpose:
 *   Initializes all necessary components for email scheduling including configuration,
 *   unique run ID, timing, and load balancing settings based on total contact count.
 * 
 * Parameters:
 *   - config: Configuration object containing organization settings and email timing
 *   - total_contacts: Total number of contacts to be processed for load balancing calculations
 * 
 * Returns:
 *   scheduling_context record with all initialized components
 * 
 * Business Logic:
 *   - Generates unique run ID for audit trail
 *   - Captures start time for performance tracking
 *   - Configures load balancing based on expected volume
 *   - Ensures consistent context across all scheduling operations
 * 
 * Usage Example:
 *   Called at the beginning of schedule_emails_streaming to initialize the session
 * 
 * Error Cases:
 *   - None expected (all dependencies should be available)
 * 
 * @integration_point @state_machine
 *)
let create_context config total_contacts =
  let run_id = generate_run_id () in
  let start_time = current_datetime () in
  let load_balancing_config = default_config total_contacts in
  { config; run_id; start_time; load_balancing_config }

(** 
 * [calculate_spread_date]: Calculates deterministic spread date for campaign emails
 * 
 * Purpose:
 *   Distributes campaign emails evenly across a date range using contact ID as seed
 *   to ensure consistent but scattered scheduling for campaigns with spread_evenly=true.
 * 
 * Parameters:
 *   - contact_id: Unique contact identifier used as distribution seed
 *   - spread_start_date: Start date of the spread period
 *   - spread_end_date: End date of the spread period
 * 
 * Returns:
 *   Date within the spread range, deterministically calculated for the contact
 * 
 * Business Logic:
 *   - Uses modulo operation on contact_id for deterministic distribution
 *   - Ensures each contact gets the same date on subsequent runs
 *   - Spreads load evenly across the available date range
 *   - Prevents clustering of campaign emails on specific dates
 * 
 * Usage Example:
 *   Called by calculate_campaign_emails when campaign_config.spread_evenly is true
 * 
 * Error Cases:
 *   - None expected (valid date range assumed to be provided)
 * 
 * @business_rule @performance
 *)
let calculate_spread_date contact_id spread_start_date spread_end_date =
  let start_date = spread_start_date in
  let end_date = spread_end_date in
  let total_days = diff_days end_date start_date + 1 in
  
  (* Use contact_id as seed for deterministic distribution *)
  let hash_value = contact_id mod total_days in
  add_days start_date hash_value

(** 
 * [should_exclude_contact]: Determines if contact should be excluded from campaign
 * 
 * Purpose:
 *   Evaluates organization-level and campaign-specific exclusion rules for failed
 *   underwriting contacts to ensure compliance with business policies.
 * 
 * Parameters:
 *   - config: Configuration containing organization exclusion settings
 *   - campaign_config: Campaign-specific configuration including exclusion rules
 *   - contact: Contact record with failed_underwriting flag
 * 
 * Returns:
 *   Option string - Some exclusion_reason if excluded, None if allowed
 * 
 * Business Logic:
 *   - Checks global organization policy for failed underwriting exclusion
 *   - Allows AEP campaigns even for failed underwriting when globally excluded
 *   - Respects campaign-specific failed underwriting skip settings
 *   - Provides specific exclusion reasons for audit purposes
 * 
 * Usage Example:
 *   Called by calculate_campaign_emails to filter contacts before scheduling
 * 
 * Error Cases:
 *   - None expected (all inputs should be valid)
 * 
 * @business_rule
 *)
let should_exclude_contact config campaign_config contact =
  (* Check global underwriting exclusion *)
  if config.organization.exclude_failed_underwriting_global && contact.failed_underwriting then
    (* Only allow AEP campaigns for failed underwriting contacts *)
    if campaign_config.name <> "aep" then
      Some "Failed underwriting - global exclusion"
    else
      None
  else if campaign_config.skip_failed_underwriting && contact.failed_underwriting then
    Some "Failed underwriting - campaign exclusion"
  else
    None

(** 
 * [is_contact_valid_for_scheduling]: Validates contact eligibility for campaign scheduling
 * 
 * Purpose:
 *   Determines if a contact has sufficient data for campaign scheduling based on
 *   email validity and location targeting requirements.
 * 
 * Parameters:
 *   - config: Configuration containing organization policies
 *   - campaign_instance: Campaign instance with targeting constraints
 *   - contact: Contact record with email, zip_code, and state information
 * 
 * Returns:
 *   Boolean indicating if contact is valid for this campaign
 * 
 * Business Logic:
 *   - Requires valid email address for all campaigns
 *   - Checks if campaign has targeting constraints (states/carriers)
 *   - For targeted campaigns, requires location data (zip or state)
 *   - For universal campaigns, respects organization policy on missing location data
 *   - Handles "ALL" targeting as universal campaigns
 * 
 * Usage Example:
 *   Called by calculate_campaign_emails to validate each contact
 * 
 * Error Cases:
 *   - Returns false for contacts with missing required data
 * 
 * @business_rule @data_flow
 *)
let is_contact_valid_for_scheduling config campaign_instance contact =
  (* Basic email validation *)
  if contact.email = "" then
    false
  else
    (* Check if we need zip code/state for this campaign *)
    let requires_location = match (campaign_instance.target_states, campaign_instance.target_carriers) with
      | (None, None) -> false (* Universal campaign *)
      | (Some states, _) when states = "ALL" -> false (* Explicitly universal *)
      | (_, Some carriers) when carriers = "ALL" -> false (* Explicitly universal *)
      | _ -> true (* Has targeting constraints *)
    in
    
    if requires_location then
      (* Campaign has targeting - need valid location data *)
      contact.zip_code <> None || contact.state <> None
    else
      (* Universal campaign - send even without zip code if org allows *)
      config.organization.send_without_zipcode_for_universal

(** 
 * [should_send_effective_date_email]: Determines if effective date email should be sent
 * 
 * Purpose:
 *   Evaluates whether sufficient time has passed since a contact's effective date
 *   to warrant sending anniversary emails based on organization configuration.
 * 
 * Parameters:
 *   - config: Configuration containing effective_date_first_email_months setting
 *   - _contact: Contact record (currently unused but preserved for future use)
 *   - effective_date: The contact's insurance effective date
 * 
 * Returns:
 *   Boolean indicating if effective date email should be sent
 * 
 * Business Logic:
 *   - Calculates months elapsed since effective date
 *   - Compares against organization minimum threshold
 *   - Prevents emails too soon after policy inception
 *   - Ensures regulatory compliance with timing requirements
 * 
 * Usage Example:
 *   Called by calculate_anniversary_emails before scheduling effective date anniversaries
 * 
 * Error Cases:
 *   - None expected (date calculations should be valid)
 * 
 * @business_rule
 *)
let should_send_effective_date_email config _contact effective_date =
  let today = current_date () in
  let (today_year, today_month, _) = today in
  let (ed_year, ed_month, _) = effective_date in
  let months_since_effective = 
    let years_diff = today_year - ed_year in
    let months_diff = today_month - ed_month in
    years_diff * 12 + months_diff
  in
  
  (* Only send if we've passed the minimum months threshold *)
  months_since_effective >= config.organization.effective_date_first_email_months

(** 
 * [calculate_campaign_emails]: Generates email schedules for a specific campaign instance
 * 
 * Purpose:
 *   Core campaign scheduling logic that processes all eligible contacts for a campaign,
 *   applies business rules, handles exclusions, and creates email schedule records.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and load balancing settings
 *   - campaign_instance: Specific campaign instance with targeting and timing data
 *   - campaign_config: Campaign type configuration with rules and settings
 * 
 * Returns:
 *   List of email_schedule records for all processed contacts in this campaign
 * 
 * Business Logic:
 *   - Retrieves contacts based on campaign targeting (all contacts vs specific list)
 *   - Validates each contact for campaign eligibility
 *   - Applies organization and campaign exclusion rules
 *   - Calculates schedule dates (spread evenly vs regular timing)
 *   - Handles exclusion windows if campaign respects them
 *   - Creates appropriate schedule status (PreScheduled vs Skipped)
 * 
 * Usage Example:
 *   Called by calculate_all_campaign_schedules for each active campaign instance
 * 
 * Error Cases:
 *   - Database errors when retrieving contacts return empty lists
 *   - Invalid contacts are skipped with Skipped status
 * 
 * @business_rule @data_flow @performance
 *)
let calculate_campaign_emails context campaign_instance campaign_config =
  let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
  let schedules = ref [] in
  
  (* Get contacts for this campaign with targeting *)
  let contacts = 
    if campaign_config.target_all_contacts then
      match get_contacts_for_campaign campaign_instance with
      | Ok contacts -> contacts
      | Error _ -> []
    else
      match get_contact_campaigns_for_instance campaign_instance.id with
      | Ok contact_campaigns ->
          (* Get the actual contact records for the contact_campaigns *)
          List.filter_map (fun (cc : contact_campaign) ->
            try
              match get_all_contacts () with
              | Ok (contacts_from_db : contact list) -> 
                  List.find_opt (fun (c : contact) -> c.id = cc.contact_id) contacts_from_db
              | Error _ -> None
            with _ -> None
          ) contact_campaigns
      | Error _ -> []
  in
  
  List.iter (fun contact ->
    (* Check if contact is valid for this campaign *)
    if Contact.is_valid_for_campaign_scheduling context.config.organization campaign_instance contact then
      (* Check organization-level exclusions *)
      match should_exclude_contact context.config campaign_config contact with
      | Some exclusion_reason ->
          (* Contact is excluded - create skipped schedule *)
          let scheduled_date = current_date () in (* Placeholder date *)
          let campaign_email = {
            campaign_type = campaign_config.name;
            instance_id = campaign_instance.id;
            respect_exclusions = campaign_config.respect_exclusion_windows;
            days_before_event = campaign_config.days_before_event;
            priority = campaign_config.priority;
          } in
          let schedule = {
            contact_id = contact.id;
            email_type = Campaign campaign_email;
            scheduled_date;
            scheduled_time = send_time;
            status = Skipped exclusion_reason;
            priority = campaign_config.priority;
            template_id = campaign_instance.email_template;
            campaign_instance_id = Some campaign_instance.id;
            scheduler_run_id = context.run_id;
          } in
          schedules := schedule :: !schedules
      | None ->
          (* Contact is eligible - calculate schedule date *)
          let scheduled_date = 
            if campaign_config.spread_evenly then
              match (campaign_instance.spread_start_date, campaign_instance.spread_end_date) with
              | (Some start_date, Some end_date) ->
                  calculate_spread_date contact.id start_date end_date
              | _ ->
                  (* Fallback to regular calculation if spread dates not set *)
                  let today = current_date () in
                  add_days today campaign_config.days_before_event
            else
              (* Regular campaign scheduling *)
              let trigger_date = 
                if campaign_config.target_all_contacts then
                  current_date () (* Use today as trigger for "all contacts" campaigns *)
                else
                  (* Get trigger date from contact_campaigns table *)
                  match get_contact_campaigns_for_instance campaign_instance.id with
                  | Ok contact_campaigns ->
                      (match List.find_opt (fun cc -> cc.contact_id = contact.id) contact_campaigns with
                       | Some cc -> 
                           (match cc.trigger_date with
                            | Some date -> date
                            | None -> current_date ())
                       | None -> current_date ())
                  | Error _ -> current_date ()
              in
              add_days trigger_date campaign_config.days_before_event
          in
          
          (* Create campaign email type *)
          let campaign_email = {
            campaign_type = campaign_config.name;
            instance_id = campaign_instance.id;
            respect_exclusions = campaign_config.respect_exclusion_windows;
            days_before_event = campaign_config.days_before_event;
            priority = campaign_config.priority;
          } in
          
          let email_type = Campaign campaign_email in
          
          (* Check exclusion windows if required *)
          let should_skip = 
            if campaign_config.respect_exclusion_windows then
              should_skip_email contact email_type scheduled_date
            else
              false
          in
          
          let (status, _skip_reason) = 
            if should_skip then
              let reason = match check_exclusion_window contact scheduled_date with
                | Excluded { reason; _ } -> reason
                | NotExcluded -> "Unknown exclusion"
              in
              (Skipped reason, reason)
            else
              (PreScheduled, "")
          in
          
          let schedule = {
            contact_id = contact.id;
            email_type;
            scheduled_date;
            scheduled_time = send_time;
            status;
            priority = campaign_config.priority;
            template_id = campaign_instance.email_template;
            campaign_instance_id = Some campaign_instance.id;
            scheduler_run_id = context.run_id;
          } in
          schedules := schedule :: !schedules
  ) contacts;
  
  !schedules

(** 
 * [calculate_anniversary_emails]: Generates anniversary email schedules for a contact
 * 
 * Purpose:
 *   Creates email schedules for birthday and effective date anniversaries based on
 *   contact data and organization configuration, applying exclusion rules.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and timing settings
 *   - contact: Contact record with birthday, effective_date, and other data
 * 
 * Returns:
 *   List of email_schedule records for anniversary emails (birthday and effective date)
 * 
 * Business Logic:
 *   - Checks organization-level failed underwriting exclusion policy
 *   - Calculates next anniversary dates for birthday and effective date
 *   - Applies days_before configuration for email timing
 *   - Evaluates exclusion windows and creates appropriate status
 *   - Handles minimum time threshold for effective date emails
 *   - Creates audit trail with skip reasons when applicable
 * 
 * Usage Example:
 *   Called by calculate_schedules_for_contact for each valid contact
 * 
 * Error Cases:
 *   - Missing birthday/effective_date are handled gracefully (no emails created)
 *   - Exclusion window checks may result in Skipped status
 * 
 * @business_rule @data_flow
 *)
let calculate_anniversary_emails context contact =
  let today = current_date () in
  let schedules = ref [] in
  
  let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
  
  (* Check organization-level underwriting exclusion for anniversary emails *)
  if context.config.organization.exclude_failed_underwriting_global && contact.failed_underwriting then
    (* Skip all anniversary emails for failed underwriting *)
    !schedules
  else (
    begin match contact.birthday with
    | Some birthday ->
        let next_bday = next_anniversary today birthday in
        let birthday_send_date = add_days next_bday (-context.config.birthday_days_before) in
        
        if not (should_skip_email contact (Anniversary Birthday) birthday_send_date) then
          let schedule = {
            contact_id = contact.id;
            email_type = Anniversary Birthday;
            scheduled_date = birthday_send_date;
            scheduled_time = send_time;
            status = PreScheduled;
            priority = priority_of_email_type (Anniversary Birthday);
            template_id = Some "birthday_template";
            campaign_instance_id = None;
            scheduler_run_id = context.run_id;
          } in
          schedules := schedule :: !schedules
        else
          let skip_reason = match check_exclusion_window contact birthday_send_date with
            | Excluded { reason; _ } -> reason
            | NotExcluded -> "Unknown exclusion"
          in
          let schedule = {
            contact_id = contact.id;
            email_type = Anniversary Birthday;
            scheduled_date = birthday_send_date;
            scheduled_time = send_time;
            status = Skipped skip_reason;
            priority = priority_of_email_type (Anniversary Birthday);
            template_id = Some "birthday_template";
            campaign_instance_id = None;
            scheduler_run_id = context.run_id;
          } in
          schedules := schedule :: !schedules
    | None -> ()
    end;
    
    begin match contact.effective_date with
    | Some ed ->
        (* Check if enough time has passed since effective date *)
        if should_send_effective_date_email context.config contact ed then
          let next_ed = next_anniversary today ed in
          let ed_send_date = add_days next_ed (-context.config.effective_date_days_before) in
          
          if not (should_skip_email contact (Anniversary EffectiveDate) ed_send_date) then
            let schedule = {
              contact_id = contact.id;
              email_type = Anniversary EffectiveDate;
              scheduled_date = ed_send_date;
              scheduled_time = send_time;
              status = PreScheduled;
              priority = priority_of_email_type (Anniversary EffectiveDate);
              template_id = Some "effective_date_template";
              campaign_instance_id = None;
              scheduler_run_id = context.run_id;
            } in
            schedules := schedule :: !schedules
          else
            let skip_reason = match check_exclusion_window contact ed_send_date with
              | Excluded { reason; _ } -> reason
              | NotExcluded -> "Unknown exclusion"
            in
            let schedule = {
              contact_id = contact.id;
              email_type = Anniversary EffectiveDate;
              scheduled_date = ed_send_date;
              scheduled_time = send_time;
              status = Skipped skip_reason;
              priority = priority_of_email_type (Anniversary EffectiveDate);
              template_id = Some "effective_date_template";
              campaign_instance_id = None;
              scheduler_run_id = context.run_id;
            } in
            schedules := schedule :: !schedules
    | None -> ()
    end;
    
    !schedules
  )

(** 
 * [calculate_post_window_emails]: Generates post-exclusion window email schedules
 * 
 * Purpose:
 *   Creates email schedules for contacts who had emails skipped during exclusion
 *   windows, to be sent after the window period ends.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration settings
 *   - contact: Contact record that may need post-window emails
 * 
 * Returns:
 *   List containing single post-window email schedule or empty list
 * 
 * Business Logic:
 *   - Checks if organization enables post-window email feature
 *   - Retrieves calculated post-window date from exclusion logic
 *   - Creates single email schedule with PostWindow anniversary type
 *   - Uses standard send time and priority settings
 * 
 * Usage Example:
 *   Called by calculate_schedules_for_contact for contacts with exclusion history
 * 
 * Error Cases:
 *   - Returns empty list if organization disables feature
 *   - Returns empty list if no post-window date calculated
 * 
 * @business_rule
 *)
let calculate_post_window_emails context contact =
  (* Check if organization enables post-window emails *)
  if not context.config.organization.enable_post_window_emails then
    []
  else
    match get_post_window_date contact with
    | Some post_date ->
        let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
        let schedule = {
          contact_id = contact.id;
          email_type = Anniversary PostWindow;
          scheduled_date = post_date;
          scheduled_time = send_time;
          status = PreScheduled;
          priority = priority_of_email_type (Anniversary PostWindow);
          template_id = Some "post_window_template";
          campaign_instance_id = None;
          scheduler_run_id = context.run_id;
        } in
        [schedule]
    | None -> []

(** 
 * [generate_post_window_for_skipped]: Generates post-window emails for schedules skipped due to exclusions
 * 
 * Purpose:
 *   Automatically creates post-window makeup emails for any schedules that were
 *   skipped due to exclusion windows during the current scheduling run.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and timing settings  
 *   - skipped_schedules: List of schedules that were skipped due to exclusions
 * 
 * Returns:
 *   List of post-window email schedules for skipped emails
 * 
 * Business Logic:
 *   - Filters skipped schedules for exclusion-related skip reasons
 *   - Calculates appropriate post-window dates for each skipped email
 *   - Creates makeup emails to be sent after exclusion window ends
 *   - Respects organization enable_post_window_emails setting
 * 
 * @business_rule @data_flow
 *)
let generate_post_window_for_skipped context skipped_schedules =
  if not context.config.organization.enable_post_window_emails then
    []
  else
    let post_window_schedules = ref [] in
    let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
    
    List.iter (fun (schedule : email_schedule) ->
      match schedule.status with
      | Skipped reason when (try Str.search_forward (Str.regexp "exclusion\\|window") reason 0 >= 0 with Not_found -> false) ->
          (* Calculate post-window date for this skipped email *)
          (match get_all_contacts () with
           | Ok (contacts : contact list) ->
               (match List.find_opt (fun (c : contact) -> c.id = schedule.contact_id) contacts with
                | Some contact ->
                    (match get_post_window_date contact with
                     | Some post_date ->
                         let post_window_schedule = {
                           contact_id = schedule.contact_id;
                           email_type = Anniversary PostWindow;
                           scheduled_date = post_date;
                           scheduled_time = send_time;
                           status = PreScheduled;
                           priority = priority_of_email_type (Anniversary PostWindow);
                           template_id = Some "post_window_template";
                           campaign_instance_id = None;
                           scheduler_run_id = context.run_id;
                         } in
                         post_window_schedules := post_window_schedule :: !post_window_schedules
                     | None -> ())
                | None -> ())
           | Error _ -> ())
      | _ -> ()
    ) skipped_schedules;
    
    !post_window_schedules

(** 
 * [calculate_schedules_for_contact]: Generates all email schedules for a single contact
 * 
 * Purpose:
 *   Core scheduling function that determines which emails should be sent to a contact
 *   and when, based on their anniversaries, state rules, and organization policies.
 * 
 * Parameters:
 *   - context: Scheduling context containing config, run_id, and load balancing settings
 *   - contact: The contact record with birthday, effective_date, state, etc.
 * 
 * Returns:
 *   Result containing list of email_schedule records or scheduler_error
 * 
 * Business Logic:
 *   - Validates contact has required data for anniversary scheduling
 *   - Calculates anniversary-based emails (birthday, effective_date)
 *   - Applies state exclusion windows based on contact.state
 *   - Adds post-window emails if any were skipped
 *   - Respects organization configuration for timing and exclusions
 * 
 * Usage Example:
 *   Called by process_contact_batch for each contact in batch processing
 * 
 * Error Cases:
 *   - InvalidContactData: Missing required fields or validation failure
 *   - UnexpectedError: Unhandled exceptions during processing
 * 
 * @business_rule @data_flow
 *)
let calculate_schedules_for_contact context contact =
  try
    if not (Contact.is_valid_for_anniversary_scheduling context.config.organization contact) then
      Error (InvalidContactData { 
        contact_id = contact.id; 
        reason = "Contact failed anniversary scheduling validation" 
      })
    else
      let anniversary_schedules = calculate_anniversary_emails context contact in
      let post_window_schedules = calculate_post_window_emails context contact in
      let all_schedules = anniversary_schedules @ post_window_schedules in
      Ok all_schedules
  with e ->
    Error (UnexpectedError e)

(** 
 * [calculate_all_campaign_schedules]: Generates schedules for all active campaigns
 * 
 * Purpose:
 *   Orchestrates campaign email scheduling across all active campaign instances,
 *   retrieving configurations and handling errors at the campaign level.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and settings
 * 
 * Returns:
 *   Tuple of (schedule_list, error_list) containing all campaign schedules and any errors
 * 
 * Business Logic:
 *   - Retrieves all active campaign instances from database
 *   - For each instance, gets campaign type configuration
 *   - Calls calculate_campaign_emails for schedule generation
 *   - Accumulates all schedules and errors for return
 *   - Continues processing even if individual campaigns fail
 * 
 * Usage Example:
 *   Called by schedule_emails_streaming to handle all campaign scheduling
 * 
 * Error Cases:
 *   - Database errors accessing campaigns are collected and returned
 *   - Individual campaign failures don't stop overall processing
 * 
 * @integration_point @data_flow
 *)
let calculate_all_campaign_schedules context =
  let all_schedules = ref [] in
  let errors = ref [] in
  
  match get_active_campaign_instances () with
  | Error err -> 
      errors := (DatabaseError (string_of_db_error err)) :: !errors;
      (!all_schedules, !errors)
  | Ok campaign_instances ->
      List.iter (fun campaign_instance ->
        match get_campaign_type_config campaign_instance.campaign_type with
        | Error err ->
            errors := (DatabaseError (string_of_db_error err)) :: !errors
        | Ok campaign_config ->
            let campaign_schedules = calculate_campaign_emails context campaign_instance campaign_config in
            all_schedules := campaign_schedules @ !all_schedules
      ) campaign_instances;
      (!all_schedules, !errors)

type batch_result = {
  schedules: email_schedule list;
  contacts_processed: int;
  emails_scheduled: int;
  emails_skipped: int;
  errors: scheduler_error list;
}

(** 
 * [process_contact_batch]: Processes a batch of contacts for anniversary email scheduling
 * 
 * Purpose:
 *   Efficiently processes a subset of contacts in parallel, calculating schedules
 *   and collecting metrics for batch processing performance optimization.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and run information
 *   - contacts: List of contacts to process in this batch
 * 
 * Returns:
 *   batch_result record containing schedules, metrics, and any errors encountered
 * 
 * Business Logic:
 *   - Processes each contact individually for anniversary scheduling
 *   - Accumulates all generated schedules from the batch
 *   - Tracks processing metrics (scheduled, skipped, errors)
 *   - Continues processing even if individual contacts fail
 *   - Provides detailed statistics for monitoring and debugging
 * 
 * Usage Example:
 *   Called by schedule_emails_streaming for each chunk of contacts
 * 
 * Error Cases:
 *   - Individual contact errors are collected but don't stop batch processing
 *   - Returns comprehensive metrics even when some contacts fail
 * 
 * @performance @data_flow
 *)
let process_contact_batch context contacts =
  let all_schedules = ref [] in
  let contacts_processed = ref 0 in
  let emails_scheduled = ref 0 in
  let emails_skipped = ref 0 in
  let errors = ref [] in
  
  List.iter (fun contact ->
    incr contacts_processed;
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        all_schedules := schedules @ !all_schedules;
        List.iter (fun (schedule : email_schedule) ->
          match schedule.status with
          | PreScheduled -> incr emails_scheduled
          | Skipped _ -> incr emails_skipped
          | _ -> ()
        ) schedules
    | Error err ->
        errors := err :: !errors
  ) contacts;
  
  {
    schedules = !all_schedules;
    contacts_processed = !contacts_processed;
    emails_scheduled = !emails_scheduled;
    emails_skipped = !emails_skipped;
    errors = !errors;
  }

(** 
 * [manage_campaign_lifecycle]: Manages campaign instance activation/deactivation based on dates
 * 
 * Purpose:
 *   Automatically activates and deactivates campaign instances based on their
 *   active_start_date and active_end_date fields to ensure only current campaigns run.
 * 
 * Parameters:
 *   - context: Scheduling context (unused but kept for consistency)
 * 
 * Returns:
 *   Result indicating success or database error
 * 
 * Business Logic:
 *   - Checks all campaign instances against current date
 *   - Activates instances whose start date has arrived
 *   - Deactivates instances whose end date has passed
 *   - Provides audit trail of lifecycle changes
 * 
 * @business_rule @state_machine
 *)
let manage_campaign_lifecycle _context =
  let today = current_date () in
  let today_str = string_of_date today in
  
  (* Get all campaign instances with date ranges *)
  let query = Printf.sprintf {|
    SELECT id, campaign_type, instance_name,
           COALESCE(active_start_date, '') as active_start_date,
           COALESCE(active_end_date, '') as active_end_date,
           COALESCE(metadata, '{}') as metadata
    FROM campaign_instances
    WHERE (active_start_date IS NOT NULL OR active_end_date IS NOT NULL)
  |} in
  
  match execute_sql_safe query with
  | Error err -> Error (DatabaseError (string_of_db_error err))
  | Ok rows ->
      let process_instance row =
        match row with
        | [id_str; _campaign_type; _instance_name; active_start_date; active_end_date; _metadata] ->
            (try
              let id = int_of_string id_str in
              let should_be_active = 
                let after_start = 
                  if active_start_date = "" || active_start_date = "NULL" then true
                  else (parse_date active_start_date) <= today
                in
                let before_end = 
                  if active_end_date = "" || active_end_date = "NULL" then true
                  else today <= (parse_date active_end_date)
                in
                after_start && before_end
              in
              
              (* Update metadata to track lifecycle changes *)
              let updated_metadata = 
                if should_be_active then
                  Printf.sprintf "{\"lifecycle_status\": \"active\", \"last_checked\": \"%s\"}" today_str
                else
                  Printf.sprintf "{\"lifecycle_status\": \"inactive\", \"last_checked\": \"%s\"}" today_str
              in
              
              let update_sql = Printf.sprintf {|
                UPDATE campaign_instances 
                SET metadata = '%s', updated_at = CURRENT_TIMESTAMP
                WHERE id = %d
              |} updated_metadata id in
              
              execute_sql_no_result update_sql
            with _ -> Ok ())
        | _ -> Ok ()
      in
      
             (* Process all instances *)
       let rec process_all rows =
         match rows with
         | [] -> Ok ()
         | row :: rest ->
             (match process_instance row with
              | Ok () -> process_all rest
              | Error err -> Error (DatabaseError (string_of_db_error err)))
       in
       
       process_all rows

(** 
 * [extract_date_from_datetime_string]: Safely extracts date from either date or datetime string
 * 
 * Purpose:
 *   Handles database values that could be either date strings (YYYY-MM-DD) or 
 *   datetime strings (YYYY-MM-DD HH:MM:SS) by extracting just the date portion.
 * 
 * Parameters:
 *   - datetime_or_date_str: String that could be date or datetime format
 * 
 * Returns:
 *   Date extracted from the string
 * 
 * Business Logic:
 *   - If string contains space (datetime format), takes only the date part
 *   - If string has no space (date format), uses as-is
 *   - Handles COALESCE(actual_send_datetime, scheduled_send_date) safely
 * 
 * @utility
 *)
let extract_date_from_datetime_string datetime_or_date_str =
  (* Check if the string contains time information (has a space) *)
  match String.index_opt datetime_or_date_str ' ' with
  | Some space_index ->
      (* Extract just the date part (before the space) *)
      let date_part = String.sub datetime_or_date_str 0 space_index in
      parse_date date_part
  | None ->
      (* No space found, treat as date string *)
      parse_date datetime_or_date_str

(** 
 * [determine_followup_type]: Determines the appropriate follow-up email type based on contact interactions
 * 
 * Purpose:
 *   Analyzes contact engagement behavior to select the most appropriate follow-up email
 *   template based on clicks, health question answers, and medical conditions.
 * 
 * Parameters:
 *   - contact_id: The contact ID to analyze
 *   - since_date: Date from which to analyze interactions (typically when initial email was sent)
 * 
 * Returns:
 *   Result containing followup_type or scheduler_error
 * 
 * Business Logic:
 *   - Checks for clicks and health question responses
 *   - Prioritizes follow-ups based on engagement level
 *   - Uses highest applicable follow-up type for contact behavior
 * 
 * @business_rule
 *)
let determine_followup_type contact_id since_date =
  match get_contact_interactions contact_id since_date with
  | Error err -> Error (DatabaseError (string_of_db_error err))
  | Ok (has_clicks, has_health_answers) ->
      if has_health_answers then
        (* For now, assume no medical conditions check - would need additional logic *)
        Ok HQNoYes
      else if has_clicks then
        Ok ClickedNoHQ
      else
        Ok Cold

(** 
 * [calculate_followup_emails]: Generates follow-up email schedules for eligible contacts
 * 
 * Purpose:
 *   Identifies contacts who need follow-up emails based on their sent emails and
 *   creates appropriate follow-up schedules based on engagement behavior.
 * 
 * Parameters:
 *   - context: Scheduling context with configuration and timing settings
 * 
 * Returns:
 *   List of email_schedule records for follow-up emails
 * 
 * Business Logic:
 *   - Looks back for sent emails that need follow-ups
 *   - Analyzes contact engagement behavior for each email
 *   - Schedules follow-ups based on configured delay
 *   - Excludes contacts with existing follow-ups
 *   - Respects exclusion windows for follow-up scheduling
 * 
 * @business_rule @data_flow
 *)
let calculate_followup_emails context =
  let schedules = ref [] in
  let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
  let lookback_days = 35 in (* Look back 35 days for eligible emails *)
  
  match get_sent_emails_for_followup lookback_days with
  | Error _ -> !schedules (* Return empty list on error *)
  | Ok sent_emails ->
      List.iter (fun (contact_id, email_type, sent_time, _email_id) ->
        (* Check if this email type is eligible for follow-ups *)
        let is_eligible_for_followup = match email_type with
          | "birthday" | "effective_date" | "aep" | "post_window" -> true
          | email_type_str when String.starts_with ~prefix:"campaign_" email_type_str ->
              (* For campaign emails, check if the campaign has enable_followups=true *)
              let campaign_type = String.sub email_type_str 9 (String.length email_type_str - 9) in
              (match get_campaign_type_config campaign_type with
               | Ok campaign_config -> campaign_config.enable_followups
               | Error _ -> false)
          | _ -> false
        in
        
        if is_eligible_for_followup then (
          (* Check if contact already has follow-ups scheduled *)
          let has_existing_followup = 
            match execute_sql_safe (Printf.sprintf {|
              SELECT COUNT(*) FROM email_schedules 
              WHERE contact_id = %d 
              AND email_type LIKE 'followup%%' 
              AND status IN ('pre-scheduled', 'scheduled', 'sent')
            |} contact_id) with
            | Ok [["0"]] -> false
            | _ -> true
          in
          
          if not has_existing_followup then (
          (* Determine follow-up type based on behavior *)
          let sent_date = extract_date_from_datetime_string sent_time in
          let since_date_str = string_of_date sent_date in
          
          match determine_followup_type contact_id since_date_str with
          | Error _ -> () (* Skip on error *)
          | Ok followup_type ->
              (* Schedule follow-up for configured delay after sent date *)
              let followup_date = add_days sent_date context.config.followup_delay_days in
              let today = current_date () in
              
              (* If follow-up is overdue, schedule for tomorrow *)
              let scheduled_date = 
                if followup_date < today then
                  add_days today 1
                else
                  followup_date
              in
              
                             (* Get contact for exclusion window check *)
               (match get_all_contacts () with
                | Ok (contacts : contact list) ->
                    (match List.find_opt (fun (c : contact) -> c.id = contact_id) contacts with
                    | Some contact ->
                        let email_type = Followup followup_type in
                        
                        (* Check exclusion windows *)
                        let should_skip = should_skip_email contact email_type scheduled_date in
                        
                        let (status, _skip_reason) = 
                          if should_skip then
                            let reason = match check_exclusion_window contact scheduled_date with
                              | Excluded { reason; _ } -> reason
                              | NotExcluded -> "Unknown exclusion"
                            in
                            (Skipped reason, reason)
                          else
                            (PreScheduled, "")
                        in
                        
                        let schedule = {
                          contact_id;
                          email_type;
                          scheduled_date;
                          scheduled_time = send_time;
                          status;
                          priority = priority_of_email_type email_type;
                          template_id = Some (Printf.sprintf "%s_template" (string_of_followup_type followup_type));
                          campaign_instance_id = None;
                          scheduler_run_id = context.run_id;
                        } in
                        schedules := schedule :: !schedules
                    | None -> ())
               | Error _ -> ())
          )
        )
      ) sent_emails;
      
             !schedules

(** 
 * [check_frequency_limits]: Checks if contact exceeds email frequency limits
 * 
 * Purpose:
 *   Enforces maximum emails per period limits to prevent overwhelming contacts
 *   and ensures compliance with organization email frequency policies.
 * 
 * Parameters:
 *   - context: Scheduling context with frequency limit configuration
 *   - contact_id: Contact to check frequency limits for
 *   - proposed_date: Date for which to schedule the new email
 * 
 * Returns:
 *   Result containing boolean (true if within limits) or scheduler_error
 * 
 * Business Logic:
 *   - Counts emails sent/scheduled within the configured period
 *   - Compares against max_emails_per_period configuration
 *   - Excludes skipped emails from count
 *   - Provides specific limit exceeded reason
 * 
 * @business_rule
 *)
let check_frequency_limits context contact_id proposed_date =
  let period_start = add_days proposed_date (-context.config.period_days) in
  let period_start_str = string_of_date period_start in
  let proposed_date_str = string_of_date proposed_date in
  
  let count_query = Printf.sprintf {|
    SELECT COUNT(*) 
    FROM email_schedules 
    WHERE contact_id = %d 
    AND scheduled_send_date BETWEEN '%s' AND '%s'
    AND status IN ('pre-scheduled', 'scheduled', 'sent', 'delivered')
  |} contact_id period_start_str proposed_date_str in
  
  match execute_sql_safe count_query with
  | Error err -> Error (DatabaseError (string_of_db_error err))
  | Ok [[ count_str ]] ->
      (try
        let current_count = int_of_string count_str in
        if current_count >= context.config.max_emails_per_period then
          Ok false (* Exceeds limit *)
        else
          Ok true (* Within limit *)
      with _ -> Error (ValidationError "Invalid email count from database"))
  | Ok _ -> Error (ValidationError "Invalid frequency check result")

(** 
 * [apply_frequency_limits]: Filters email schedules based on frequency limits
 * 
 * Purpose:
 *   Applies frequency limit enforcement to a list of proposed email schedules,
 *   prioritizing higher priority emails when limits are exceeded.
 * 
 * Parameters:
 *   - context: Scheduling context with frequency limit configuration
 *   - schedules: List of proposed email schedules to filter
 * 
 * Returns:
 *   Tuple of (allowed_schedules, frequency_limited_schedules)
 * 
 * Business Logic:
 *   - Groups schedules by contact_id for frequency checking
 *   - Sorts schedules by priority (lower number = higher priority)
 *   - Allows highest priority emails within frequency limits
 *   - Marks excess emails as skipped due to frequency limits
 * 
 * @business_rule @performance
 *)
let apply_frequency_limits context schedules =
  let allowed_schedules = ref [] in
  let limited_schedules = ref [] in
  
  (* Group schedules by contact_id *)
  let contact_groups = 
    List.fold_left (fun acc (schedule : email_schedule) ->
      let contact_id = schedule.contact_id in
      let existing = try List.assoc contact_id acc with Not_found -> [] in
      (contact_id, schedule :: existing) :: (List.remove_assoc contact_id acc)
    ) [] schedules
  in
  
  (* Process each contact's schedules *)
  List.iter (fun (contact_id, contact_schedules) ->
    (* Sort by priority (lower number = higher priority) *)
    let sorted_schedules : email_schedule list = List.sort (fun (a : email_schedule) (b : email_schedule) -> compare a.priority b.priority) contact_schedules in
    
    List.iter (fun (schedule : email_schedule) ->
      match check_frequency_limits context contact_id schedule.scheduled_date with
      | Error _ -> 
          (* On error, allow the email (conservative approach) *)
          allowed_schedules := schedule :: !allowed_schedules
      | Ok within_limits ->
          if within_limits then
            allowed_schedules := schedule :: !allowed_schedules
          else
            (* Create skipped version due to frequency limits *)
            let limited_schedule = {
              schedule with 
              status = Skipped "Frequency limit exceeded";
            } in
            limited_schedules := limited_schedule :: !limited_schedules
    ) sorted_schedules
  ) contact_groups;
  
  (!allowed_schedules, !limited_schedules)

(** 
 * [resolve_campaign_conflicts]: Resolves conflicts when multiple campaigns target same contact on same date
 * 
 * Purpose:
 *   Handles priority conflicts when multiple campaign emails are scheduled for the
 *   same contact on the same date, keeping highest priority and skipping others.
 * 
 * Parameters:
 *   - schedules: List of email schedules potentially containing conflicts
 * 
 * Returns:
 *   Tuple of (resolved_schedules, conflicted_schedules)
 * 
 * Business Logic:
 *   - Groups schedules by (contact_id, scheduled_date)
 *   - For each group, selects highest priority email (lowest number)
 *   - Marks other emails as skipped due to campaign conflicts
 *   - Preserves non-campaign emails (anniversary, follow-up) alongside campaigns
 * 
 * @business_rule
 *)
let resolve_campaign_conflicts schedules =
  let resolved_schedules = ref [] in
  let conflicted_schedules = ref [] in
  
  (* Group schedules by contact_id and scheduled_date *)
  let date_groups = 
    List.fold_left (fun acc (schedule : email_schedule) ->
      let key = (schedule.contact_id, schedule.scheduled_date) in
      let existing = try List.assoc key acc with Not_found -> [] in
      (key, schedule :: existing) :: (List.remove_assoc key acc)
    ) [] schedules
  in
  
  (* Process each date group *)
  List.iter (fun ((contact_id, date), group_schedules) ->
    (* Validate that all schedules in group actually match the key *)
    List.iter (fun (s : email_schedule) ->
      if s.contact_id <> contact_id || s.scheduled_date <> date then
        failwith (Printf.sprintf "Grouping error: schedule contact_id=%d date=%s doesn't match group key contact_id=%d date=%s"
                   s.contact_id (string_of_date s.scheduled_date) contact_id (string_of_date date))
    ) group_schedules;
    
    (* Separate campaign emails from other types *)
    let (campaign_emails, other_emails) = 
      List.partition (fun (s : email_schedule) ->
        match s.email_type with
        | Campaign _ -> true
        | _ -> false
      ) group_schedules
    in
    
    (* Always keep non-campaign emails *)
    resolved_schedules := other_emails @ !resolved_schedules;
    
    (* Handle campaign conflicts for contact_id on date *)
    match campaign_emails with
    | [] -> () (* No campaigns for this contact on this date *)
    | [single_campaign] -> 
        (* Single campaign, no conflict for contact_id on date *)
        resolved_schedules := single_campaign :: !resolved_schedules
    | multiple_campaigns ->
        (* Multiple campaigns for contact_id on date - resolve by priority *)
        let sorted_campaigns : email_schedule list = List.sort (fun (a : email_schedule) (b : email_schedule) -> compare a.priority b.priority) multiple_campaigns in
        match sorted_campaigns with
        | highest_priority :: conflicts ->
            (* Keep highest priority campaign for contact_id on date *)
            resolved_schedules := highest_priority :: !resolved_schedules;
            (* Skip conflicting campaigns for contact_id on date *)
            List.iter (fun (conflict : email_schedule) ->
              let skipped_conflict = {
                conflict with 
                status = Skipped (Printf.sprintf "Campaign priority conflict on %s for contact %d" 
                                   (string_of_date date) contact_id);
              } in
              conflicted_schedules := skipped_conflict :: !conflicted_schedules
            ) conflicts
        | [] -> () (* Should not happen *)
  ) date_groups;
  
  (!resolved_schedules, !conflicted_schedules)

(** 
 * [schedule_emails_streaming]: Main orchestration function for email scheduling
 * 
 * Purpose:
 *   Top-level function that coordinates all email scheduling including anniversary
 *   emails, campaigns, load balancing, and provides comprehensive execution results.
 * 
 * Parameters:
 *   - contacts: List of all contacts to process for anniversary emails
 *   - config: Configuration containing organization settings and timing
 *   - total_contacts: Total contact count for load balancing calculations
 * 
 * Returns:
 *   Result containing batch_result with all schedules and metrics, or scheduler_error
 * 
 * Business Logic:
 *   - Creates scheduling context with run ID and load balancing config
 *   - Processes campaign schedules first (independent of contact batching)
 *   - Processes anniversary contacts in configurable batch sizes
 *   - Combines anniversary and campaign schedules
 *   - Applies load balancing distribution to final schedules
 *   - Provides comprehensive metrics and error reporting
 * 
 * Usage Example:
 *   Main entry point called by external scheduler with full contact list
 * 
 * Error Cases:
 *   - Database errors, validation failures, unexpected exceptions
 *   - Returns detailed error information for debugging
 * 
 * @integration_point @state_machine @performance
 *)
let schedule_emails_streaming ~contacts ~config ~total_contacts =
  try
    let context = create_context config total_contacts in
    let chunk_size = config.batch_size in
    
    (* Manage campaign lifecycle before scheduling *)
    let _ = manage_campaign_lifecycle context in
    
    (* First, calculate all campaign schedules *)
    let (campaign_schedules, campaign_errors) = calculate_all_campaign_schedules context in
    
    (* Calculate follow-up email schedules *)
    let followup_schedules = calculate_followup_emails context in
    
    let rec process_chunks remaining_contacts acc_result =
      match remaining_contacts with
      | [] -> Ok acc_result
      | _ ->
          let (chunk, rest) = 
            let rec take n lst acc =
              if n = 0 || lst = [] then (List.rev acc, lst)
              else match lst with
                | h :: t -> take (n - 1) t (h :: acc)
                | [] -> (List.rev acc, [])
            in
            take chunk_size remaining_contacts []
          in
          
          let batch_result = process_contact_batch context chunk in
          
          let new_acc = {
            schedules = batch_result.schedules @ acc_result.schedules;
            contacts_processed = acc_result.contacts_processed + batch_result.contacts_processed;
            emails_scheduled = acc_result.emails_scheduled + batch_result.emails_scheduled;
            emails_skipped = acc_result.emails_skipped + batch_result.emails_skipped;
            errors = batch_result.errors @ acc_result.errors;
          } in
          
          process_chunks rest new_acc
    in
    
    let initial_result = {
      schedules = [];
      contacts_processed = 0;
      emails_scheduled = 0;
      emails_skipped = 0;
      errors = campaign_errors; (* Include campaign errors from the start *)
    } in
    
    match process_chunks contacts initial_result with
    | Ok raw_result ->
        (* Combine anniversary schedules with campaign schedules *)
        let all_schedules = raw_result.schedules @ campaign_schedules @ followup_schedules in
        
        (* Apply frequency limits before load balancing *)
        let (frequency_allowed_schedules, frequency_limited_schedules) = apply_frequency_limits context all_schedules in
        let frequency_filtered_schedules = frequency_allowed_schedules @ frequency_limited_schedules in
        
        (* Resolve campaign priority conflicts *)
        let (conflict_resolved_schedules, campaign_conflicts) = resolve_campaign_conflicts frequency_filtered_schedules in
        let conflict_resolved_all = conflict_resolved_schedules @ campaign_conflicts in
        
        (* Generate post-window emails for any skipped schedules *)
        let skipped_schedules = List.filter (fun (s : email_schedule) -> 
          match s.status with Skipped _ -> true | _ -> false) conflict_resolved_all in
        let auto_post_window_schedules = generate_post_window_for_skipped context skipped_schedules in
        
        (* Combine all schedules including auto-generated post-window emails *)
        let final_schedules = conflict_resolved_all @ auto_post_window_schedules in
        
        (* Count campaign schedules for metrics *)
        let campaign_scheduled = List.fold_left (fun acc (schedule : email_schedule) ->
          match schedule.status with
          | PreScheduled -> acc + 1
          | _ -> acc
        ) 0 campaign_schedules in
        
        let campaign_skipped = List.fold_left (fun acc (schedule : email_schedule) ->
          match schedule.status with
          | Skipped _ -> acc + 1
          | _ -> acc
        ) 0 campaign_schedules in
        
        (* Count follow-up schedules for metrics *)
        let followup_scheduled = List.fold_left (fun acc (schedule : email_schedule) ->
          match schedule.status with
          | PreScheduled -> acc + 1
          | _ -> acc
        ) 0 followup_schedules in
        
        let followup_skipped = List.fold_left (fun acc (schedule : email_schedule) ->
          match schedule.status with
          | Skipped _ -> acc + 1
          | _ -> acc
        ) 0 followup_schedules in
        
        (* Count frequency-limited schedules for metrics *)
        let frequency_limited_count = List.length frequency_limited_schedules in
        
        (* Count auto-generated post-window schedules for metrics *)
        let auto_post_window_count = List.length auto_post_window_schedules in
        
        (* Count campaign conflicts for metrics *)
        let campaign_conflict_count = List.length campaign_conflicts in
        
        let combined_result = {
          schedules = final_schedules;
          contacts_processed = raw_result.contacts_processed;
          emails_scheduled = raw_result.emails_scheduled + campaign_scheduled + followup_scheduled + auto_post_window_count;
          emails_skipped = raw_result.emails_skipped + campaign_skipped + followup_skipped + frequency_limited_count + campaign_conflict_count;
          errors = raw_result.errors;
        } in
        
        begin match distribute_schedules combined_result.schedules context.load_balancing_config with
        | Ok balanced_schedules ->
            Ok { combined_result with schedules = balanced_schedules }
        | Error err ->
            Error err
        end
    | Error err -> Error err
    
  with e ->
    Error (UnexpectedError e)

(** 
 * [get_scheduling_summary]: Generates human-readable summary of scheduling results
 * 
 * Purpose:
 *   Creates formatted summary text with key metrics and distribution analysis
 *   for monitoring, logging, and administrative reporting purposes.
 * 
 * Parameters:
 *   - result: batch_result containing schedules and processing metrics
 * 
 * Returns:
 *   Formatted string with comprehensive scheduling statistics
 * 
 * Business Logic:
 *   - Analyzes email distribution across dates for load balancing insights
 *   - Calculates averages, maximums, and variance for capacity planning
 *   - Provides contact processing metrics for performance monitoring
 *   - Formats data in human-readable format for reports and logs
 * 
 * Usage Example:
 *   Called after schedule_emails_streaming completes for logging and reporting
 * 
 * Error Cases:
 *   - None expected (operates on already validated result data)
 * 
 * @integration_point
 *)
let get_scheduling_summary result =
  let analysis = analyze_distribution result.schedules in
  Printf.sprintf 
    "Scheduling Summary:\n\
     - Contacts processed: %d\n\
     - Emails scheduled: %d\n\
     - Emails skipped: %d\n\
     - Total emails: %d\n\
     - Distribution over %d days\n\
     - Average per day: %.1f\n\
     - Max day: %d emails\n\
     - Distribution variance: %d"
    result.contacts_processed
    result.emails_scheduled
    result.emails_skipped
    analysis.total_emails
    analysis.total_days
    analysis.avg_per_day
    analysis.max_day
    analysis.distribution_variance