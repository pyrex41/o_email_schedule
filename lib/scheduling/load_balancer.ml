open Date_time
open Types
open Database_native
open Simple_date
open Date_calc

module DailyStats = struct
  let empty date = {
    date;
    total_count = 0;
    ed_count = 0;
    campaign_count = 0;
    anniversary_count = 0;
    over_threshold = false;
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

let calculate_daily_cap config =
  int_of_float (float_of_int config.total_contacts *. config.daily_send_percentage_cap)

let calculate_ed_soft_limit config =
  let org_cap = calculate_daily_cap config in
  min config.ed_daily_soft_limit (int_of_float (float_of_int org_cap *. 0.3))

let is_over_threshold config stats =
  let daily_cap = calculate_daily_cap config in
  let threshold = int_of_float (float_of_int daily_cap *. config.overage_threshold) in
  stats.total_count > threshold

let is_ed_over_soft_limit config stats =
  let ed_limit = calculate_ed_soft_limit config in
  stats.ed_count > ed_limit

let apply_jitter ~original_date ~contact_id ~email_type ~window_days =
  try
    let jitter = calculate_jitter 
      ~contact_id 
      ~event_type:(string_of_email_type email_type)
      ~year:original_date.year 
      ~window_days in
    let new_date = add_days original_date jitter in
    Ok new_date
  with e ->
    Error (LoadBalancingError (Printf.sprintf "Jitter calculation failed: %s" (Printexc.to_string e)))

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

and distribute_catch_up schedules config =
  let spread_days = config.catch_up_spread_days in
  let today = current_date () in
  
  List.mapi (fun index schedule ->
    let day_offset = (index mod spread_days) + 1 in
    let new_date = add_days today day_offset in
    { schedule with scheduled_date = new_date }
  ) schedules

let distribute_schedules schedules config =
  try
    let result = schedules
      |> (fun s -> smooth_effective_dates s config)
      |> (fun s -> enforce_daily_caps s config) in
    Ok result
  with e ->
    Error (LoadBalancingError (Printf.sprintf "Load balancing failed: %s" (Printexc.to_string e)))

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

let default_config total_contacts = {
  daily_send_percentage_cap = 0.07;
  ed_daily_soft_limit = 15;
  ed_smoothing_window_days = 5;
  catch_up_spread_days = 7;
  overage_threshold = 1.2;
  total_contacts;
}