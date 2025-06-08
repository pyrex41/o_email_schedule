open Types
open Simple_date
open Date_calc
open Exclusion_window
open Load_balancer

type scheduling_context = {
  config: Config.t;
  run_id: string;
  start_time: datetime;
  load_balancing_config: load_balancing_config;
}

let generate_run_id () =
  let now = current_datetime () in
  Printf.sprintf "run_%04d%02d%02d_%02d%02d%02d" 
    now.date.year now.date.month now.date.day
    now.time.hour now.time.minute now.time.second

let create_context config total_contacts =
  let run_id = generate_run_id () in
  let start_time = current_datetime () in
  let load_balancing_config = default_config total_contacts in
  { config; run_id; start_time; load_balancing_config }

(* Calculate spread distribution for campaigns with spread_evenly=true *)
let calculate_spread_date contact_id spread_start_date spread_end_date =
  let start_date = spread_start_date in
  let end_date = spread_end_date in
  let total_days = diff_days end_date start_date + 1 in
  
  (* Use contact_id as seed for deterministic distribution *)
  let hash_value = contact_id mod total_days in
  add_days start_date hash_value

(* Check if contact should be excluded based on organization settings and campaign config *)
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

(* Check if contact is valid for scheduling with enhanced logic *)
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

(* Enhanced effective date validation with configurable timing *)
let should_send_effective_date_email config contact effective_date =
  let today = current_date () in
  let months_since_effective = 
    let years_diff = today.year - effective_date.year in
    let months_diff = today.month - effective_date.month in
    years_diff * 12 + months_diff
  in
  
  (* Only send if we've passed the minimum months threshold *)
  months_since_effective >= config.organization.effective_date_first_email_months

let calculate_campaign_emails context campaign_instance campaign_config =
  let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
  let schedules = ref [] in
  
  (* Get contacts for this campaign with targeting *)
  let contacts = 
    if campaign_config.target_all_contacts then
      match Database_native.get_contacts_for_campaign campaign_instance with
      | Ok contacts -> contacts
      | Error _ -> []
    else
      match Database_native.get_contact_campaigns_for_instance campaign_instance.id with
      | Ok contact_campaigns ->
          (* Get the actual contact records for the contact_campaigns *)
          List.filter_map (fun cc ->
            try
              match Database_native.get_all_contacts () with
              | Ok all_contacts -> 
                  List.find_opt (fun c -> c.id = cc.contact_id) all_contacts
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
                  match Database_native.get_contact_campaigns_for_instance campaign_instance.id with
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
          
          let (status, skip_reason) = 
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

(* Enhanced anniversary email calculation with organization config *)
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

(* Enhanced post-window email calculation with organization config *)
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

(* New function to calculate all campaign schedules *)
let calculate_all_campaign_schedules context =
  let all_schedules = ref [] in
  let errors = ref [] in
  
  match Database_native.get_active_campaign_instances () with
  | Error err -> 
      errors := (DatabaseError (Database_native.string_of_db_error err)) :: !errors;
      (!all_schedules, !errors)
  | Ok campaign_instances ->
      List.iter (fun campaign_instance ->
        match Database_native.get_campaign_type_config campaign_instance.campaign_type with
        | Error err ->
            errors := (DatabaseError (Database_native.string_of_db_error err)) :: !errors
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

let schedule_emails_streaming ~contacts ~config ~total_contacts =
  try
    let context = create_context config total_contacts in
    let chunk_size = config.batch_size in
    
    (* First, calculate all campaign schedules *)
    let (campaign_schedules, campaign_errors) = calculate_all_campaign_schedules context in
    
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
        let all_schedules = raw_result.schedules @ campaign_schedules in
        
        (* Count campaign schedules for metrics *)
        let campaign_scheduled = List.fold_left (fun acc schedule ->
          match schedule.status with
          | PreScheduled -> acc + 1
          | _ -> acc
        ) 0 campaign_schedules in
        
        let campaign_skipped = List.fold_left (fun acc schedule ->
          match schedule.status with
          | Skipped _ -> acc + 1
          | _ -> acc
        ) 0 campaign_schedules in
        
        let combined_result = {
          schedules = all_schedules;
          contacts_processed = raw_result.contacts_processed;
          emails_scheduled = raw_result.emails_scheduled + campaign_scheduled;
          emails_skipped = raw_result.emails_skipped + campaign_skipped;
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