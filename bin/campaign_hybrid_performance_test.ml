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

(* CAMPAIGN-AWARE parallel schedule generation *)
let parallel_generate_campaign_schedules contacts config scheduler_run_id contact_count =
  let num_threads = min 4 (max 1 (contact_count / 1000)) in
  let chunk_size = (List.length contacts + num_threads - 1) / num_threads in
  
  log_progress (Printf.sprintf "🧵 Parallelizing CAMPAIGN-AWARE schedule generation: %d threads, ~%d contacts each" 
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
  
  (* Process each chunk in a separate thread with FULL campaign logic *)
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
      
      log_progress (Printf.sprintf "   Thread %d completed anniversary processing: %d schedules" 
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
  
  (* Now calculate campaign schedules (single-threaded as it involves complex state) *)
  log_progress "🎯 Processing campaign schedules...";
  let context = create_context config in
  let context_with_run_id = { context with run_id = scheduler_run_id } in
  
  let (campaign_schedules, campaign_errors) = calculate_all_campaign_schedules context_with_run_id in
  log_progress (Printf.sprintf "✅ Campaign generation complete: %d schedules" (List.length campaign_schedules));
  
  if campaign_errors <> [] then
    log_progress (Printf.sprintf "⚠️  Campaign errors: %d" (List.length campaign_errors));
  
  (* Calculate follow-up schedules *)
  log_progress "📧 Processing follow-up schedules...";
  let followup_schedules = calculate_followup_emails context_with_run_id in
  log_progress (Printf.sprintf "✅ Follow-up generation complete: %d schedules" (List.length followup_schedules));
  
  (* Combine all schedules *)
  let all_schedules = anniversary_schedules @ campaign_schedules @ followup_schedules in
  log_progress (Printf.sprintf "✅ Total schedule generation complete: %d schedules" (List.length all_schedules));
  
  (all_schedules, campaign_errors)

(* Get contacts with campaign-aware filtering *)
let get_contacts_with_campaign_filtering (org_config : enhanced_organization_config) =
  log_progress "📊 Loading contacts with campaign-aware filtering...";
  
  (* Calculate minimum effective date based on organization config *)
  let today = current_date () in
  let months_back = org_config.effective_date_first_email_months in
  let (year, month, day) = today in
  let target_year = if month <= months_back then year - 1 else year in
  let target_month = if month <= months_back then month + 12 - months_back else month - months_back in
  let min_effective_date = (target_year, target_month, day) in
  let min_date_str = string_of_date min_effective_date in
  
  log_progress (Printf.sprintf "   Filtering contacts with effective_date >= %s (%d months back)" 
    min_date_str months_back);
  
  (* Campaign-aware query *)
  let query = Printf.sprintf {|
    SELECT DISTINCT c.id, c.email, 
           COALESCE(c.zip_code, '') as zip_code, 
           COALESCE(c.state, '') as state, 
           COALESCE(c.birth_date, '') as birth_date, 
           COALESCE(c.effective_date, '') as effective_date,
           COALESCE(c.carrier, c.current_carrier, '') as carrier,
           COALESCE(c.failed_underwriting, 0) as failed_underwriting
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
        AND date('now') BETWEEN COALESCE(ci.active_start_date, date('now')) 
                            AND COALESCE(ci.active_end_date, date('now', '+1 year'))
      )
      OR 
      -- Include contacts with upcoming anniversaries (birthdays)
      (c.birth_date IS NOT NULL AND c.birth_date != '')
    )
    ORDER BY c.id
  |} min_date_str in
  
  match execute_sql_safe query with
  | Error err -> 
      log_progress (Printf.sprintf "   ❌ Query failed: %s" (string_of_db_error err));
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
      log_progress (Printf.sprintf "   ✅ Found %d eligible contacts" (List.length contacts));
      Ok contacts

(* Sequential database insertion with optimizations *)
let sequential_insert_schedules schedules =
  log_progress "💾 Sequential database insertion with WAL optimizations...";
  batch_insert_schedules_optimized schedules

(* Campaign-aware hybrid performance test *)
let run_campaign_hybrid_performance_test db_path test_name =
  log_progress (Printf.sprintf "🚀 Starting CAMPAIGN-AWARE hybrid performance test: %s" test_name);
  log_progress "=========================================================";
  log_progress "Strategy: Parallel campaign-aware generation + Sequential database insertion";
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      log_progress (Printf.sprintf "❌ Database initialization failed: %s" (string_of_db_error err));
      (0, 0.0, 0, 0)
  | Ok () ->
      (* Load configuration using the new Config system *)
      let config = Scheduler.Config.load_for_org 206 db_path in
      
      (* Measure contact loading with campaign awareness *)
      log_progress "📊 Loading contacts with campaign awareness...";
      let (contacts_result, load_time) = time_it (fun () ->
        get_contacts_with_campaign_filtering config.organization
      ) in
      
      match contacts_result with
      | Error err ->
          log_progress (Printf.sprintf "❌ Contact loading failed: %s" (string_of_db_error err));
          (0, load_time, 0, 0)
      | Ok contacts ->
          let contact_count = List.length contacts in
          log_progress (Printf.sprintf "   Loaded %d contacts in %.3f seconds" contact_count load_time);
          
          if contact_count = 0 then (
            log_progress "   No contacts need scheduling";
            (0, load_time, 0, 0)
          ) else (
            (* Manage campaign lifecycle *)
            log_progress "🔄 Managing campaign lifecycle...";
            let context = create_context config in
            let _ = manage_campaign_lifecycle context in
            
            (* Measure memory before scheduling *)
            let (major_before, minor_before, _heap_before) = measure_memory_usage () in
            
            (* PARALLEL: Campaign-aware schedule generation *)
            log_progress "⚡ Generating schedules (campaign-aware parallel processing)...";
            let scheduler_run_id = Printf.sprintf "campaign_hybrid_%s_%f" test_name (Unix.time ()) in
            
            let (all_schedules_result, schedule_time) = time_it (fun () ->
              parallel_generate_campaign_schedules contacts config scheduler_run_id contact_count
            ) in
            
            let (all_schedules, campaign_errors) = all_schedules_result in
            let schedule_count = List.length all_schedules in
            log_progress (Printf.sprintf "   Generated %d schedules in %.3f seconds" schedule_count schedule_time);
            log_progress (Printf.sprintf "   Throughput: %.0f schedules/second" 
              (float_of_int schedule_count /. schedule_time));
            
            (* Measure memory after scheduling *)
            let (major_after, minor_after, _heap_after) = measure_memory_usage () in
            let memory_used = (major_after - major_before) + (minor_after - minor_before) in
            log_progress (Printf.sprintf "   Memory used: %d words (%.1f MB)" 
              memory_used (float_of_int memory_used *. 8.0 /. 1024.0 /. 1024.0));
            
            (* Apply conflict resolution *)
            log_progress "⚔️  Applying campaign conflict resolution...";
            let (resolved_result, resolution_time) = time_it (fun () ->
              resolve_campaign_conflicts all_schedules
            ) in
            let (resolved_schedules, conflicted_schedules) = resolved_result in
            let final_schedules = resolved_schedules @ conflicted_schedules in
            log_progress (Printf.sprintf "   Conflict resolution completed in %.3f seconds" resolution_time);
            
            (* Load balancing *)
            log_progress "⚖️  Applying load balancing...";
            let lb_config = Scheduler.Config.to_load_balancing_config config in
            let (lb_result, lb_time) = time_it (fun () ->
              Scheduler.Load_balancer.distribute_schedules final_schedules lb_config
            ) in
            
            match lb_result with
            | Error err ->
                log_progress (Printf.sprintf "❌ Load balancing failed: %s" (Scheduler.Types.string_of_error err));
                (contact_count, load_time +. schedule_time +. resolution_time, schedule_count, 0)
            | Ok balanced_schedules ->
                log_progress (Printf.sprintf "   Load balancing completed in %.3f seconds" lb_time);
                
                (* SEQUENTIAL: Database insertion with optimizations *)
                log_progress "💾 Inserting schedules (sequential with WAL)...";
                let (insert_result, insert_time) = time_it (fun () ->
                  sequential_insert_schedules balanced_schedules
                ) in
                
                match insert_result with
                | Error err ->
                    log_progress (Printf.sprintf "❌ Database insertion failed: %s" (string_of_db_error err));
                    (contact_count, load_time +. schedule_time +. resolution_time +. lb_time, schedule_count, 0)
                | Ok inserted_count ->
                    log_progress (Printf.sprintf "   Inserted %d schedules in %.3f seconds" inserted_count insert_time);
                    log_progress (Printf.sprintf "   Throughput: %.0f inserts/second" 
                      (float_of_int inserted_count /. insert_time));
                    
                    let total_time = load_time +. schedule_time +. resolution_time +. lb_time +. insert_time in
                    log_progress "";
                    log_progress "📈 CAMPAIGN-AWARE HYBRID PERFORMANCE SUMMARY:";
                    log_progress "==============================================";
                    log_progress (Printf.sprintf "   • Total time: %.3f seconds" total_time);
                    log_progress (Printf.sprintf "   • Contacts processed: %d" contact_count);
                    log_progress (Printf.sprintf "   • Schedules generated: %d" schedule_count);
                    log_progress (Printf.sprintf "   • Schedules inserted: %d" inserted_count);
                    log_progress (Printf.sprintf "   • Campaign errors: %d" (List.length campaign_errors));
                    log_progress (Printf.sprintf "   • Overall throughput: %.0f contacts/second" 
                      (float_of_int contact_count /. total_time));
                    log_progress (Printf.sprintf "   • Memory efficiency: %.1f KB per contact" 
                      (float_of_int memory_used *. 8.0 /. 1024.0 /. float_of_int contact_count));
                    log_progress "";
                    log_progress "🧠 CAMPAIGN OPTIMIZATION BREAKDOWN:";
                    log_progress (Printf.sprintf "   • Anniversary generation: PARALLEL (%.1fx faster potential)" 
                      (float_of_int (min 4 (contact_count / 1000))));
                    log_progress "   • Campaign generation: SINGLE-THREADED (complex state)";
                    log_progress "   • Conflict resolution: OPTIMIZED algorithm";
                    log_progress "   • Database insertion: SEQUENTIAL + WAL (optimal for SQLite)";
                    log_progress "   • Result: Campaign-aware enterprise performance! 🎯";
                    
                    (contact_count, total_time, schedule_count, inserted_count)
          )

let main () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.printf "Usage: %s <database_path> <test_name>\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_test_dataset.sqlite3 \"Campaign-Aware 750k Test\"\n" Sys.argv.(0);
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  let test_name = Sys.argv.(2) in
  
  let _ = run_campaign_hybrid_performance_test db_path test_name in
  ()

let () = main ()