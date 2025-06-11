open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types

(* Database-driven comprehensive scheduler that handles both anniversaries AND campaigns *)

let run_comprehensive_scheduler db_path =
  Printf.printf "=== Comprehensive Database-Driven Scheduler ===\n\n";
  Printf.printf "Processing both anniversary emails AND campaign emails from database\n\n";
  
  (* Set database path *)
  set_db_path db_path;
  
  (* Initialize database with proper error handling *)
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      exit 1
  | Ok () ->
      Printf.printf "✅ Database connected successfully\n";
      
      (* Load ZIP data *)
      let _ = Scheduler.Zip_data.ensure_loaded () in
      Printf.printf "✅ ZIP data loaded\n";
      
      (* Use same approach as high-performance scheduler - get contacts in scheduling window *)
      Printf.printf "📊 Loading contacts from database (scheduling window approach)...\n";
      let lookahead_days = 365 in  (* Look ahead 1 year to get everything *)
      let lookback_days = 30 in    (* Look back 30 days *)
      match get_contacts_in_scheduling_window lookahead_days lookback_days with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok contacts ->
          let contact_count = List.length contacts in
          Printf.printf "   Found %d contacts in database\n" contact_count;
          
          if contact_count = 0 then (
            Printf.printf "✅ No contacts found - nothing to schedule\n";
            exit 0
          );
          
          (* Get organization configuration *)
          let config = Scheduler.Config.default in
          
          (* Use the comprehensive scheduling function that handles BOTH anniversaries AND campaigns *)
          Printf.printf "⚡ Running comprehensive scheduler (anniversaries + campaigns)...\n";
          
          match schedule_emails_streaming ~contacts ~config ~total_contacts:contact_count with
          | Ok result ->
              Printf.printf "✅ Comprehensive scheduling completed successfully!\n\n";
              
              (* Show detailed results *)
              Printf.printf "%s\n\n" (get_scheduling_summary result);
              
              (* Generate unique run ID for database insertion *)
              let scheduler_run_id = 
                let now = Unix.time () in
                let tm = Unix.localtime now in
                Printf.sprintf "comprehensive_%04d%02d%02d_%02d%02d%02d" 
                  (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday 
                  tm.tm_hour tm.tm_min tm.tm_sec
              in
              Printf.printf "🆔 Scheduler run ID: %s\n" scheduler_run_id;
              
              (* Apply load balancing *)
              Printf.printf "⚖️  Applying load balancing...\n";
              let lb_config = Scheduler.Load_balancer.default_config contact_count in
              (match Scheduler.Load_balancer.distribute_schedules result.schedules lb_config with
               | Ok balanced_schedules ->
                   Printf.printf "   Load balancing complete\n";
                   
                   (* Save to database using smart update *)
                   Printf.printf "💾 Saving schedules to database...\n";
                   (match update_email_schedules ~use_smart_update:true balanced_schedules scheduler_run_id with
                    | Ok changes ->
                        Printf.printf "   Successfully saved %d schedules to database\n" changes;
                        Printf.printf "✅ Comprehensive scheduling complete!\n\n";
                        
                        (* Show summary by email type *)
                        Printf.printf "📈 Email Type Breakdown:\n";
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
                          Printf.printf "  %s: %d emails\n" email_type count
                        ) type_counts;
                        
                        (* Show any errors *)
                        if result.errors <> [] then (
                          Printf.printf "\n⚠️  Errors encountered:\n";
                          List.iter (fun error ->
                            Printf.printf "  - %s\n" (string_of_error error)
                          ) result.errors
                        );
                        
                    | Error err ->
                        Printf.printf "❌ Failed to save schedules: %s\n" (string_of_db_error err))
               | Error err ->
                   Printf.printf "❌ Load balancing failed: %s\n" (string_of_error err))
          | Error error ->
              Printf.printf "❌ Comprehensive scheduling failed: %s\n" (string_of_error error)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    Printf.printf "This scheduler processes BOTH anniversary emails AND campaign emails from the database\n";
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  run_comprehensive_scheduler db_path

(* Entry point *)
let () = main ()