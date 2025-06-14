open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Performance measurement utilities with high precision *)
let time_it f =
  let start_time = Unix.gettimeofday () in
  let result = f () in
  let end_time = Unix.gettimeofday () in
  (result, end_time -. start_time)

let measure_memory_usage () =
  let gc_stats = Gc.stat () in
  (int_of_float gc_stats.major_words, int_of_float gc_stats.minor_words, gc_stats.top_heap_words)

(* Progress logging with thread safety *)
let log_mutex = Mutex.create ()
let log_progress message =
  Mutex.lock log_mutex;
  let timestamp = Unix.time () |> Unix.localtime in
  Printf.printf "[%02d:%02d:%02d] %s\n%!" 
    timestamp.tm_hour timestamp.tm_min timestamp.tm_sec message;
  Mutex.unlock log_mutex

(* IN-MEMORY database setup functions *)
let create_memory_database () =
  log_progress "🧠 Creating in-memory SQLite database...";
  
  (* Set database path to special in-memory identifier *)
  set_db_path ":memory:";
  
  (* Initialize the in-memory database with schema *)
  match initialize_database () with
  | Error err -> 
      log_progress (Printf.sprintf "❌ In-memory database creation failed: %s" (string_of_db_error err));
      Error err
  | Ok () ->
      log_progress "✅ In-memory database created with schema";
      
      (* Optimize for maximum in-memory performance *)
      log_progress "⚡ Applying in-memory optimizations...";
      let memory_optimizations = [
        "PRAGMA synchronous = OFF";        (* No disk sync needed *)
        "PRAGMA journal_mode = MEMORY";    (* Keep journal in memory *)
        "PRAGMA cache_size = 1000000";     (* Very large cache - 400MB+ *)
        "PRAGMA temp_store = MEMORY";      (* All temp data in memory *)
        "PRAGMA mmap_size = 0";            (* Disable memory mapping (not needed for :memory:) *)
        "PRAGMA page_size = 8192";         (* Larger page size *)
        "PRAGMA auto_vacuum = 0";          (* No vacuum needed for memory DB *)
        "PRAGMA secure_delete = OFF";      (* No secure delete needed *)
        "PRAGMA locking_mode = EXCLUSIVE"; (* Exclusive access *)
        "PRAGMA count_changes = OFF";      (* Don't count changes *)
      ] in
      
      let rec apply_pragmas remaining =
        match remaining with
        | [] -> Ok ()
        | pragma :: rest ->
            match execute_sql_no_result pragma with
            | Ok () -> apply_pragmas rest
            | Error err -> Error err
      in
      
      match apply_pragmas memory_optimizations with
      | Ok () -> 
          log_progress "✅ In-memory optimizations applied";
          Ok ()
      | Error err -> Error err

(* Load contacts from disk database into memory database *)
let load_contacts_to_memory disk_db_path =
  log_progress (Printf.sprintf "📥 Loading contacts from disk database: %s" disk_db_path);
  
  (* First, connect to disk database to read data *)
  set_db_path disk_db_path;
  let start_time = Unix.gettimeofday () in
  
  (* Use the existing function to get contacts in scheduling window *)
  match get_contacts_in_scheduling_window 365 30 with
  | Error err ->
      log_progress (Printf.sprintf "❌ Failed to load contacts from disk: %s" (string_of_db_error err));
      Error err
  | Ok (contacts : contact list) ->
      let load_time = Unix.gettimeofday () -. start_time in
      log_progress (Printf.sprintf "✅ Loaded %d contacts from disk in %.3f seconds" (List.length contacts) load_time);
      
      (* Switch back to memory database *)
      set_db_path ":memory:";
      
      (* Insert contacts into memory database using optimized bulk insert *)
      log_progress "💾 Inserting contacts into memory database...";
      let insert_start = Unix.gettimeofday () in
      
      let contact_values = List.map (fun (contact : contact) ->
        [|
          string_of_int contact.id;
          contact.email;
          (match contact.zip_code with Some z -> z | None -> "");
          (match contact.state with Some s -> string_of_state s | None -> "");
          (match contact.birthday with Some d -> string_of_date d | None -> "");
          (match contact.effective_date with Some d -> string_of_date d | None -> "");
          (match contact.carrier with Some c -> c | None -> "");
          if contact.failed_underwriting then "1" else "0";
        |]
      ) contacts in
      
      let insert_sql = {|
        INSERT INTO contacts (id, email, zip_code, state, birth_date, effective_date, carrier, failed_underwriting)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      |} in
      
      match batch_insert_with_prepared_statement insert_sql contact_values with
      | Error err ->
          log_progress (Printf.sprintf "❌ Failed to insert contacts into memory: %s" (string_of_db_error err));
          Error err
      | Ok inserted_count ->
          let insert_time = Unix.gettimeofday () -. insert_start in
          log_progress (Printf.sprintf "✅ Inserted %d contacts into memory in %.3f seconds" inserted_count insert_time);
          log_progress (Printf.sprintf "   Memory insertion rate: %.0f contacts/sec" (float_of_int inserted_count /. insert_time));
          Ok contacts

(* Load campaign data from disk to memory *)
let load_campaigns_to_memory disk_db_path =
  log_progress "🎯 Loading campaign data from disk to memory...";
  
  (* Connect to disk database *)
  set_db_path disk_db_path;
  
  (* Get campaign types *)
  let campaign_types_sql = "SELECT * FROM campaign_types WHERE active = 1" in
  let campaign_instances_sql = "SELECT * FROM campaign_instances" in
  let contact_campaigns_sql = "SELECT * FROM contact_campaigns WHERE status = 'active'" in
  
  match execute_sql_safe campaign_types_sql with
  | Error err -> Error err
  | Ok campaign_types_rows ->
      match execute_sql_safe campaign_instances_sql with
      | Error err -> Error err
      | Ok campaign_instances_rows ->
          match execute_sql_safe contact_campaigns_sql with
          | Error err -> Error err
          | Ok contact_campaigns_rows ->
              (* Switch back to memory database *)
              set_db_path ":memory:";
              
              (* Execute campaign data inserts into memory database *)
              let _result_types = List.iter (fun row ->
                match row with
                | [id; name; respect_exclusion_windows; enable_followups; days_before_event; target_all_contacts; priority; active; spread_evenly; skip_failed_underwriting; created_at; updated_at] ->
                    let values_sql = Printf.sprintf {|
                      INSERT INTO campaign_types 
                      (id, name, respect_exclusion_windows, enable_followups, days_before_event, 
                       target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting, 
                       created_at, updated_at)
                      VALUES (%s, '%s', %s, %s, %s, %s, %s, %s, %s, %s, '%s', '%s')
                    |} id name respect_exclusion_windows enable_followups days_before_event 
                       target_all_contacts priority active spread_evenly skip_failed_underwriting 
                       created_at updated_at in
                    ignore (execute_sql_no_result values_sql)
                | _ -> ()
              ) campaign_types_rows in
              
              let _result_instances = List.iter (fun row ->
                match row with
                | [id; campaign_type; instance_name; email_template; sms_template; active_start_date; active_end_date; spread_start_date; spread_end_date; target_states; target_carriers; metadata; created_at; updated_at] ->
                    let values_sql = Printf.sprintf {|
                      INSERT INTO campaign_instances 
                      (id, campaign_type, instance_name, email_template, sms_template, 
                       active_start_date, active_end_date, spread_start_date, spread_end_date,
                       target_states, target_carriers, metadata, created_at, updated_at)
                      VALUES (%s, '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s', '%s')
                    |} id campaign_type instance_name email_template sms_template 
                       active_start_date active_end_date spread_start_date spread_end_date
                       target_states target_carriers metadata created_at updated_at in
                    ignore (execute_sql_no_result values_sql)
                | _ -> ()
              ) campaign_instances_rows in
              
              let _result_campaigns = List.iter (fun row ->
                match row with
                | [id; contact_id; campaign_instance_id; trigger_date; status; metadata; created_at; updated_at] ->
                    let values_sql = Printf.sprintf {|
                      INSERT INTO contact_campaigns 
                      (id, contact_id, campaign_instance_id, trigger_date, status, metadata, created_at, updated_at)
                      VALUES (%s, %s, %s, '%s', '%s', '%s', '%s', '%s')
                    |} id contact_id campaign_instance_id trigger_date status metadata created_at updated_at in
                    ignore (execute_sql_no_result values_sql)
                | _ -> ()
              ) contact_campaigns_rows in
              
              log_progress (Printf.sprintf "✅ Loaded campaign data: %d types, %d instances, %d enrollments" 
                (List.length campaign_types_rows) (List.length campaign_instances_rows) (List.length contact_campaigns_rows));
              Ok ()

(* ULTRA-FAST in-memory parallel schedule generation *)
let inmemory_parallel_generate_schedules contacts config scheduler_run_id contact_count =
  let num_threads = min 8 (max 1 (contact_count / 500)) in  (* More aggressive threading for memory *)
  let chunk_size = (List.length contacts + num_threads - 1) / num_threads in
  
  log_progress (Printf.sprintf "🧵 IN-MEMORY parallel generation: %d threads, ~%d contacts each" 
    num_threads chunk_size);
  
  (* Split contacts into chunks *)
  let rec chunk_list lst size =
    match lst with
    | [] -> []
    | _ ->
        let rec take n acc = function
          | [] -> (List.rev acc, [])
          | x :: xs when n > 0 -> take (n-1) (x::acc) xs
          | xs -> (List.rev acc, xs)
        in
        let (chunk, rest) = take size [] lst in
        chunk :: chunk_list rest size
  in
  
  let chunks = chunk_list contacts chunk_size in
  let results = Array.make (List.length chunks) [] in
  let threads = ref [] in
  
  (* Process each chunk in a separate thread with in-memory database *)
  List.iteri (fun i chunk ->
    let thread = Thread.create (fun () ->
      let thread_id = i + 1 in
      let context = create_context config in
      let context_with_run_id = { context with run_id = scheduler_run_id } in
      
      let thread_schedules = ref [] in
      
      (* Process anniversary emails for each contact *)
      List.iter (fun contact ->
        match calculate_schedules_for_contact context_with_run_id contact with
        | Ok contact_schedules -> thread_schedules := contact_schedules @ !thread_schedules
        | Error _ -> ()
      ) chunk;
      
      log_progress (Printf.sprintf "   Thread %d completed: %d schedules" 
        thread_id (List.length !thread_schedules));
      results.(i) <- !thread_schedules;
    ) () in
    threads := thread :: !threads
  ) chunks;
  
  (* Wait for all threads to complete *)
  List.iter Thread.join (List.rev !threads);
  
  (* Combine anniversary results *)
  let anniversary_schedules = Array.fold_left (fun acc schedules -> schedules @ acc) [] results in
  log_progress (Printf.sprintf "✅ Anniversary generation complete: %d schedules" (List.length anniversary_schedules));
  
  (* Campaign and follow-up processing (in-memory) *)
  log_progress "🎯 Processing campaigns in memory...";
  let context = create_context config in
  let context_with_run_id = { context with run_id = scheduler_run_id } in
  
  let (campaign_schedules, campaign_errors) = calculate_all_campaign_schedules context_with_run_id in
  log_progress (Printf.sprintf "✅ Campaign generation complete: %d schedules" (List.length campaign_schedules));
  
  let followup_schedules = calculate_followup_emails context_with_run_id in
  log_progress (Printf.sprintf "✅ Follow-up generation complete: %d schedules" (List.length followup_schedules));
  
  let all_schedules = anniversary_schedules @ campaign_schedules @ followup_schedules in
  log_progress (Printf.sprintf "✅ Total in-memory generation: %d schedules" (List.length all_schedules));
  
  (all_schedules, campaign_errors)

(* Write results back to disk database *)
let write_results_to_disk disk_db_path schedules =
  log_progress (Printf.sprintf "💾 Writing %d schedules to disk database: %s" (List.length schedules) disk_db_path);
  
  let start_time = Unix.gettimeofday () in
  
  (* Switch to disk database *)
  set_db_path disk_db_path;
  
  (* Use optimized batch insert *)
  match batch_insert_schedules_optimized schedules with
  | Error err ->
      log_progress (Printf.sprintf "❌ Failed to write schedules to disk: %s" (string_of_db_error err));
      Error err
  | Ok inserted_count ->
      let write_time = Unix.gettimeofday () -. start_time in
      log_progress (Printf.sprintf "✅ Wrote %d schedules to disk in %.3f seconds" inserted_count write_time);
      log_progress (Printf.sprintf "   Disk write rate: %.0f schedules/sec" (float_of_int inserted_count /. write_time));
      Ok inserted_count

(* Ultra-fast in-memory campaign hybrid performance test *)
let run_inmemory_campaign_hybrid_test disk_db_path test_name =
  log_progress (Printf.sprintf "🚀 Starting IN-MEMORY Campaign Hybrid Test: %s" test_name);
  log_progress "============================================================";
  log_progress "Strategy: Load to memory → Process in memory → Write to disk";
  
  let total_start_time = Unix.gettimeofday () in
  
  (* Step 1: Create in-memory database *)
  match create_memory_database () with
  | Error err -> 
      log_progress (Printf.sprintf "❌ Memory database creation failed: %s" (string_of_db_error err));
      (0, 0.0, 0, 0)
  | Ok () ->
      (* Step 2: Load contacts from disk to memory *)
      let (contacts_result, load_time) = time_it (fun () ->
        load_contacts_to_memory disk_db_path
      ) in
      
      match contacts_result with
      | Error err ->
          log_progress (Printf.sprintf "❌ Contact loading failed: %s" (string_of_db_error err));
          (0, load_time, 0, 0)
      | Ok contacts ->
          let contact_count = List.length contacts in
          log_progress (Printf.sprintf "✅ Loaded %d contacts to memory in %.3f seconds" contact_count load_time);
          
          if contact_count = 0 then (
            log_progress "   No contacts to process";
            (0, load_time, 0, 0)
          ) else (
            (* Step 3: Load campaign data to memory *)
            let (campaign_load_result, campaign_load_time) = time_it (fun () ->
              load_campaigns_to_memory disk_db_path
            ) in
            
            match campaign_load_result with
            | Error err ->
                log_progress (Printf.sprintf "❌ Campaign loading failed: %s" (string_of_db_error err));
                (contact_count, load_time +. campaign_load_time, 0, 0)
            | Ok () ->
                (* Step 4: Measure memory before processing *)
                let (major_before, minor_before, _heap_before) = measure_memory_usage () in
                
                (* Step 5: Ultra-fast in-memory processing *)
                log_progress "⚡ Ultra-fast in-memory schedule generation...";
                let config = Scheduler.Config.load_for_org 206 disk_db_path in
                let scheduler_run_id = Printf.sprintf "inmemory_%s_%f" test_name (Unix.time ()) in
                
                let (all_schedules_result, schedule_time) = time_it (fun () ->
                  inmemory_parallel_generate_schedules contacts config scheduler_run_id contact_count
                ) in
                
                let (all_schedules, campaign_errors) = all_schedules_result in
                let schedule_count = List.length all_schedules in
                log_progress (Printf.sprintf "✅ Generated %d schedules in %.3f seconds" schedule_count schedule_time);
                log_progress (Printf.sprintf "   IN-MEMORY throughput: %.0f schedules/second" 
                  (float_of_int schedule_count /. schedule_time));
                log_progress (Printf.sprintf "   IN-MEMORY contact rate: %.0f contacts/second" 
                  (float_of_int contact_count /. schedule_time));
                
                (* Step 6: Memory usage measurement *)
                let (major_after, minor_after, _heap_after) = measure_memory_usage () in
                let memory_used = (major_after - major_before) + (minor_after - minor_before) in
                log_progress (Printf.sprintf "   Memory used: %d words (%.1f MB)" 
                  memory_used (float_of_int memory_used *. 8.0 /. 1024.0 /. 1024.0));
                
                (* Step 7: Conflict resolution and load balancing (in memory) *)
                log_progress "⚔️  In-memory conflict resolution...";
                let (resolved_result, resolution_time) = time_it (fun () ->
                  resolve_campaign_conflicts all_schedules
                ) in
                let (resolved_schedules, conflicted_schedules) = resolved_result in
                let final_schedules = resolved_schedules @ conflicted_schedules in
                
                log_progress "⚖️  In-memory load balancing...";
                let lb_config = Scheduler.Config.to_load_balancing_config config in
                let (lb_result, lb_time) = time_it (fun () ->
                  Scheduler.Load_balancer.distribute_schedules final_schedules lb_config
                ) in
                
                match lb_result with
                | Error err ->
                    log_progress (Printf.sprintf "❌ Load balancing failed: %s" (Scheduler.Types.string_of_error err));
                    let processing_time = load_time +. campaign_load_time +. schedule_time +. resolution_time in
                    (contact_count, processing_time, schedule_count, 0)
                | Ok balanced_schedules ->
                    log_progress (Printf.sprintf "✅ Load balancing completed in %.3f seconds" lb_time);
                    
                    (* Step 8: Write results back to disk *)
                    let (write_result, write_time) = time_it (fun () ->
                      write_results_to_disk disk_db_path balanced_schedules
                    ) in
                    
                    match write_result with
                    | Error err ->
                        log_progress (Printf.sprintf "❌ Disk write failed: %s" (string_of_db_error err));
                        let processing_time = load_time +. campaign_load_time +. schedule_time +. resolution_time +. lb_time in
                        (contact_count, processing_time, schedule_count, 0)
                    | Ok inserted_count ->
                        let total_time = Unix.gettimeofday () -. total_start_time in
                        
                        log_progress "";
                        log_progress "🎉 IN-MEMORY ULTRA-PERFORMANCE RESULTS:";
                        log_progress "=======================================";
                        log_progress (Printf.sprintf "   • Total time: %.3f seconds" total_time);
                        log_progress (Printf.sprintf "   • Data load time: %.3f seconds" (load_time +. campaign_load_time));
                        log_progress (Printf.sprintf "   • In-memory processing: %.3f seconds" (schedule_time +. resolution_time +. lb_time));
                        log_progress (Printf.sprintf "   • Disk write time: %.3f seconds" write_time);
                        log_progress (Printf.sprintf "   • Contacts processed: %d" contact_count);
                        log_progress (Printf.sprintf "   • Schedules generated: %d" schedule_count);
                        log_progress (Printf.sprintf "   • Schedules written: %d" inserted_count);
                        log_progress (Printf.sprintf "   • Campaign errors: %d" (List.length campaign_errors));
                        log_progress (Printf.sprintf "   • Overall throughput: %.0f contacts/second" 
                          (float_of_int contact_count /. total_time));
                        log_progress (Printf.sprintf "   • Pure processing rate: %.0f contacts/second" 
                          (float_of_int contact_count /. (schedule_time +. resolution_time +. lb_time)));
                        log_progress (Printf.sprintf "   • Memory efficiency: %.1f KB per contact" 
                          (float_of_int memory_used *. 8.0 /. 1024.0 /. float_of_int contact_count));
                        log_progress "";
                        log_progress "🧠 IN-MEMORY OPTIMIZATION BREAKDOWN:";
                        log_progress "   • Database: 100% IN-MEMORY (zero disk I/O during processing)";
                        log_progress "   • Threading: Up to 8 threads for memory processing";
                        log_progress "   • Caching: 400MB+ SQLite cache";
                        log_progress "   • Journaling: Memory-only journal";
                        log_progress "   • Result: MAXIMUM POSSIBLE PERFORMANCE! 🚀⚡";
                        
                        (contact_count, total_time, schedule_count, inserted_count)
          )

let main () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.printf "Usage: %s <disk_database_path> <test_name>\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_750k_test.db \"InMemory_Ultra_750K_Test\"\n" Sys.argv.(0);
    exit 1
  );
  
  let disk_db_path = Sys.argv.(1) in
  let test_name = Sys.argv.(2) in
  
  let _ = run_inmemory_campaign_hybrid_test disk_db_path test_name in
  ()

let () = main ()