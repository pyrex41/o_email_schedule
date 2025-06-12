open Scheduler.Email_scheduler
open Scheduler.Db.Database

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

(* Parallel schedule generation - optimal threading *)
let parallel_generate_schedules contacts scheduler_run_id contact_count =
  let num_threads = min 4 (max 1 (contact_count / 1000)) in  (* Optimal thread count *)
  let chunk_size = (List.length contacts + num_threads - 1) / num_threads in
  
  log_progress (Printf.sprintf "🧵 Parallelizing schedule generation: %d threads, ~%d contacts each" 
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
  
  (* Process each chunk in a separate thread *)
  List.iteri (fun i chunk ->
    let thread = Thread.create (fun () ->
      let thread_id = i + 1 in
      
      let thread_schedules = ref [] in
      List.iter (fun contact ->
        let config = Scheduler.Config.default in
        let context = create_context config in
        let context_with_run_id = { context with run_id = scheduler_run_id } in
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
  
  (* Combine results *)
  let all_schedules = Array.fold_left (fun acc schedules -> schedules @ acc) [] results in
  log_progress (Printf.sprintf "✅ Parallel generation complete: %d total schedules" (List.length all_schedules));
  all_schedules

(* Sequential database insertion with optimizations *)
let sequential_insert_schedules schedules =
  log_progress "💾 Sequential database insertion with WAL optimizations...";
  batch_insert_schedules_optimized schedules

(* Hybrid performance test - best of both worlds *)
let run_hybrid_performance_test db_path test_name =
  log_progress (Printf.sprintf "🚀 Starting hybrid performance test: %s" test_name);
  log_progress "=================================================";
  log_progress "Strategy: Parallel schedule generation + Sequential database insertion";
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      log_progress (Printf.sprintf "❌ Database initialization failed: %s" (string_of_db_error err));
      (0, 0.0, 0, 0)
  | Ok () ->
      (* Measure contact loading *)
      log_progress "📊 Loading contacts...";
      let (contacts_result, load_time) = time_it (fun () ->
        get_contacts_in_scheduling_window 60 14
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
            (* Measure memory before scheduling *)
            let (major_before, minor_before, _heap_before) = measure_memory_usage () in
            
            (* PARALLEL: Schedule generation *)
            log_progress "⚡ Generating schedules (parallel threads)...";
            let scheduler_run_id = Printf.sprintf "hybrid_test_%s_%f" test_name (Unix.time ()) in
            
            let (all_schedules, schedule_time) = time_it (fun () ->
              parallel_generate_schedules contacts scheduler_run_id contact_count
            ) in
            
            let schedule_count = List.length all_schedules in
            log_progress (Printf.sprintf "   Generated %d schedules in %.3f seconds" schedule_count schedule_time);
            log_progress (Printf.sprintf "   Throughput: %.0f schedules/second" 
              (float_of_int schedule_count /. schedule_time));
            
            (* Measure memory after scheduling *)
            let (major_after, minor_after, _heap_after) = measure_memory_usage () in
            let memory_used = (major_after - major_before) + (minor_after - minor_before) in
            log_progress (Printf.sprintf "   Memory used: %d words (%.1f MB)" 
              memory_used (float_of_int memory_used *. 8.0 /. 1024.0 /. 1024.0));
            
            (* Load balancing *)
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
                
                (* SEQUENTIAL: Database insertion with optimizations *)
                log_progress "💾 Inserting schedules (sequential with WAL)...";
                let (insert_result, insert_time) = time_it (fun () ->
                  sequential_insert_schedules balanced_schedules
                ) in
                
                match insert_result with
                | Error err ->
                    log_progress (Printf.sprintf "❌ Database insertion failed: %s" (string_of_db_error err));
                    (contact_count, load_time +. schedule_time +. lb_time, schedule_count, 0)
                | Ok inserted_count ->
                    log_progress (Printf.sprintf "   Inserted %d schedules in %.3f seconds" inserted_count insert_time);
                    log_progress (Printf.sprintf "   Throughput: %.0f inserts/second" 
                      (float_of_int inserted_count /. insert_time));
                    
                    let total_time = load_time +. schedule_time +. lb_time +. insert_time in
                    log_progress "";
                    log_progress "📈 HYBRID PERFORMANCE SUMMARY:";
                    log_progress "===============================";
                    log_progress (Printf.sprintf "   • Total time: %.3f seconds" total_time);
                    log_progress (Printf.sprintf "   • Contacts processed: %d" contact_count);
                    log_progress (Printf.sprintf "   • Schedules generated: %d" schedule_count);
                    log_progress (Printf.sprintf "   • Schedules inserted: %d" inserted_count);
                    log_progress (Printf.sprintf "   • Overall throughput: %.0f contacts/second" 
                      (float_of_int contact_count /. total_time));
                    log_progress (Printf.sprintf "   • Memory efficiency: %.1f KB per contact" 
                      (float_of_int memory_used *. 8.0 /. 1024.0 /. float_of_int contact_count));
                    log_progress "";
                    log_progress "🧠 OPTIMIZATION BREAKDOWN:";
                    log_progress (Printf.sprintf "   • Schedule generation: PARALLEL (%.1fx faster potential)" 
                      (float_of_int (min 4 (contact_count / 1000))));
                    log_progress "   • Database insertion: SEQUENTIAL + WAL (optimal for SQLite)";
                    log_progress "   • Result: Best of both worlds! 🎉";
                    
                    (contact_count, total_time, schedule_count, inserted_count)
          )

let main () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.printf "Usage: %s <database_path> <test_name>\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_test_dataset.sqlite3 \"500k Hybrid Test\"\n" Sys.argv.(0);
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  let test_name = Sys.argv.(2) in
  
  let _ = run_hybrid_performance_test db_path test_name in
  ()

let () = main () 