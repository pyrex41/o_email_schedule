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

let calculate_anniversary_emails context contact =
  let today = current_date () in
  let schedules = ref [] in
  
  let send_time = schedule_time_ct context.config.send_time_hour context.config.send_time_minute in
  
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
  
  let today_month = today.month in
  if today_month = 9 then (
    let aep_date = make_date today.year 9 15 in
    if not (should_skip_email contact (Anniversary AEP) aep_date) then (
      let schedule = {
        contact_id = contact.id;
        email_type = Anniversary AEP;
        scheduled_date = aep_date;
        scheduled_time = send_time;
        status = PreScheduled;
        priority = priority_of_email_type (Anniversary AEP);
        template_id = Some "aep_template";
        campaign_instance_id = None;
        scheduler_run_id = context.run_id;
      } in
      schedules := schedule :: !schedules
    )
  );
  
  !schedules

let calculate_post_window_emails context contact =
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
    if not (Contact.is_valid_for_scheduling contact) then
      Error (InvalidContactData { 
        contact_id = contact.id; 
        reason = "Contact failed validation" 
      })
    else
      let anniversary_schedules = calculate_anniversary_emails context contact in
      let post_window_schedules = calculate_post_window_emails context contact in
      let all_schedules = anniversary_schedules @ post_window_schedules in
      Ok all_schedules
  with e ->
    Error (UnexpectedError e)

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
      errors = [];
    } in
    
    match process_chunks contacts initial_result with
    | Ok raw_result ->
        begin match distribute_schedules raw_result.schedules context.load_balancing_config with
        | Ok balanced_schedules ->
            Ok { raw_result with schedules = balanced_schedules }
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