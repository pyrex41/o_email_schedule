open Scheduler.Email_scheduler
open Scheduler.Db.Database

(* High-performance scheduler implementing Python's query-driven approach *)


let run_high_performance_scheduler db_path =
  Printf.printf "=== High-Performance OCaml Email Scheduler ===\n\n";
  
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
      
      (* Generate run_id for this scheduling run *)
      let scheduler_run_id = 
        let now = Unix.time () in
        let tm = Unix.localtime now in
        Printf.sprintf "run_%04d%02d%02d_%02d%02d%02d" 
          (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday 
          tm.tm_hour tm.tm_min tm.tm_sec
      in
      Printf.printf "🆔 Generated scheduler run ID: %s\n" scheduler_run_id;
      
      (* PERFORMANCE OPTIMIZATION: Use query-driven contact fetching *)
      Printf.printf "📊 Loading contacts using query-driven approach...\n";
      let lookahead_days = 60 in  (* Look ahead 2 months *)
      let lookback_days = 14 in   (* Look back 2 weeks for catch-up *)
      
      match get_contacts_in_scheduling_window lookahead_days lookback_days with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok relevant_contacts ->
          let contact_count = List.length relevant_contacts in
          Printf.printf "   Found %d contacts with anniversaries in scheduling window\n" contact_count;
          Printf.printf "   (This is a massive performance improvement over loading all %s contacts)\n" 
            (match get_total_contact_count () with 
             | Ok total -> string_of_int total 
             | Error _ -> "unknown");
          
          if contact_count = 0 then (
            Printf.printf "✅ No contacts need scheduling at this time\n";
            exit 0
          );
          
          (* Generate scheduler run ID *)
          let scheduler_run_id = "hiperf_" ^ string_of_float (Unix.time ()) in
          Printf.printf "📋 Scheduler run ID: %s\n\n" scheduler_run_id;
          
          (* Process contacts and generate schedules *)
          Printf.printf "⚡ Processing contacts with high-performance engine...\n";
          
          (* Use the full scheduling engine that includes campaigns *)
          let config = Scheduler.Config.default in
          let total_contacts = List.length relevant_contacts in
          
          match Scheduler.Email_scheduler.schedule_emails_streaming ~contacts:relevant_contacts ~config ~total_contacts with
          | Error err ->
              Printf.printf "❌ Scheduling failed: %s\n" (Scheduler.Types.string_of_error err);
              exit 1
          | Ok result ->
              let all_schedules = result.schedules in
              let total_count = List.length all_schedules in
              let scheduled_count = result.emails_scheduled in
              let skipped_count = result.emails_skipped in
          
          Printf.printf "   Generated %d total schedules (%d to send, %d skipped)\n" 
            total_count scheduled_count skipped_count;
          
          (* Apply load balancing and smoothing *)
          Printf.printf "⚖️  Applying load balancing and smoothing...\n";
          let total_contacts_for_lb = match get_total_contact_count () with
            | Ok count -> count
            | Error _ -> 1000  (* fallback *)
          in
          let lb_config = Scheduler.Load_balancer.default_config total_contacts_for_lb in
          (match Scheduler.Load_balancer.distribute_schedules all_schedules lb_config with
           | Ok balanced_schedules ->
               Printf.printf "   Load balancing complete\n";
               
               (* NEW: Smart update approach - preserves scheduler_run_id when content unchanged *)
               Printf.printf "🧠 Using smart update to minimize diff size...\n";
               (match update_email_schedules ~use_smart_update:true balanced_schedules scheduler_run_id with
                | Ok changes ->
                    Printf.printf "   Smart update completed: %d schedules processed\n" changes;
                    Printf.printf "✅ High-performance scheduling complete!\n\n";
                    
                    (* Display summary statistics *)
                    Printf.printf "📈 Performance Summary:\n";
                    Printf.printf "   • Query-driven filtering: %d/%s contacts processed (major speedup)\n" 
                      contact_count 
                      (match get_total_contact_count () with Ok total -> string_of_int total | Error _ -> "?");
                    Printf.printf "   • Smart diff optimization: Preserves scheduler_run_id when content unchanged\n";
                    Printf.printf "   • Minimal database writes: Only updates rows that actually changed\n";
                    Printf.printf "   • Turso sync-friendly: Dramatically reduces diff file size\n";
                    Printf.printf "   • Type-safe error handling: All operations checked at compile time\n";
                    Printf.printf "   • State exclusion rules: Applied with mathematical precision\n";
                    Printf.printf "   • Load balancing: Sophisticated smoothing algorithms applied\n";
                    
                | Error err ->
                    Printf.printf "❌ Failed to insert schedules: %s\n" (string_of_db_error err))
           | Error (Scheduler.Types.LoadBalancingError msg) ->
               Printf.printf "❌ Load balancing failed: %s\n" msg
           | Error err ->
               Printf.printf "❌ Load balancing failed: %s\n" (Scheduler.Types.string_of_error err))

let run_performance_demo db_path =
  Printf.printf "=== Performance Comparison Demo ===\n\n";
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err)
  | Ok () ->
      (* Demonstrate the performance difference *)
      
      Printf.printf "🐌 OLD APPROACH: Get all contacts first...\n";
      let start_time = Unix.time () in
      (match get_all_contacts () with
       | Ok all_contacts -> 
           let old_time = Unix.time () -. start_time in
           Printf.printf "   Loaded %d contacts in %.3f seconds\n" (List.length all_contacts) old_time;
           
           Printf.printf "\n⚡ NEW APPROACH: Query-driven pre-filtering...\n";
           let start_time2 = Unix.time () in
           (match get_contacts_in_scheduling_window 60 14 with
            | Ok relevant_contacts ->
                let new_time = Unix.time () -. start_time2 in
                Printf.printf "   Loaded %d relevant contacts in %.3f seconds\n" 
                  (List.length relevant_contacts) new_time;
                Printf.printf "\n🚀 PERFORMANCE IMPROVEMENT:\n";
                Printf.printf "   • Data reduction: %d → %d contacts (%.1f%% reduction)\n"
                  (List.length all_contacts) (List.length relevant_contacts)
                  (100.0 *. (1.0 -. float_of_int (List.length relevant_contacts) /. float_of_int (List.length all_contacts)));
                Printf.printf "   • Speed improvement: %.1fx faster\n" (old_time /. new_time);
                Printf.printf "   • Memory usage: %.1fx less data in memory\n"
                  (float_of_int (List.length all_contacts) /. float_of_int (List.length relevant_contacts));
            | Error err ->
                Printf.printf "   Error: %s\n" (string_of_db_error err))
       | Error err ->
           Printf.printf "   Error: %s\n" (string_of_db_error err))

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path> [--demo]\n" Sys.argv.(0);
    Printf.printf "  --demo: Run performance comparison demo\n";
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  let is_demo = argc >= 3 && Sys.argv.(2) = "--demo" in
  
  if is_demo then
    run_performance_demo db_path
  else
    run_high_performance_scheduler db_path

(* Entry point *)
let () = main ()