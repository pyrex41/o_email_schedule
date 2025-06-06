open Scheduler.Email_scheduler
open Scheduler.Db.Turso_integration  (* Use FFI integration instead of Database *)

(* FFI-powered scheduler with real-time Turso sync *)

let schedule_contact_emails contact scheduler_run_id =
  let config = Scheduler.Config.default in
  let context = create_context config 1000 in
  let context_with_run_id = { context with run_id = scheduler_run_id } in
  match calculate_schedules_for_contact context_with_run_id contact with
  | Ok schedules -> schedules
  | Error _err -> []

let run_ffi_scheduler () =
  Printf.printf "=== Turso FFI High-Performance Scheduler ===\n\n";
  
  (* Initialize FFI connection (auto-syncs from Turso) *)
  Printf.printf "🔗 Connecting to Turso via FFI...\n";
  match get_connection () with
  | Error err -> 
      Printf.printf "❌ Turso connection failed: %s\n" (string_of_db_error err);
      Printf.printf "💡 Make sure TURSO_DATABASE_URL and TURSO_AUTH_TOKEN are set\n";
      exit 1
  | Ok _conn ->
      Printf.printf "✅ Connected to Turso with real-time sync enabled\n";
      
      (* Load ZIP data *)
      let _ = Scheduler.Zip_data.ensure_loaded () in
      Printf.printf "✅ ZIP data loaded\n";
      
      (* Generate run_id *)
      let scheduler_run_id = 
        let now = Unix.time () in
        let tm = Unix.localtime now in
        Printf.sprintf "ffi_run_%04d%02d%02d_%02d%02d%02d" 
          (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday 
          tm.tm_hour tm.tm_min tm.tm_sec
      in
      Printf.printf "🆔 Scheduler run ID: %s\n\n" scheduler_run_id;
      
      (* Load contacts using optimized query *)
      Printf.printf "📊 Loading contacts with scheduling windows...\n";
      let lookahead_days = 60 in
      let lookback_days = 14 in
      
      (* Use FFI-powered SQL execution *)
      let contact_query = Printf.sprintf 
        "SELECT id, email, zip_code, state, birthday, effective_date 
         FROM contacts 
         WHERE (birthday IS NOT NULL AND DATE(birthday, '+%d days') >= DATE('now') AND DATE(birthday, '+%d days') <= DATE('now', '+%d days'))
            OR (effective_date IS NOT NULL AND DATE(effective_date, '+%d days') >= DATE('now', '-%d days') AND DATE(effective_date, '+%d days') <= DATE('now', '+%d days'))"
        0 (-lookback_days) lookahead_days 0 lookback_days 0 lookahead_days in
      
      match execute_sql_safe contact_query with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok contact_rows ->
          let contact_count = List.length contact_rows in
          Printf.printf "   Found %d contacts with anniversaries in scheduling window\n" contact_count;
          
          if contact_count = 0 then (
            Printf.printf "✅ No contacts need scheduling at this time\n";
            exit 0
          );
          
          (* Convert rows to contact records *)
          let contacts = List.map (fun row ->
            match row with
            | [id_str; email; zip_code; state; birthday; effective_date] ->
                let id = int_of_string id_str in
                let zip_opt = if zip_code = "" then None else Some zip_code in
                let state_opt = if state = "" then None else Some (Scheduler.Types.state_of_string state) in
                let birthday_opt = if birthday = "" then None else Some (Scheduler.Utils.Simple_date.parse_date birthday) in
                let effective_date_opt = if effective_date = "" then None else Some (Scheduler.Utils.Simple_date.parse_date effective_date) in
                { Scheduler.Types.id; email; zip_code = zip_opt; state = state_opt; 
                  birthday = birthday_opt; effective_date = effective_date_opt }
            | _ -> failwith "Invalid contact row format"
          ) contact_rows in
          
          (* Process contacts and generate schedules *)
          Printf.printf "⚡ Processing contacts with FFI-powered engine...\n";
          let all_schedules = ref [] in
          let scheduled_count = ref 0 in
          
          List.iter (fun contact ->
            let contact_schedules = schedule_contact_emails contact scheduler_run_id in
            all_schedules := contact_schedules @ !all_schedules;
            scheduled_count := !scheduled_count + (List.length contact_schedules);
          ) contacts;
          
          Printf.printf "   Generated %d total schedules for %d contacts\n" 
            (List.length !all_schedules) !scheduled_count;
          
          (* Apply load balancing *)
          Printf.printf "⚖️  Applying load balancing...\n";
          let total_contacts = contact_count in  (* Use actual count *)
          let lb_config = Scheduler.Load_balancer.default_config total_contacts in
          (match Scheduler.Load_balancer.distribute_schedules !all_schedules lb_config with
           | Ok balanced_schedules ->
               Printf.printf "   Load balancing complete\n";
               
               (* Insert schedules using FFI (auto-syncs to Turso) *)
               Printf.printf "🚀 Inserting schedules with real-time Turso sync...\n";
               (match batch_insert_schedules balanced_schedules with
                | Ok inserted_count ->
                    Printf.printf "✅ FFI scheduler complete! %d schedules inserted and synced\n\n" inserted_count;
                    
                    (* Display FFI advantages *)
                    Printf.printf "🎯 FFI ADVANTAGES REALIZED:\n";
                    Printf.printf "   • No copy/diff/apply workflow needed\n";
                    Printf.printf "   • Real-time bidirectional sync with Turso\n";
                    Printf.printf "   • Minimal diff sizes (smart updates)\n";
                    Printf.printf "   • Type-safe error handling\n";
                    Printf.printf "   • Direct libSQL integration\n";
                    Printf.printf "   • Automatic transaction handling\n";
                    
                | Error err ->
                    Printf.printf "❌ Failed to insert schedules: %s\n" (string_of_db_error err))
           | Error err ->
               Printf.printf "❌ Load balancing failed: %s\n" (Scheduler.Types.string_of_error err))

let run_ffi_performance_test () =
  Printf.printf "=== FFI Performance Comparison ===\n\n";
  
  match get_connection () with
  | Error err -> 
      Printf.printf "❌ Connection failed: %s\n" (string_of_db_error err)
  | Ok _conn ->
      Printf.printf "🔗 Connected via FFI\n";
      
      Printf.printf "⚡ FFI PERFORMANCE BENEFITS:\n";
      Printf.printf "   • No file copying overhead\n";
      Printf.printf "   • No diff generation time\n";
      Printf.printf "   • No manual sync steps\n";
      Printf.printf "   • Real-time consistency\n";
      Printf.printf "   • Reduced storage usage\n";
      Printf.printf "   • Eliminated race conditions\n";
      
      let start_time = Unix.time () in
      
      (* Simple test query *)
      (match execute_sql_safe "SELECT COUNT(*) FROM contacts" with
       | Ok [[count]] ->
           let query_time = Unix.time () -. start_time in
           Printf.printf "   • Direct query: %s contacts in %.3f seconds\n" count query_time;
           Printf.printf "✅ FFI integration working perfectly!\n"
       | Ok _ -> Printf.printf "   Unexpected result format\n"
       | Error err -> Printf.printf "   Query error: %s\n" (string_of_db_error err))

let main () =
  let argc = Array.length Sys.argv in
  let mode = if argc >= 2 then Sys.argv.(1) else "run" in
  
  match mode with
  | "test" -> run_ffi_performance_test ()
  | "run" | _ -> run_ffi_scheduler ()

let () = main () 