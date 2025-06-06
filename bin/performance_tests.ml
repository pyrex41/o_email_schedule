open Scheduler.Email_scheduler
open Scheduler.Db.Database

(* Performance measurement utilities *)
let time_it f =
  let start_time = Unix.time () in
  let result = f () in
  let end_time = Unix.time () in
  (result, end_time -. start_time)

let measure_memory_usage () =
  let gc_stats = Gc.stat () in
  (int_of_float gc_stats.major_words, int_of_float gc_stats.minor_words, gc_stats.top_heap_words)

(* Scheduler run with performance measurement *)
let run_scheduler_with_metrics db_path test_name =
  Printf.printf "\n=== %s ===\n" test_name;
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      (0, 0.0, 0, 0)
  | Ok () ->
      let _ = Scheduler.Zip_data.ensure_loaded () in
      
      (* Measure contact loading performance *)
      Printf.printf "📊 Loading contacts...\n";
      let (contacts_result, load_time) = time_it (fun () ->
        get_contacts_in_scheduling_window 60 14
      ) in
      
      match contacts_result with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          (0, 0.0, 0, 0)
      | Ok contacts ->
          let contact_count = List.length contacts in
          Printf.printf "   Loaded %d contacts in %.3f seconds\n" contact_count load_time;
          Printf.printf "   Throughput: %.0f contacts/second\n" (float_of_int contact_count /. load_time);
          
          if contact_count = 0 then (
            Printf.printf "   No contacts need scheduling\n";
            (0, load_time, 0, 0)
          ) else (
            (* Measure memory before scheduling *)
            let (major_before, minor_before, _heap_before) = measure_memory_usage () in
            
            (* Measure scheduling performance *)
            Printf.printf "⚡ Generating schedules...\n";
            let scheduler_run_id = Printf.sprintf "perf_test_%s_%f" test_name (Unix.time ()) in
            
            let (all_schedules, schedule_time) = time_it (fun () ->
              let schedules = ref [] in
              List.iter (fun contact ->
                let config = Scheduler.Config.default in
                let context = create_context config contact_count in
                let context_with_run_id = { context with run_id = scheduler_run_id } in
                match calculate_schedules_for_contact context_with_run_id contact with
                | Ok contact_schedules -> schedules := contact_schedules @ !schedules
                | Error _ -> ()
              ) contacts;
              !schedules
            ) in
            
            let schedule_count = List.length all_schedules in
            Printf.printf "   Generated %d schedules in %.3f seconds\n" schedule_count schedule_time;
            Printf.printf "   Throughput: %.0f schedules/second\n" (float_of_int schedule_count /. schedule_time);
            
            (* Measure memory after scheduling *)
            let (major_after, minor_after, _heap_after) = measure_memory_usage () in
            let memory_used = (major_after - major_before) + (minor_after - minor_before) in
            Printf.printf "   Memory used: %d words (%.1f MB)\n" memory_used 
              (float_of_int memory_used *. 8.0 /. 1024.0 /. 1024.0);
            
            (* Measure load balancing performance *)
            Printf.printf "⚖️  Load balancing...\n";
            let total_contacts = match get_total_contact_count () with
              | Ok count -> count
              | Error _ -> contact_count
            in
            let lb_config = Scheduler.Load_balancer.default_config total_contacts in
            let (lb_result, lb_time) = time_it (fun () ->
              Scheduler.Load_balancer.distribute_schedules all_schedules lb_config
            ) in
            
            match lb_result with
            | Error err ->
                Printf.printf "❌ Load balancing failed: %s\n" (Scheduler.Types.string_of_error err);
                (contact_count, load_time +. schedule_time, schedule_count, 0)
            | Ok balanced_schedules ->
                Printf.printf "   Load balancing completed in %.3f seconds\n" lb_time;
                
                (* Measure database insertion performance *)
                Printf.printf "💾 Inserting schedules...\n";
                let (insert_result, insert_time) = time_it (fun () ->
                  (* Use optimized batch insertion for large datasets *)
                  if schedule_count > 1000 then
                    batch_insert_schedules_optimized balanced_schedules
                  else
                    batch_insert_schedules_chunked balanced_schedules 500
                ) in
                
                match insert_result with
                | Error err ->
                    Printf.printf "❌ Database insertion failed: %s\n" (string_of_db_error err);
                    (contact_count, load_time +. schedule_time +. lb_time, schedule_count, 0)
                | Ok inserted_count ->
                    Printf.printf "   Inserted %d schedules in %.3f seconds\n" inserted_count insert_time;
                    Printf.printf "   Throughput: %.0f inserts/second\n" (float_of_int inserted_count /. insert_time);
                    
                    let total_time = load_time +. schedule_time +. lb_time +. insert_time in
                    Printf.printf "\n📈 Performance Summary:\n";
                    Printf.printf "   • Total time: %.3f seconds\n" total_time;
                    Printf.printf "   • Contacts processed: %d\n" contact_count;
                    Printf.printf "   • Schedules generated: %d\n" schedule_count;
                    Printf.printf "   • Schedules inserted: %d\n" inserted_count;
                    Printf.printf "   • Overall throughput: %.0f contacts/second\n" (float_of_int contact_count /. total_time);
                    Printf.printf "   • Memory efficiency: %.1f KB per contact\n" 
                      (float_of_int memory_used *. 8.0 /. 1024.0 /. float_of_int contact_count);
                    
                    (contact_count, total_time, schedule_count, inserted_count)
          )

(* Test with different dataset sizes *)
let run_performance_suite () =
  Printf.printf "🚀 OCaml Email Scheduler Performance Test Suite\n";
  Printf.printf "==============================================\n";
  
  let results = ref [] in
  
  (* Test 1: Small dataset (original org-206.sqlite3) *)
  if Sys.file_exists "org-206.sqlite3" then (
    let (contacts1, time1, schedules1, inserts1) = 
      run_scheduler_with_metrics "org-206.sqlite3" "Small Dataset (org-206)" in
    results := ("Small Dataset", contacts1, time1, schedules1, inserts1) :: !results
  );
  
  (* Test 2: Golden dataset (~25k contacts) *)
  if Sys.file_exists "golden_dataset.sqlite3" then (
    let (contacts2, time2, schedules2, inserts2) = 
      run_scheduler_with_metrics "golden_dataset.sqlite3" "Golden Dataset (~25k contacts)" in
    results := ("Golden Dataset", contacts2, time2, schedules2, inserts2) :: !results
  );
  
  (* Test 3: Generated large dataset (if exists) *)
  if Sys.file_exists "large_test_dataset.sqlite3" then (
    let (contacts3, time3, schedules3, inserts3) = 
      run_scheduler_with_metrics "large_test_dataset.sqlite3" "Large Generated Dataset" in
    results := ("Large Generated", contacts3, time3, schedules3, inserts3) :: !results
  );
  
  (* Test 4: Massive dataset (500k contacts) - if exists *)
  if Sys.file_exists "massive_test_dataset.sqlite3" then (
    let (contacts4, time4, schedules4, inserts4) = 
      run_scheduler_with_metrics "massive_test_dataset.sqlite3" "Massive Dataset (500k)" in
    results := ("Massive Dataset", contacts4, time4, schedules4, inserts4) :: !results
  );
  
  (* Performance comparison report *)
  Printf.printf "\n\n🏆 PERFORMANCE COMPARISON REPORT\n";
  Printf.printf "=================================\n";
  Printf.printf "%-20s | %-10s | %-10s | %-12s | %-12s | %-15s\n" 
    "Dataset" "Contacts" "Time (s)" "Schedules" "Inserts" "Throughput (c/s)";
  Printf.printf "%s\n" (String.make 95 '-');
  
  List.rev !results |> List.iter (fun (name, contacts, time, schedules, inserts) ->
    let throughput = if time > 0.0 then float_of_int contacts /. time else 0.0 in
    Printf.printf "%-20s | %-10d | %-10.3f | %-12d | %-12d | %-15.0f\n" 
      name contacts time schedules inserts throughput
  );
  
  Printf.printf "\n✅ Performance testing complete!\n"

(* Scalability stress test *)
let run_scalability_test db_path =
  Printf.printf "\n🔥 SCALABILITY STRESS TEST\n";
  Printf.printf "==========================\n";
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err)
  | Ok () ->
      (* Test with increasing window sizes *)
      let window_sizes = [30; 60; 90; 120; 180; 365] in
      
      Printf.printf "Testing scheduler with different lookahead windows:\n\n";
      
      List.iter (fun window_days ->
        Printf.printf "📊 Testing %d-day window...\n" window_days;
        
        let (contacts_result, time) = time_it (fun () ->
          get_contacts_in_scheduling_window window_days 14
        ) in
        
        match contacts_result with
        | Error err ->
            Printf.printf "   ❌ Error: %s\n" (string_of_db_error err)
        | Ok contacts ->
            let contact_count = List.length contacts in
            Printf.printf "   Found %d contacts in %.3f seconds (%.0f contacts/second)\n" 
              contact_count time (float_of_int contact_count /. time);
            
            (* Memory measurement *)
            let (major, minor, _heap) = measure_memory_usage () in
            Printf.printf "   Memory usage: %d words (%.1f MB)\n" 
              (major + minor) (float_of_int (major + minor) *. 8.0 /. 1024.0 /. 1024.0);
      ) window_sizes;
      
      Printf.printf "\n✅ Scalability test complete!\n"

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <command> [database_path]\n" Sys.argv.(0);
    Printf.printf "Commands:\n";
    Printf.printf "  suite               - Run full performance test suite\n";
    Printf.printf "  single <db_path>    - Test single database\n";
    Printf.printf "  scalability <db_path> - Run scalability stress test\n";
    exit 1
  );
  
  let command = Sys.argv.(1) in
  match command with
  | "suite" -> run_performance_suite ()
  | "single" when argc >= 3 -> 
      let db_path = Sys.argv.(2) in
      let _ = run_scheduler_with_metrics db_path "Single Database Test" in
      ()
  | "scalability" when argc >= 3 ->
      let db_path = Sys.argv.(2) in
      run_scalability_test db_path
  | _ ->
      Printf.printf "Invalid command or missing database path\n";
      exit 1

(* Entry point *)
let () = main () 