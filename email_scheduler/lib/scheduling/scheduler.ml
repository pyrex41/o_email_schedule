(* Main email scheduler with streaming architecture *)

open Lwt.Syntax
open Domain.Types
open Scheduling.Date_calc
open Scheduling.Load_balancer

(* Scheduler context *)
type scheduler_context = {
  config: scheduler_config;
  run_id: string;
  start_time: Ptime.t;
  total_contacts: int;
}

(* Batch processing results *)
type batch_result = {
  contacts_processed: int;
  emails_scheduled: int;
  emails_skipped: int;
  errors: scheduler_error list;
}

let empty_batch_result = {
  contacts_processed = 0;
  emails_scheduled = 0;
  emails_skipped = 0;
  errors = [];
}

(* Combine batch results *)
let combine_batch_results r1 r2 = {
  contacts_processed = r1.contacts_processed + r2.contacts_processed;
  emails_scheduled = r1.emails_scheduled + r2.emails_scheduled;
  emails_skipped = r1.emails_skipped + r2.emails_skipped;
  errors = r1.errors @ r2.errors;
}

(* Generate unique scheduler run ID *)
let generate_run_id () =
  let now = Ptime_clock.now () in
  match now with
  | Some time ->
      let timestamp = Ptime.to_rfc3339 time in
      Printf.sprintf "sched_%s_%d" timestamp (Random.int 10000)
  | None ->
      Printf.sprintf "sched_unknown_%d" (Random.int 10000)

(* Calculate schedules for a single contact *)
let calculate_contact_schedules ~context ~contact =
  let today = Ptime.to_date context.start_time in
  let schedules = ref [] in
  let errors = ref [] in
  
  (* Helper to add schedule *)
  let add_schedule email_type priority =
    match calculate_send_date ~today ~contact ~email_type ~config:context.config with
    | Ok send_date ->
        let schedule = {
          contact_id = contact.id;
          email_type;
          scheduled_date = send_date;
          scheduled_time = context.config.send_time;
          status = PreScheduled;
          priority;
          template_id = None;
          campaign_instance_id = None;
          scheduler_run_id = context.run_id;
          skip_reason = None;
          created_at = context.start_time;
          updated_at = context.start_time;
        } in
        
        (* Check exclusion rules *)
        if contact_in_exclusion_window ~contact ~email_type ~check_date:send_date then
          let skip_reason = "Excluded by state rules" in
          let skipped_schedule = { 
            schedule with 
            status = Skipped skip_reason;
            skip_reason = Some skip_reason;
          } in
          schedules := skipped_schedule :: !schedules
        else
          schedules := schedule :: !schedules
    | Error reason ->
        errors := (InvalidContactData { contact_id = contact.id; reason }) :: !errors
  in
  
  (* Schedule anniversary-based emails *)
  if Option.is_some contact.birthday then
    add_schedule (Anniversary Birthday) 5;
  
  if Option.is_some contact.effective_date then
    add_schedule (Anniversary EffectiveDate) 3;
  
  (* Always schedule AEP *)
  add_schedule (Anniversary AEP) 7;
  
  (* Check if we need post-window emails *)
  let has_skipped_emails = List.exists (fun s ->
    match s.status with Skipped _ -> true | _ -> false
  ) !schedules in
  
  if has_skipped_emails then
    add_schedule (Anniversary PostWindow) 8;
  
  (!schedules, !errors)

(* Process a batch of contacts *)
let process_contact_batch ~context ~contacts =
  let* () = Lwt.return_unit in
  let schedules = ref [] in
  let total_errors = ref [] in
  let processed_count = ref 0 in
  
  (* Process each contact *)
  let* () = Lwt_list.iter_s (fun contact ->
    incr processed_count;
    let (contact_schedules, contact_errors) = 
      calculate_contact_schedules ~context ~contact in
    schedules := contact_schedules @ !schedules;
    total_errors := contact_errors @ !total_errors;
    
    (* Log progress periodically *)
    if !processed_count mod 1000 = 0 then
      Logs.info (fun m -> m "Processed %d contacts" !processed_count);
    
    Lwt.return_unit
  ) contacts in
  
  let scheduled_count = List.length (List.filter (fun s ->
    match s.status with PreScheduled -> true | _ -> false
  ) !schedules) in
  
  let skipped_count = List.length (List.filter (fun s ->
    match s.status with Skipped _ -> true | _ -> false
  ) !schedules) in
  
  let result = {
    contacts_processed = !processed_count;
    emails_scheduled = scheduled_count;
    emails_skipped = skipped_count;
    errors = !total_errors;
  } in
  
  Lwt.return (!schedules, result)

(* Main streaming scheduler function *)
let schedule_emails_streaming ~db ~config =
  let run_id = generate_run_id () in
  let* start_time = match get_current_ct () with
    | Ok time -> Lwt.return time
    | Error _ -> Lwt.return (Ptime.epoch)
  in
  
  Logs.info (fun m -> m "Starting email scheduling run: %s" run_id);
  
  (* Get total contact count for load balancing *)
  let* total_contacts = 
    (* This would be implemented in the database module *)
    Lwt.return 100000  (* placeholder *)
  in
  
  let context = {
    config;
    run_id;
    start_time;
    total_contacts;
  } in
  
  let load_balance_config = Load_balancer.default_config total_contacts in
  
  (* Process contacts in streaming fashion *)
  let chunk_size = config.batch_size in
  let all_schedules = ref [] in
  let cumulative_result = ref empty_batch_result in
  
  let rec process_chunk offset =
    Logs.info (fun m -> m "Processing chunk starting at offset %d" offset);
    
    (* Fetch contacts batch - this would be implemented in database module *)
    let* contacts = 
      (* Database.fetch_contacts_batch ~offset ~limit:chunk_size db *)
      Lwt.return []  (* placeholder *)
    in
    
    match contacts with
    | [] -> 
        Logs.info (fun m -> m "No more contacts to process");
        Lwt.return_unit
    | batch ->
        let* (batch_schedules, batch_result) = 
          process_contact_batch ~context ~contacts:batch in
        
        (* Accumulate results *)
        all_schedules := batch_schedules @ !all_schedules;
        cumulative_result := combine_batch_results !cumulative_result batch_result;
        
        (* Apply load balancing to current batch *)
        let balanced_schedules = 
          Load_balancer.distribute_schedules batch_schedules load_balance_config in
        
        (* Insert schedules to database *)
        let* () = 
          (* Database.insert_schedules db balanced_schedules *)
          Lwt.return_unit  (* placeholder *)
        in
        
        (* Log progress *)
        Logs.info (fun m -> m 
          "Batch complete: %d contacts, %d emails scheduled, %d skipped" 
          batch_result.contacts_processed
          batch_result.emails_scheduled
          batch_result.emails_skipped);
        
        (* Continue with next chunk *)
        process_chunk (offset + chunk_size)
  in
  
  let* () = process_chunk 0 in
  
  (* Apply global load balancing *)
  let final_schedules = 
    Load_balancer.distribute_schedules !all_schedules load_balance_config in
  
  (* Generate distribution analysis *)
  let analysis = Load_balancer.analyze_distribution final_schedules in
  
  Logs.info (fun m -> m 
    "Scheduling complete: %d contacts processed, %d emails scheduled, %d skipped, %d errors"
    !cumulative_result.contacts_processed
    !cumulative_result.emails_scheduled
    !cumulative_result.emails_skipped
    (List.length !cumulative_result.errors));
  
  Logs.info (fun m -> m
    "Load balancing: avg %.1f emails/day, max %d, min %d, variance %d"
    analysis.avg_per_day
    analysis.max_day
    analysis.min_day
    analysis.distribution_variance);
  
  Lwt.return (!cumulative_result, analysis)

(* Error handling utilities *)
let handle_scheduler_error = function
  | DatabaseError msg -> 
      Logs.err (fun m -> m "Database error: %s" msg);
      (* Implement retry logic *)
      Lwt.return_unit
  | InvalidContactData { contact_id; reason } ->
      Logs.warn (fun m -> m "Skipping contact %d: %s" contact_id reason);
      (* Continue processing *)
      Lwt.return_unit
  | ConfigurationError msg ->
      Logs.err (fun m -> m "Configuration error: %s" msg);
      (* Halt processing *)
      Lwt.fail (Failure ("Configuration error: " ^ msg))
  | UnexpectedError exn ->
      Logs.err (fun m -> m "Unexpected error: %s" (Printexc.to_string exn));
      (* Log and re-raise *)
      Lwt.fail exn

(* Configuration validation *)
let validate_scheduler_config config =
  let errors = [] in
  let errors = if config.batch_size <= 0 then
    "batch_size must be positive" :: errors
  else errors in
  let errors = if config.birthday_days_before < 0 then
    "birthday_days_before must be non-negative" :: errors
  else errors in
  let errors = if config.effective_date_days_before < 0 then
    "effective_date_days_before must be non-negative" :: errors
  else errors in
  let errors = if config.followup_delay_days < 0 then
    "followup_delay_days must be non-negative" :: errors
  else errors in
  match errors with
  | [] -> Ok ()
  | _ -> Error (String.concat "; " errors)

(* Default configuration *)
let default_config = {
  timezone = "America/Chicago";
  batch_size = 10000;
  max_memory_mb = 1024;
  birthday_days_before = 14;
  effective_date_days_before = 30;
  pre_window_buffer_days = 60;
  followup_delay_days = 2;
  daily_cap_percentage = 0.07;
  ed_soft_limit = 15;
  smoothing_window_days = 5;
  send_time = Ptime.of_time (8, 30, 0) |> Option.get;
}

(* Main entry point *)
let run_scheduler ?(config = default_config) ~db () =
  match validate_scheduler_config config with
  | Error msg ->
      Logs.err (fun m -> m "Invalid configuration: %s" msg);
      Lwt.return (Error (ConfigurationError msg))
  | Ok () ->
      Lwt.catch
        (fun () ->
           let* (result, analysis) = schedule_emails_streaming ~db ~config in
           Lwt.return (Ok (result, analysis)))
        (fun exn ->
           let* () = handle_scheduler_error (UnexpectedError exn) in
           Lwt.return (Error (UnexpectedError exn)))