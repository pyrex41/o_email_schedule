(* Load balancing and email smoothing algorithms *)

open Domain.Types
open Scheduling.Date_calc

(* Load balancing configuration *)
type balancing_config = {
  daily_send_percentage_cap: float;
  ed_daily_soft_limit: int;
  ed_smoothing_window_days: int;
  catch_up_spread_days: int;
  overage_threshold: float;
  total_contacts: int;
}

(* Distribution analysis result *)
type distribution_analysis = {
  total_emails: int;
  total_days: int;
  avg_per_day: float;
  max_day: int;
  min_day: int;
  distribution_variance: int;
}

(* Daily email statistics *)
module DailyStats = struct
  type t = {
    date: Ptime.date;
    total_count: int;
    ed_count: int;
    campaign_count: int;
    anniversary_count: int;
  }

  let empty date = {
    date;
    total_count = 0;
    ed_count = 0;
    campaign_count = 0;
    anniversary_count = 0;
  }

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

(* Group schedules by date *)
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

(* Calculate daily caps *)
let calculate_daily_cap config =
  int_of_float (float_of_int config.total_contacts *. config.daily_send_percentage_cap)

let calculate_ed_soft_limit config =
  let org_cap = calculate_daily_cap config in
  min config.ed_daily_soft_limit (int_of_float (float_of_int org_cap *. 0.3))

(* Check if a day exceeds thresholds *)
let is_over_threshold config stats =
  let daily_cap = calculate_daily_cap config in
  let threshold = int_of_float (float_of_int daily_cap *. config.overage_threshold) in
  stats.DailyStats.total_count > threshold

let is_ed_over_soft_limit config stats =
  let ed_limit = calculate_ed_soft_limit config in
  stats.DailyStats.ed_count > ed_limit

(* Effective date smoothing algorithm *)
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
  
  (* Group ED emails by date *)
  let daily_stats = group_by_date ed_schedules in
  
  (* Find dates that need smoothing *)
  let dates_to_smooth = List.filter (is_ed_over_soft_limit config) daily_stats in
  
  (* Apply smoothing to over-threshold dates *)
  let smoothed_schedules = List.fold_left (fun acc stats ->
    if is_ed_over_soft_limit config stats then
      (* Get schedules for this date *)
      let date_schedules = List.filter (fun s -> 
        Ptime.compare s.scheduled_date stats.date = 0
      ) ed_schedules in
      
      (* Apply jitter to redistribute *)
      let window_days = config.ed_smoothing_window_days in
      let redistributed = List.map (fun schedule ->
        match apply_jitter 
          ~original_date:schedule.scheduled_date
          ~contact_id:schedule.contact_id
          ~email_type:schedule.email_type
          ~window_days with
        | Ok new_date -> 
            (* Ensure new date is not in the past *)
            (match get_current_ct () with
             | Ok now ->
                 let now_date = Ptime.to_date now in
                 if Ptime.compare new_date now_date >= 0 then
                   { schedule with scheduled_date = new_date }
                 else
                   schedule
             | Error _ -> schedule)
        | Error _ -> schedule
      ) date_schedules in
      redistributed @ acc
    else
      (* Keep schedules for dates under threshold *)
      let date_schedules = List.filter (fun s -> 
        Ptime.compare s.scheduled_date stats.date = 0
      ) ed_schedules in
      date_schedules @ acc
  ) [] daily_stats in
  
  smoothed_schedules @ other_schedules

(* Global daily cap enforcement *)
let enforce_daily_caps schedules config =
  let daily_stats = group_by_date schedules in
  
  (* Sort stats by date to process chronologically *)
  let sorted_stats = List.sort (fun a b -> 
    Ptime.compare a.DailyStats.date b.DailyStats.date
  ) daily_stats in
  
  (* Process each day and move excess to next day *)
  let rec process_days acc remaining_stats =
    match remaining_stats with
    | [] -> acc
    | stats :: rest ->
        if is_over_threshold config stats then
          let daily_cap = calculate_daily_cap config in
          let excess_count = stats.total_count - daily_cap in
          
          (* Get schedules for this date *)
          let date_schedules = List.filter (fun s ->
            Ptime.compare s.scheduled_date stats.date = 0
          ) schedules in
          
          (* Sort by priority (lower number = higher priority) *)
          let sorted_schedules = List.sort (fun a b ->
            compare a.priority b.priority
          ) date_schedules in
          
          (* Keep high priority emails, move low priority to next day *)
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
          
          (* Move excess emails to next day *)
          let moved_schedules = match rest with
            | next_stats :: _ ->
                List.map (fun schedule ->
                  { schedule with scheduled_date = next_stats.date }
                ) move_schedules
            | [] ->
                (* No next day available, apply catch-up distribution *)
                distribute_catch_up move_schedules config
          in
          
          process_days (keep_schedules @ moved_schedules @ acc) rest
        else
          (* Day is under threshold, keep all schedules *)
          let date_schedules = List.filter (fun s ->
            Ptime.compare s.scheduled_date stats.date = 0
          ) schedules in
          process_days (date_schedules @ acc) rest
  in
  
  process_days [] sorted_stats

(* Catch-up email distribution *)
and distribute_catch_up schedules config =
  let spread_days = config.catch_up_spread_days in
  
  match get_current_ct () with
  | Error _ -> schedules
  | Ok now ->
      let today = Ptime.to_date now in
      
      List.mapi (fun index schedule ->
        let day_offset = (index mod spread_days) + 1 in
        match add_days today day_offset with
        | Ok new_date -> { schedule with scheduled_date = new_date }
        | Error _ -> schedule
      ) schedules

(* Main load balancing function *)
let distribute_schedules schedules config =
  schedules
  |> smooth_effective_dates config
  |> enforce_daily_caps config

(* Utility functions for monitoring and reporting *)
let analyze_distribution schedules =
  let daily_stats = group_by_date schedules in
  let total_emails = List.length schedules in
  let total_days = List.length daily_stats in
  let avg_per_day = if total_days > 0 then 
    float_of_int total_emails /. float_of_int total_days 
  else 0.0 in
  
  let max_day = List.fold_left (fun acc stats ->
    max acc stats.DailyStats.total_count
  ) 0 daily_stats in
  
  let min_day = List.fold_left (fun acc stats ->
    min acc stats.DailyStats.total_count
  ) max_int daily_stats in
  
  {
    total_emails;
    total_days;
    avg_per_day;
    max_day;
    min_day;
    distribution_variance = max_day - min_day;
  }

(* Configuration validation *)
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
  | _ -> Error (String.concat "; " errors)

(* Default configuration *)
let default_config total_contacts = {
  daily_send_percentage_cap = 0.07;
  ed_daily_soft_limit = 15;
  ed_smoothing_window_days = 5;
  catch_up_spread_days = 7;
  overage_threshold = 1.2;
  total_contacts;
}