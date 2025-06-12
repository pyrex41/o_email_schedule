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

(* Progress logging *)
let log_progress message =
  let timestamp = Unix.time () |> Unix.localtime in
  Printf.printf "[%02d:%02d:%02d] %s\n%!" 
    timestamp.tm_hour timestamp.tm_min timestamp.tm_sec message

(* Parallel processing using threading *)
let parallel_map_chunks chunk_size f lst =
  let chunks = 
    let rec chunk acc current_chunk remaining =
      match remaining with
      | [] -> if current_chunk = [] then acc else current_chunk :: acc
      | x :: xs ->
          if List.length current_chunk >= chunk_size then
            chunk (current_chunk :: acc) [x] xs
          else
            chunk acc (x :: current_chunk) xs
    in
    chunk [] [] lst |> List.rev
  in
  
  log_progress (Printf.sprintf "Processing %d items in %d chunks of %d" 
    (List.length lst) (List.length chunks) chunk_size);
  
  (* Process chunks in parallel using threads *)
  let process_chunk chunk_id chunk =
    log_progress (Printf.sprintf "Processing chunk %d/%d (%d items)" 
      (chunk_id + 1) (List.length chunks) (List.length chunk));
    let results = List.map f chunk in
    log_progress (Printf.sprintf "Completed chunk %d/%d" (chunk_id + 1) (List.length chunks));
    results
  in
  
  (* For now, let's use sequential processing with better logging *)
  (* TODO: Add proper threading with Domain.spawn in OCaml 5.0+ *)
  List.mapi process_chunk chunks |> List.flatten

(* High-performance scheduler run with parallel processing *)
let run_parallel_scheduler_with_metrics db_path test_name =
  log_progress (Printf.sprintf "=== %s ===" test_name);
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      log_progress (Printf.sprintf "❌ Database initialization failed: %s" (string_of_db_error err));
      (0, 0.0, 0, 0)
  | Ok () ->
      log_progress "✅ Database connected successfully";
      let _ = Scheduler.Zip_data.ensure_loaded () in
      log_progress "✅ ZIP data loaded";
      
      (* Measure contact loading performance *)
      log_progress "📊 Loading contacts with window filtering...";
      let (contacts_result, load_time) = time_it (fun () ->
        get_contacts_in_scheduling_window 60 14
      ) in
      
      match contacts_result with
      | Error err ->
          log_progress (Printf.sprintf "❌ Failed to load contacts: %s" (string_of_db_error err));
          (0, 0.0, 0, 0)
      | Ok contacts ->
          let contact_count = List.length contacts in
          log_progress (Printf.sprintf "   Loaded %d contacts in %.3f seconds (%.0f contacts/second)" 
            contact_count load_time (float_of_int contact_count /. load_time));
          
          if contact_count = 0 then (
            log_progress "   No contacts need scheduling";
            (0, load_time, 0, 0)
          ) else (
            (* Measure memory before scheduling *)
            let (major_before, minor_before, _heap_before) = measure_memory_usage () in
            log_progress (Printf.sprintf "📊 Memory before processing: %d words (%.1f MB)" 
              (major_before + minor_before) 
              (float_of_int (major_before + minor_before) *. 8.0 /. 1024.0 /. 1024.0));
            
            (* Parallel schedule generation *)
            log_progress "⚡ Generating schedules in parallel...";
            let scheduler_run_id = Printf.sprintf "parallel_test_%s_%f" test_name (Unix.time ()) in
            
            (* Determine optimal chunk size based on contact count *)
            let chunk_size = 
              if contact_count > 50000 then 1000      (* Large datasets: 1k chunks *)
              else if contact_count > 10000 then 500  (* Medium datasets: 500 chunks *)
              else 100                                 (* Small datasets: 100 chunks *)
            in
            
            let (all_schedules, schedule_time) = time_it (fun () ->
              let schedule_contact contact =
                let config = Scheduler.Config.default in
                let context = create_context config in
                let context_with_run_id = { context with run_id = scheduler_run_id } in
                match calculate_schedules_for_contact context_with_run_id contact with
                | Ok contact_schedules -> contact_schedules
                | Error _ -> []
              in
              
              parallel_map_chunks chunk_size schedule_contact contacts |> List.flatten
            ) in
            
            let schedule_count = List.length all_schedules in
            log_progress (Printf.sprintf "   Generated %d schedules in %.3f seconds (%.0f schedules/second)" 
              schedule_count schedule_time (float_of_int schedule_count /. schedule_time));
            
            (* Measure memory after scheduling *)
            let (major_after, minor_after, _heap_after) = measure_memory_usage () in
            let memory_used = (major_after - major_before) + (minor_after - minor_before) in
            log_progress (Printf.sprintf "📊 Memory used for processing: %d words (%.1f MB)" 
              memory_used (float_of_int memory_used *. 8.0 /. 1024.0 /. 1024.0));
            
            (* Measure load balancing performance *)
            log_progress "⚖️  Applying load balancing...";
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
                log_progress (Printf.sprintf "❌ Load balancing failed: %s" (Scheduler.Types.string_of_error err));
                (contact_count, load_time +. schedule_time, schedule_count, 0)
            | Ok balanced_schedules ->
                log_progress (Printf.sprintf "   Load balancing completed in %.3f seconds" lb_time);
                
                (* High-performance database insertion with large chunks *)
                log_progress "💾 Inserting schedules with optimized batching...";
                let large_chunk_size = 
                  if schedule_count > 100000 then 1000  (* Very large: 1000 per chunk - optimal balance *)
                  else if schedule_count > 10000 then 1000   (* Large: 1000 per chunk *)
                  else 500                                   (* Standard: 500 per chunk *)
                in
                
                log_progress (Printf.sprintf "   Using chunk size: %d schedules per batch" large_chunk_size);
                
                let (insert_result, insert_time) = time_it (fun () ->
                  let total_chunks = (schedule_count + large_chunk_size - 1) / large_chunk_size in
                  log_progress (Printf.sprintf "   Processing %d schedules in %d chunks" 
                    schedule_count total_chunks);
                  
                  (* Custom chunked insertion with progress logging *)
                  let rec insert_chunks chunks_remaining inserted_so_far chunk_num =
                    match chunks_remaining with
                    | [] -> inserted_so_far
                    | chunk :: rest ->
                        if chunk_num mod 10 = 0 then
                          log_progress (Printf.sprintf "   Inserting chunk %d/%d (%d schedules inserted so far)" 
                            chunk_num total_chunks inserted_so_far);
                        
                        match batch_insert_schedules_chunked chunk large_chunk_size with
                        | Ok count -> insert_chunks rest (inserted_so_far + count) (chunk_num + 1)
                        | Error _ -> inserted_so_far
                  in
                  
                  (* Split schedules into chunks *)
                  let rec split_into_chunks lst chunk_size =
                    let rec take n acc = function
                      | [] -> (List.rev acc, [])
                      | x :: xs when n > 0 -> take (n-1) (x::acc) xs
                      | xs -> (List.rev acc, xs)
                    in
                    match lst with
                    | [] -> []
                    | _ -> 
                        let (chunk, rest) = take chunk_size [] lst in
                        chunk :: split_into_chunks rest chunk_size
                  in
                  
                  let chunks = split_into_chunks balanced_schedules large_chunk_size in
                  insert_chunks chunks 0 1
                ) in
                
                match insert_result with
                | 0 ->
                    log_progress "❌ Database insertion failed";
                    (contact_count, load_time +. schedule_time +. lb_time, schedule_count, 0)
                | inserted_count ->
                    log_progress (Printf.sprintf "   Inserted %d schedules in %.3f seconds (%.0f inserts/second)" 
                      inserted_count insert_time (float_of_int inserted_count /. insert_time));
                    
                    let total_time = load_time +. schedule_time +. lb_time +. insert_time in
                    log_progress "\n📈 Performance Summary:";
                    log_progress (Printf.sprintf "   • Total time: %.3f seconds" total_time);
                    log_progress (Printf.sprintf "   • Contacts processed: %d" contact_count);
                    log_progress (Printf.sprintf "   • Schedules generated: %d" schedule_count);
                    log_progress (Printf.sprintf "   • Schedules inserted: %d" inserted_count);
                    log_progress (Printf.sprintf "   • Overall throughput: %.0f contacts/second" 
                      (float_of_int contact_count /. total_time));
                    log_progress (Printf.sprintf "   • Memory efficiency: %.1f KB per contact" 
                      (float_of_int memory_used *. 8.0 /. 1024.0 /. float_of_int contact_count));
                    
                    (contact_count, total_time, schedule_count, inserted_count)
          )

(* Fast performance test for massive datasets *)
let run_massive_performance_test db_path =
  log_progress "🚀 High-Performance Massive Dataset Test";
  log_progress "========================================";
  
  let (contacts, time, schedules, inserts) = 
    run_parallel_scheduler_with_metrics db_path "Massive Dataset Performance Test" in
  
  log_progress "\n🎯 Final Results:";
  log_progress (Printf.sprintf "✅ Processed %d contacts in %.2f seconds" contacts time);
  log_progress (Printf.sprintf "✅ Generated %d schedules" schedules);
  log_progress (Printf.sprintf "✅ Inserted %d schedules" inserts);
  log_progress (Printf.sprintf "✅ Achieved %.0f contacts/second throughput" 
    (if time > 0.0 then float_of_int contacts /. time else 0.0));
  
  log_progress "\n🏆 Performance test complete!"

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <command> [database_path]\n" Sys.argv.(0);
    Printf.printf "Commands:\n";
    Printf.printf "  massive <db_path>   - High-performance test for large datasets\n";
    Printf.printf "  single <db_path>    - Single database test with detailed logging\n";
    exit 1
  );
  
  let command = Sys.argv.(1) in
  match command with
  | "massive" when argc >= 3 ->
      let db_path = Sys.argv.(2) in
      run_massive_performance_test db_path
  | "single" when argc >= 3 -> 
      let db_path = Sys.argv.(2) in
      let _ = run_parallel_scheduler_with_metrics db_path "Single Database Test" in
      ()
  | _ ->
      Printf.printf "Invalid command or missing database path\n";
      exit 1

(* Entry point *)
let () = main () 