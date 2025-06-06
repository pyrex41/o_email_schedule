open Scheduler.Email_scheduler
open Scheduler.Db.Database  (* Keep using the working Database module *)

(* Simple wrapper to schedule emails for a contact *)
let schedule_contact_emails contact scheduler_run_id =
  let config = Scheduler.Config.default in
  let context = create_context config 1000 in
  let context_with_run_id = { context with run_id = scheduler_run_id } in
  match calculate_schedules_for_contact context_with_run_id contact with
  | Ok schedules -> schedules
  | Error _err -> []

let run_high_performance_scheduler_ffi db_path =
  Printf.printf "=== High-Performance OCaml Email Scheduler (FFI) ===\n\n";
  
  (* For now, use the existing Database module but point to your FFI-synced database *)
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      exit 1
  | Ok () ->
      Printf.printf "✅ Database connected successfully (FFI-synced database)\n";
      
      (* Load ZIP data *)
      let _ = Scheduler.Zip_data.ensure_loaded () in
      Printf.printf "✅ ZIP data loaded\n";
      
      (* Generate run_id for this scheduling run *)
      let scheduler_run_id = 
        let now = Unix.time () in
        let tm = Unix.localtime now in
        Printf.sprintf "ffi_run_%04d%02d%02d_%02d%02d%02d" 
          (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday 
          tm.tm_hour tm.tm_min tm.tm_sec
      in
      Printf.printf "🆔 Generated scheduler run ID: %s\n" scheduler_run_id;
      
      (* Use query-driven contact fetching - same as before *)
      Printf.printf "📊 Loading contacts using query-driven approach...\n";
      let lookahead_days = 60 in
      let lookback_days = 14 in
      
      match get_contacts_in_scheduling_window lookahead_days lookback_days with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok relevant_contacts ->
          let contact_count = List.length relevant_contacts in
          Printf.printf "   Found %d contacts with anniversaries in scheduling window\n" contact_count;
          
          if contact_count = 0 then (
            Printf.printf "✅ No contacts need scheduling at this time\n";
            exit 0
          );
          
          (* Process contacts and generate schedules *)
          Printf.printf "⚡ Processing contacts with high-performance engine...\n";
          let all_schedules = ref [] in
          let scheduled_count = ref 0 in
          
          List.iter (fun contact ->
            let contact_schedules = schedule_contact_emails contact scheduler_run_id in
            all_schedules := contact_schedules @ !all_schedules;
            scheduled_count := !scheduled_count + (List.length contact_schedules);
          ) relevant_contacts;
          
          Printf.printf "   Generated %d total schedules for %d contacts\n" 
            (List.length !all_schedules) !scheduled_count;
          
          (* Apply load balancing *)
          Printf.printf "⚖️  Applying load balancing...\n";
          let total_contacts_for_lb = match get_total_contact_count () with
            | Ok count -> count
            | Error _ -> 1000
          in
          let lb_config = Scheduler.Load_balancer.default_config total_contacts_for_lb in
          (match Scheduler.Load_balancer.distribute_schedules !all_schedules lb_config with
           | Ok balanced_schedules ->
               Printf.printf "   Load balancing complete\n";
               
               (* Use existing batch insert with smart updates *)
               Printf.printf "🚀 Inserting schedules with smart updates...\n";
               (match update_email_schedules ~use_smart_update:true balanced_schedules scheduler_run_id with
                | Ok changes ->
                    Printf.printf "✅ High-performance scheduling complete! %d schedules processed\n" changes;
                    Printf.printf "\n🎯 FFI INTEGRATION NOTES:\n";
                    Printf.printf "   • This scheduler works with your FFI-synced database\n";
                    Printf.printf "   • Use this with: ./ffi_workflow.sh run working_copy.db\n";
                    Printf.printf "   • The database file is automatically synced with Turso via FFI\n";
                    Printf.printf "   • No manual sync steps needed after this completes\n";
                | Error err ->
                    Printf.printf "❌ Failed to insert schedules: %s\n" (string_of_db_error err))
           | Error err ->
               Printf.printf "❌ Load balancing failed: %s\n" (Scheduler.Types.string_of_error err))

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    Printf.printf "Example: %s working_copy.db\n" Sys.argv.(0);
    Printf.printf "\nFor FFI workflow:\n";
    Printf.printf "  ./ffi_workflow.sh run working_copy.db\n";
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  run_high_performance_scheduler_ffi db_path

(* Entry point *)
let () = main () 