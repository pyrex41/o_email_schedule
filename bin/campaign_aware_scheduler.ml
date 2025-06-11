open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Campaign-aware scheduler that properly loads contacts with effective date filtering *)

let get_contacts_with_effective_date_filter (org_config : enhanced_organization_config) =
  Printf.printf "📊 Loading contacts with effective date filtering...\n";
  
  (* Calculate minimum effective date based on organization config *)
  let today = current_date () in
  let months_back = org_config.effective_date_first_email_months in
  let (year, month, day) = today in
  let target_year = if month <= months_back then year - 1 else year in
  let target_month = if month <= months_back then month + 12 - months_back else month - months_back in
  let min_effective_date = (target_year, target_month, day) in
  let min_date_str = string_of_date min_effective_date in
  
  Printf.printf "   Filtering contacts with effective_date >= %s (%d months back)\n" 
    min_date_str months_back;
  
  (* Custom query that handles both anniversary and campaign needs *)
  let query = Printf.sprintf {|
    SELECT DISTINCT c.id, c.email, 
           COALESCE(c.zip_code, '') as zip_code, 
           COALESCE(c.state, '') as state, 
           COALESCE(c.birth_date, '') as birth_date, 
           COALESCE(c.effective_date, '') as effective_date,
           COALESCE(c.current_carrier, '') as carrier,
           0 as failed_underwriting
    FROM contacts c
    WHERE c.email IS NOT NULL AND c.email != '' 
    AND (
      -- Include contacts with effective dates after minimum threshold
      (c.effective_date IS NOT NULL AND c.effective_date != '' AND c.effective_date >= '%s')
      OR
      -- Include contacts enrolled in active campaigns (regardless of effective date)
      c.id IN (
        SELECT cc.contact_id 
        FROM contact_campaigns cc
        JOIN campaign_instances ci ON cc.campaign_instance_id = ci.id
        WHERE cc.status = 'active'
        AND date('now') BETWEEN ci.active_start_date AND ci.active_end_date
      )
      OR 
      -- Include contacts with upcoming anniversaries (birthdays)
      (c.birth_date IS NOT NULL AND c.birth_date != '')
    )
    ORDER BY c.id
  |} min_date_str in
  
  match execute_sql_safe query with
  | Error err -> 
      Printf.printf "   ❌ Query failed: %s\n" (string_of_db_error err);
      Error err
  | Ok rows ->
      let contacts = List.filter_map (fun row ->
        match row with
        | [id_str; email; zip_code; state; birth_date; effective_date; carrier; failed_underwriting_str] ->
            (try
              let id = int_of_string id_str in
              let failed_underwriting = (int_of_string failed_underwriting_str) <> 0 in
              
              (* Parse optional dates *)
              let birthday = if birth_date = "" || birth_date = "N/A" then None 
                           else (try Some (parse_date birth_date) with _ -> None) in
              let eff_date = if effective_date = "" || effective_date = "N/A" then None 
                           else (try Some (parse_date effective_date) with _ -> None) in
              let zip = if zip_code = "" then None else Some zip_code in
              let contact_state = if state = "" then None else (try Some (state_of_string state) with _ -> None) in
              let contact_carrier = if carrier = "" then None else Some carrier in
              
              Some {
                id;
                email;
                zip_code = zip;
                state = contact_state;
                birthday;
                effective_date = eff_date;
                carrier = contact_carrier;
                failed_underwriting;
              }
            with _ -> None)
        | _ -> None
      ) rows in
      Printf.printf "   ✅ Found %d eligible contacts\n" (List.length contacts);
      Ok contacts

let run_campaign_aware_scheduler db_path =
  Printf.printf "=== Campaign-Aware Scheduler with Effective Date Filtering ===\n\n";
  
  (* Set database path *)
  set_db_path db_path;
  
  (* Initialize database *)
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      exit 1
  | Ok () ->
      Printf.printf "✅ Database connected successfully\n";
      
      (* Load ZIP data *)
      let _ = Scheduler.Zip_data.ensure_loaded () in
      Printf.printf "✅ ZIP data loaded\n";
      
      (* Get organization configuration to determine effective date threshold *)
      Printf.printf "📋 Loading organization configuration...\n";
      let config = Scheduler.Config.default in
      let org_config = config.organization in
      Printf.printf "   Organization: %s\n" org_config.name;
      Printf.printf "   Effective date first email months: %d\n" org_config.effective_date_first_email_months;
      
      (* Show active campaigns *)
      Printf.printf "\n🎯 Checking active campaigns...\n";
      (match get_active_campaign_instances () with
       | Error err ->
           Printf.printf "   ❌ Failed to get campaigns: %s\n" (string_of_db_error err);
       | Ok campaigns ->
           Printf.printf "   Found %d active campaign instances:\n" (List.length campaigns);
           List.iter (fun campaign ->
             Printf.printf "     📅 %s (%s)\n" campaign.instance_name campaign.campaign_type
           ) campaigns);
      
      (* Load contacts with proper filtering *)
      match get_contacts_with_effective_date_filter org_config with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok contacts ->
          let contact_count = List.length contacts in
          Printf.printf "\n⚡ Running comprehensive scheduler with %d contacts...\n" contact_count;
          
          if contact_count = 0 then (
            Printf.printf "✅ No eligible contacts found\n";
            exit 0
          );
          
          (* Run the comprehensive scheduling *)
          match schedule_emails_streaming ~contacts ~config ~total_contacts:contact_count with
          | Ok result ->
              Printf.printf "✅ Scheduling completed successfully!\n\n";
              
              (* Show summary *)
              Printf.printf "%s\n\n" (get_scheduling_summary result);
              
              (* Generate run ID and save to database *)
              let scheduler_run_id = 
                let now = Unix.time () in
                let tm = Unix.localtime now in
                Printf.sprintf "campaign_aware_%04d%02d%02d_%02d%02d%02d" 
                  (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday 
                  tm.tm_hour tm.tm_min tm.tm_sec
              in
              
              (* Apply load balancing *)
              Printf.printf "⚖️  Applying load balancing...\n";
              let lb_config = Scheduler.Load_balancer.default_config contact_count in
              (match Scheduler.Load_balancer.distribute_schedules result.schedules lb_config with
               | Ok balanced_schedules ->
                   Printf.printf "   Load balancing complete\n";
                   
                   (* Save to database *)
                   Printf.printf "💾 Saving schedules to database...\n";
                   (match update_email_schedules ~use_smart_update:true balanced_schedules scheduler_run_id with
                    | Ok changes ->
                        Printf.printf "   Successfully saved %d schedules\n" changes;
                        
                        (* Show detailed breakdown by email type *)
                        Printf.printf "\n📈 Email Type Breakdown:\n";
                        let type_counts = Hashtbl.create 10 in
                        List.iter (fun schedule ->
                          let type_str = string_of_email_type schedule.email_type in
                          let current_count = match Hashtbl.find_opt type_counts type_str with
                            | Some count -> count
                            | None -> 0
                          in
                          Hashtbl.replace type_counts type_str (current_count + 1)
                        ) balanced_schedules;
                        
                        Hashtbl.iter (fun email_type count ->
                          let category = match email_type with
                            | s when String.contains s '_' && not (s = "effective_date" || s = "post_window") -> "Campaign"
                            | _ -> "Anniversary"
                          in
                          Printf.printf "  [%s] %s: %d emails\n" category email_type count
                        ) type_counts;
                        
                        Printf.printf "\n✅ Campaign-aware scheduling complete!\n";
                        
                    | Error err ->
                        Printf.printf "❌ Failed to save schedules: %s\n" (string_of_db_error err))
               | Error err ->
                   Printf.printf "❌ Load balancing failed: %s\n" (string_of_error err))
          | Error error ->
              Printf.printf "❌ Scheduling failed: %s\n" (string_of_error error)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    Printf.printf "This scheduler includes:\n";
    Printf.printf "- Effective date filtering based on organization config\n";
    Printf.printf "- Campaign enrollee inclusion\n";
    Printf.printf "- Anniversary email processing\n";
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  run_campaign_aware_scheduler db_path

let () = main ()