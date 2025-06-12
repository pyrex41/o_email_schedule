open Date_time
open Types
open Date_calc

module DailyStats = struct
  (** 
   * [empty]: Creates empty daily statistics record for a specific date
   * 
   * Purpose:
   *   Initializes daily statistics tracking structure with zero counts for
   *   all email types to begin accumulating load metrics.
   * 
   * Parameters:
   *   - date: Date tuple for which to create empty statistics
   * 
   * Returns:
   *   daily_stats record with zero counts and specified date
   * 
   * Business Logic:
   *   - Provides clean starting point for daily email counting
   *   - Initializes all email type counters to zero
   *   - Sets over_threshold flag to false initially
   *   - Forms basis for load balancing calculations
   * 
   * Usage Example:
   *   Called by group_by_date when encountering new date
   * 
   * Error Cases:
   *   - None expected (pure data structure creation)
   * 
   * @performance
   *)
  let empty date = {
    date;
    total_count = 0;
    ed_count = 0;
    campaign_count = 0;
    anniversary_count = 0;
    over_threshold = false;
  }

  (** 
   * [add_email]: Updates daily statistics by adding one email schedule
   * 
   * Purpose:
   *   Increments appropriate counters in daily statistics based on email type
   *   to track load distribution and support capacity planning decisions.
   * 
   * Parameters:
   *   - stats: Current daily statistics record
   *   - email_schedule: Email schedule to add to statistics
   * 
   * Returns:
   *   Updated daily_stats record with incremented counters
   * 
   * Business Logic:
   *   - Increments total count for all email types
   *   - Increments specific counters based on email type classification
   *   - Distinguishes between anniversary, campaign, and effective date emails
   *   - Maintains detailed breakdown for targeted load balancing
   * 
   * Usage Example:
   *   Called by group_by_date for each schedule on a given date
   * 
   * Error Cases:
   *   - None expected (pure counter increment operations)
   * 
   * @performance
   *)
  let add_email stats email_schedule =
    let new_total = stats.total_count + 1 in
    let new_ed = match email_schedule.email_type with
      | Anniversary EffectiveDate -> stats.ed_count + 1
      | _ -> stats.ed_count
    in
    let new_campaign = match email_schedule.email_type with
      | Campaign _ -> stats.campaign_count + 1
      | _ -> stats.campaign_count
    in
    let new_anniversary = match email_schedule.email_type with
      | Anniversary _ -> stats.anniversary_count + 1
      | _ -> stats.anniversary_count
    in
    { stats with 
      total_count = new_total;
      ed_count = new_ed;
      campaign_count = new_campaign;
      anniversary_count = new_anniversary;
    }
end

(** 
 * [group_by_date]: Groups email schedules by date and computes daily statistics
 * 
 * Purpose:
 *   Aggregates email schedules by scheduled date to create daily load statistics
 *   for analysis and load balancing decision making.
 * 
 * Parameters:
 *   - schedules: List of email schedules to group and analyze
 * 
 * Returns:
 *   List of daily_stats records, one for each date with scheduled emails
 * 
 * Business Logic:
 *   - Uses hashtable for efficient date-based grouping
 *   - Accumulates email counts per date for load analysis
 *   - Creates detailed breakdown by email type for targeted balancing
 *   - Provides foundation for capacity planning and smoothing algorithms
 * 
 * Usage Example:
 *   Called by load balancing functions to analyze current distribution
 * 
 * Error Cases:
 *   - None expected (handles empty schedule lists gracefully)
 * 
 * @performance @data_flow
 *)
let group_by_date schedules =
  let date_map = Hashtbl.create 1000 in
  List.iter (fun schedule ->
    let date = schedule.scheduled_date in
    let current_stats = 
      match Hashtbl.find_opt date_map date with
      | Some stats -> stats
      | None -> DailyStats.empty date
    in
    let updated_stats = DailyStats.add_email current_stats schedule in
    Hashtbl.replace date_map date updated_stats
  ) schedules;
  Hashtbl.fold (fun _date stats acc -> stats :: acc) date_map []

(** 
 * [calculate_daily_cap]: Calculates daily email sending capacity limit
 * 
 * Purpose:
 *   Determines maximum emails per day based on total contact count and
 *   configured percentage cap to prevent overwhelming email volumes.
 * 
 * Parameters:
 *   - config: Load balancing configuration with percentage cap and contact count
 * 
 * Returns:
 *   Integer representing maximum emails allowed per day
 * 
 * Business Logic:
 *   - Applies percentage cap to total contact count
 *   - Ensures sustainable email sending volumes
 *   - Provides hard limit for daily email distribution
 *   - Supports capacity planning and resource management
 * 
 * Usage Example:
 *   Called by cap enforcement functions to determine redistribution thresholds
 * 
 * Error Cases:
 *   - None expected (arithmetic on validated configuration values)
 * 
 * @business_rule @performance
 *)
let calculate_daily_cap config =
  int_of_float (float_of_int config.total_contacts *. config.daily_send_percentage_cap)

(** 
 * [calculate_ed_soft_limit]: Calculates soft limit for effective date emails per day
 * 
 * Purpose:
 *   Determines target limit for effective date anniversary emails to prevent
 *   clustering and ensure balanced distribution across dates.
 * 
 * Parameters:
 *   - config: Load balancing configuration with ED limit and percentage cap
 * 
 * Returns:
 *   Integer representing soft limit for effective date emails per day
 * 
 * Business Logic:
 *   - Uses configured ED daily soft limit as baseline
 *   - Caps at 30% of overall daily capacity
 *   - Prevents effective date emails from dominating daily volume
 *   - Enables targeted smoothing of anniversary clusters
 * 
 * Usage Example:
 *   Called by effective date smoothing algorithms
 * 
 * Error Cases:
 *   - None expected (arithmetic on validated configuration values)
 * 
 * @business_rule @performance
 *)
let calculate_ed_soft_limit config =
  let org_cap = calculate_daily_cap config in
  min config.ed_daily_soft_limit (int_of_float (float_of_int org_cap *. 0.3))

(** 
 * [is_over_threshold]: Checks if daily statistics exceed overage threshold
 * 
 * Purpose:
 *   Determines if a day's email count exceeds the configured overage threshold
 *   requiring redistribution to maintain sustainable sending patterns.
 * 
 * Parameters:
 *   - config: Load balancing configuration with overage threshold
 *   - stats: Daily statistics to evaluate
 * 
 * Returns:
 *   Boolean indicating if day exceeds acceptable overage threshold
 * 
 * Business Logic:
 *   - Applies overage threshold multiplier to daily cap
 *   - Identifies days requiring load redistribution
 *   - Triggers redistribution algorithms when threshold exceeded
 *   - Maintains flexibility while preventing extreme clustering
 * 
 * Usage Example:
 *   Called by cap enforcement to identify redistribution candidates
 * 
 * Error Cases:
 *   - None expected (comparison operations on valid statistics)
 * 
 * @business_rule
 *)
let is_over_threshold config stats =
  let daily_cap = calculate_daily_cap config in
  let threshold = int_of_float (float_of_int daily_cap *. config.overage_threshold) in
  stats.total_count > threshold

(** 
 * [is_ed_over_soft_limit]: Checks if effective date emails exceed soft limit
 * 
 * Purpose:
 *   Determines if effective date anniversary emails on a day exceed the soft
 *   limit requiring targeted smoothing to prevent clustering.
 * 
 * Parameters:
 *   - config: Load balancing configuration with ED soft limit
 *   - stats: Daily statistics to evaluate
 * 
 * Returns:
 *   Boolean indicating if ED count exceeds soft limit threshold
 * 
 * Business Logic:
 *   - Compares ED count against calculated soft limit
 *   - Identifies days needing effective date smoothing
 *   - Triggers targeted redistribution for anniversary clusters
 *   - Maintains balanced distribution of anniversary emails
 * 
 * Usage Example:
 *   Called by smooth_effective_dates to identify smoothing candidates
 * 
 * Error Cases:
 *   - None expected (comparison operations on valid statistics)
 * 
 * @business_rule
 *)
let is_ed_over_soft_limit config stats =
  let ed_limit = calculate_ed_soft_limit config in
  stats.ed_count > ed_limit

(** 
 * [apply_jitter]: Applies deterministic jitter to redistribute email schedules
 * 
 * Purpose:
 *   Calculates jittered date for email schedule using contact ID and email type
 *   as seed to ensure consistent but distributed scheduling across window.
 * 
 * Parameters:
 *   - original_date: Original scheduled date for the email
 *   - contact_id: Contact identifier for deterministic jitter calculation
 *   - email_type: Email type for jitter algorithm differentiation
 *   - window_days: Size of redistribution window in days
 * 
 * Returns:
 *   Result containing new jittered date or load balancing error
 * 
 * Business Logic:
 *   - Uses deterministic algorithm for consistent redistribution
 *   - Leverages contact ID as seed for even distribution
 *   - Maintains email type context for algorithm tuning
 *   - Provides controlled randomization within specified window
 * 
 * Usage Example:
 *   Called by smoothing algorithms to redistribute clustered emails
 * 
 * Error Cases:
 *   - LoadBalancingError: Jitter calculation or date arithmetic failures
 * 
 * @performance @business_rule
 *)
let apply_jitter ~original_date ~contact_id ~email_type ~window_days =
  try
    let (year, _, _) = original_date in
    let jitter = calculate_jitter 
      ~contact_id 
      ~event_type:(string_of_email_type email_type)
      ~year 
      ~window_days in
    let new_date = add_days original_date jitter in
    Ok new_date
  with e ->
    Error (LoadBalancingError (Printf.sprintf "Jitter calculation failed: %s" (Printexc.to_string e)))

(** 
 * [smooth_effective_dates]: Redistributes clustered effective date anniversary emails
 * 
 * Purpose:
 *   Applies targeted smoothing algorithm to effective date emails that exceed
 *   soft limits, redistributing them across nearby dates to prevent clustering.
 * 
 * Parameters:
 *   - schedules: List of all email schedules to process
 *   - config: Load balancing configuration with smoothing parameters
 * 
 * Returns:
 *   List of schedules with effective date emails redistributed
 * 
 * Business Logic:
 *   - Separates effective date emails from other types for targeted processing
 *   - Identifies days exceeding ED soft limits requiring smoothing
 *   - Applies jitter within configured window to redistribute clusters
 *   - Ensures redistributed dates are not in the past
 *   - Recombines smoothed schedules with unmodified schedules
 * 
 * Usage Example:
 *   Called by distribute_schedules as first step in load balancing pipeline
 * 
 * Error Cases:
 *   - Jitter application failures handled gracefully by keeping original dates
 * 
 * @business_rule @performance
 *)
let smooth_effective_dates schedules config =
  let ed_schedules = List.filter (fun s ->
    match s.email_type with
    | Anniversary EffectiveDate -> true
    | _ -> false
  ) schedules in
  
  let other_schedules = List.filter (fun s ->
    match s.email_type with
    | Anniversary EffectiveDate -> false
    | _ -> true
  ) schedules in
  
  let daily_stats = group_by_date ed_schedules in
  let _dates_to_smooth = List.filter (is_ed_over_soft_limit config) daily_stats in
  
  let smoothed_schedules = List.fold_left (fun acc stats ->
    if is_ed_over_soft_limit config stats then
      let date_schedules = List.filter (fun s -> 
        compare_date s.scheduled_date stats.date = 0
      ) ed_schedules in
      
      let window_days = config.ed_smoothing_window_days in
      let redistributed = List.map (fun schedule ->
        match apply_jitter 
          ~original_date:schedule.scheduled_date
          ~contact_id:schedule.contact_id
          ~email_type:schedule.email_type
          ~window_days with
        | Ok new_date -> 
            let today = current_date () in
            if compare_date new_date today >= 0 then
              { schedule with scheduled_date = new_date }
            else
              schedule
        | Error _ -> schedule
      ) date_schedules in
      redistributed @ acc
    else
      let date_schedules = List.filter (fun s -> 
        compare_date s.scheduled_date stats.date = 0
      ) ed_schedules in
      date_schedules @ acc
  ) [] daily_stats in
  
  smoothed_schedules @ other_schedules

(** 
 * [enforce_daily_caps]: Enforces hard daily limits by redistributing excess emails
 * 
 * Purpose:
 *   Core cap enforcement algorithm that identifies overloaded days and redistributes
 *   emails to maintain daily sending limits while preserving priority ordering.
 * 
 * Parameters:
 *   - schedules: List of email schedules to process
 *   - config: Load balancing configuration with daily caps and thresholds
 * 
 * Returns:
 *   List of schedules with excess emails redistributed to maintain caps
 * 
 * Business Logic:
 *   - Groups schedules by date and sorts chronologically
 *   - Identifies days exceeding overage threshold
 *   - Sorts schedules by priority to preserve important emails
 *   - Moves excess schedules to next available day or catch-up distribution
 *   - Maintains email priority ordering during redistribution
 * 
 * Usage Example:
 *   Called by distribute_schedules after effective date smoothing
 * 
 * Error Cases:
 *   - None expected (uses deterministic redistribution algorithms)
 * 
 * @business_rule @performance
 *)
let rec enforce_daily_caps schedules config =
  let day_stats_list = group_by_date schedules in
  
  let sorted_stats = List.sort (fun (a : daily_stats) (b : daily_stats) -> 
    compare_date a.date b.date
  ) day_stats_list in
  
  let rec process_days acc remaining_stats =
    match remaining_stats with
    | [] -> acc
    | stats :: rest ->
        if is_over_threshold config stats then
          let daily_cap = calculate_daily_cap config in
          let date_schedules = List.filter (fun s ->
            compare_date s.scheduled_date stats.date = 0
          ) schedules in
          
          let sorted_schedules = List.sort (fun (a : email_schedule) (b : email_schedule) ->
            compare a.priority b.priority
          ) date_schedules in
          
          let (keep_schedules, move_schedules) = 
            let rec split kept moved remaining count =
              if count >= daily_cap || remaining = [] then
                (List.rev kept, List.rev moved @ remaining)
              else
                match remaining with
                | schedule :: rest ->
                    split (schedule :: kept) moved rest (count + 1)
                | [] -> (List.rev kept, List.rev moved)
            in
            split [] [] sorted_schedules 0
          in
          
          let moved_schedules = match rest with
            | next_stats :: _ ->
                List.map (fun schedule ->
                  { schedule with scheduled_date = next_stats.date }
                ) move_schedules
            | [] ->
                distribute_catch_up move_schedules config
          in
          
          process_days (keep_schedules @ moved_schedules @ acc) rest
        else
          let date_schedules = List.filter (fun s ->
            compare_date s.scheduled_date stats.date = 0
          ) schedules in
          process_days (date_schedules @ acc) rest
  in
  
  process_days [] sorted_stats

(** 
 * [distribute_catch_up]: Distributes overflow emails across catch-up period
 * 
 * Purpose:
 *   Handles emails that cannot be accommodated in normal scheduling by spreading
 *   them across a configured catch-up period to ensure delivery.
 * 
 * Parameters:
 *   - schedules: List of overflow email schedules to redistribute
 *   - config: Load balancing configuration with catch-up spread parameters
 * 
 * Returns:
 *   List of schedules with dates spread across catch-up period
 * 
 * Business Logic:
 *   - Uses modulo operation for even distribution across catch-up days
 *   - Starts from tomorrow to avoid same-day delivery issues
 *   - Ensures all overflow emails eventually get scheduled
 *   - Provides predictable distribution pattern for capacity planning
 * 
 * Usage Example:
 *   Called by enforce_daily_caps when no future capacity available
 * 
 * Error Cases:
 *   - None expected (deterministic date calculation)
 * 
 * @business_rule
 *)
and distribute_catch_up schedules config =
  let spread_days = config.catch_up_spread_days in
  let today = current_date () in
  
  List.mapi (fun index schedule ->
    let day_offset = (index mod spread_days) + 1 in
    let new_date = add_days today day_offset in
    { schedule with scheduled_date = new_date }
  ) schedules

(** 
 * [distribute_schedules]: Main load balancing orchestration function
 * 
 * Purpose:
 *   Coordinates complete load balancing pipeline applying smoothing algorithms
 *   and cap enforcement to create balanced email distribution.
 * 
 * Parameters:
 *   - schedules: List of all email schedules to balance
 *   - config: Load balancing configuration with all parameters
 * 
 * Returns:
 *   Result containing balanced schedules or load balancing error
 * 
 * Business Logic:
 *   - Applies effective date smoothing first for targeted redistribution
 *   - Follows with daily cap enforcement for hard limit compliance
 *   - Uses pipeline approach for layered load balancing
 *   - Provides comprehensive error handling for all balancing operations
 * 
 * Usage Example:
 *   Called by schedule_emails_streaming after all schedules generated
 * 
 * Error Cases:
 *   - LoadBalancingError: Any failures in smoothing or cap enforcement
 * 
 * @integration_point @performance @business_rule
 *)
let distribute_schedules schedules config =
  try
    let result = schedules
      |> (fun s -> smooth_effective_dates s config)
      |> (fun s -> enforce_daily_caps s config) in
    Ok result
  with e ->
    Error (LoadBalancingError (Printf.sprintf "Load balancing failed: %s" (Printexc.to_string e)))

(** 
 * [analyze_distribution]: Analyzes email distribution for reporting and monitoring
 * 
 * Purpose:
 *   Computes comprehensive statistics on email distribution across dates for
 *   capacity planning, performance monitoring, and load balancing assessment.
 * 
 * Parameters:
 *   - schedules: List of email schedules to analyze
 * 
 * Returns:
 *   distribution_analysis record with detailed statistics
 * 
 * Business Logic:
 *   - Groups schedules by date for daily analysis
 *   - Calculates total volume and time span metrics
 *   - Computes distribution statistics (average, min, max, variance)
 *   - Provides insights for capacity planning and system optimization
 * 
 * Usage Example:
 *   Called by get_scheduling_summary for comprehensive reporting
 * 
 * Error Cases:
 *   - Handles empty schedule lists gracefully with zero values
 * 
 * @integration_point @performance
 *)
let analyze_distribution schedules =
  let daily_stats = group_by_date schedules in
  let total_emails = List.length schedules in
  let total_days = List.length daily_stats in
  let avg_per_day = if total_days > 0 then 
    float_of_int total_emails /. float_of_int total_days 
  else 0.0 in
  
  let max_day = List.fold_left (fun acc stats ->
    max acc stats.total_count
  ) 0 daily_stats in
  
  let min_day = if daily_stats = [] then 0 else
    List.fold_left (fun acc stats ->
      min acc stats.total_count
    ) max_int daily_stats in
  
  {
    total_emails;
    total_days;
    avg_per_day;
    max_day;
    min_day;
    distribution_variance = max_day - min_day;
  }

(** 
 * [validate_config]: Validates load balancing configuration parameters
 * 
 * Purpose:
 *   Ensures all load balancing configuration values are within valid ranges
 *   and logically consistent to prevent runtime errors and invalid behavior.
 * 
 * Parameters:
 *   - config: Load balancing configuration to validate
 * 
 * Returns:
 *   Result indicating validation success or configuration errors
 * 
 * Business Logic:
 *   - Validates percentage cap is between 0 and 1
 *   - Ensures all day limits and windows are positive
 *   - Checks overage threshold is greater than 1.0
 *   - Accumulates all validation errors for comprehensive feedback
 * 
 * Usage Example:
 *   Called before using configuration in load balancing operations
 * 
 * Error Cases:
 *   - ConfigurationError: Invalid parameter values with detailed descriptions
 * 
 * @integration_point
 *)
let validate_config config =
  let errors = [] in
  let errors = if config.daily_send_percentage_cap <= 0.0 || config.daily_send_percentage_cap > 1.0 then
    "daily_send_percentage_cap must be between 0 and 1" :: errors
  else errors in
  let errors = if config.ed_daily_soft_limit <= 0 then
    "ed_daily_soft_limit must be positive" :: errors
  else errors in
  let errors = if config.ed_smoothing_window_days <= 0 then
    "ed_smoothing_window_days must be positive" :: errors
  else errors in
  let errors = if config.catch_up_spread_days <= 0 then
    "catch_up_spread_days must be positive" :: errors
  else errors in
  let errors = if config.overage_threshold <= 1.0 then
    "overage_threshold must be greater than 1.0" :: errors
  else errors in
  match errors with
  | [] -> Ok ()
  | _ -> Error (ConfigurationError (String.concat "; " errors))

(** 
 * [default_config]: Creates default load balancing configuration
 * 
 * Purpose:
 *   Provides sensible default configuration values for load balancing based on
 *   total contact count and proven operational parameters.
 * 
 * Parameters:
 *   - total_contacts: Total number of contacts for capacity calculations
 * 
 * Returns:
 *   load_balancing_config record with default values
 * 
 * Business Logic:
 *   - Sets 7% daily sending cap for sustainable volume
 *   - Limits effective date emails to 15 per day
 *   - Uses 5-day smoothing window for anniversary redistribution
 *   - Provides 7-day catch-up period for overflow emails
 *   - Sets 20% overage threshold before redistribution
 * 
 * Usage Example:
 *   Called by create_context to initialize load balancing configuration
 * 
 * Error Cases:
 *   - None expected (uses validated default values)
 * 
 * @integration_point
 *)
let default_config total_contacts = {
  daily_send_percentage_cap = 0.07;
  ed_daily_soft_limit = 15;
  ed_smoothing_window_days = 5;
  catch_up_spread_days = 7;
  overage_threshold = 1.2;
  total_contacts;
  batch_size = 10000;
}