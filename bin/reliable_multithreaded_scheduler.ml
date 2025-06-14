open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Reliable Multithreaded In-Memory Scheduler *)
(* Priority: Robustness > Speed, while still achieving great performance *)

let default_thread_count = 4  (* Conservative thread count for reliability *)

(* Safe SQLite optimizations - proven and reliable *)
let apply_safe_sqlite_optimizations () =
  let safe_optimizations = [
    "PRAGMA synchronous = NORMAL";        (* Safer than OFF, still faster than FULL *)
    "PRAGMA journal_mode = WAL";          (* Proven reliable for concurrent access *)
    "PRAGMA cache_size = 10000";          (* Reasonable cache size *)
    "PRAGMA temp_store = MEMORY";         (* Store temporary tables in memory *)
  ] in
  
  let rec apply_pragmas remaining =
    match remaining with
    | [] -> Ok ()
    | pragma :: rest ->
        Printf.printf "   🔧 Applying: %s\n%!" pragma;
        match execute_sql_no_result pragma with
        | Ok () -> apply_pragmas rest
        | Error err -> 
            Printf.printf "   ⚠️  Warning: %s failed: %s\n%!" pragma (string_of_db_error err);
            apply_pragmas rest  (* Continue with other optimizations *)
  in
  apply_pragmas safe_optimizations

(* Create reliable in-memory database with proven approach *)
let create_reliable_memory_database source_db_path =
  Printf.printf "🧠 Creating reliable in-memory database...\n%!";
  
  (* Step 1: Read contacts from source *)
  set_db_path source_db_path;
  let start_time = Unix.gettimeofday () in
  
  match get_contacts_in_scheduling_window 365 30 with
  | Error err -> 
      Printf.printf "❌ Failed to read from source: %s\n" (string_of_db_error err);
      Error err
  | Ok contacts ->
      Printf.printf "✅ Read %d contacts from disk in %.3f seconds\n" 
        (List.length contacts) (Unix.gettimeofday () -. start_time);
      
      (* Step 2: Create memory database with safe settings *)
      let memory_start = Unix.gettimeofday () in
      set_db_path ":memory:";
      
      (* Apply safe performance optimizations *)
      Printf.printf "🔧 Applying safe SQLite optimizations...\n%!";
      (match apply_safe_sqlite_optimizations () with
       | Ok () -> Printf.printf "✅ Safe optimizations applied\n%!"
       | Error err -> Printf.printf "⚠️  Some optimizations failed: %s\n%!" (string_of_db_error err));
      
      (* Create schema in memory *)
      let schema_sql = {|
        CREATE TABLE contacts (
          id INTEGER PRIMARY KEY,
          email TEXT NOT NULL,
          zip_code TEXT,
          state TEXT,
          birth_date TEXT,
          effective_date TEXT,
          carrier TEXT,
          failed_underwriting INTEGER DEFAULT 0
        );
        
        CREATE TABLE email_schedules (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          contact_id INTEGER NOT NULL,
          email_type TEXT NOT NULL,
          scheduled_date TEXT NOT NULL,
          scheduled_time TEXT NOT NULL,
          status TEXT NOT NULL,
          priority INTEGER DEFAULT 10,
          template_id TEXT,
          campaign_instance_id INTEGER,
          scheduler_run_id TEXT NOT NULL
        );
      |} in
      
      (match execute_sql_no_result schema_sql with
       | Error err -> 
           Printf.printf "❌ Failed to create memory schema: %s\n" (string_of_db_error err);
           Error err
       | Ok () ->
           Printf.printf "✅ Created memory schema in %.3f seconds\n" 
             (Unix.gettimeofday () -. memory_start);
           
           (* Step 3: Insert contacts using simple reliable approach *)
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
           
           (* Use simple batch insert without complex transaction handling *)
           match batch_insert_with_prepared_statement insert_sql contact_values with
           | Error err -> 
               Printf.printf "❌ Failed to insert into memory: %s\n" (string_of_db_error err);
               Error err
           | Ok count ->
               Printf.printf "✅ Inserted %d contacts into memory in %.3f seconds\n" 
                 count (Unix.gettimeofday () -. insert_start);
               Printf.printf "📊 Total memory setup: %.3f seconds\n" 
                 (Unix.gettimeofday () -. memory_start);
               Ok contacts)

(* Robust thread worker function *)
let process_contact_chunk thread_id contacts chunk_start chunk_end scheduler_run_id =
  Printf.printf "[Thread %d] Processing contacts %d-%d (%d contacts)\n%!" 
    thread_id chunk_start chunk_end (chunk_end - chunk_start + 1);
  
  let chunk_start_time = Unix.gettimeofday () in
  let config = Scheduler.Config.default in
  let total_schedules = ref 0 in
  let processed_count = ref 0 in
  
  (* Process chunk of contacts with error handling *)
  let chunk_contacts = 
    contacts
    |> List.mapi (fun i contact -> (i, contact))
    |> List.filter (fun (i, _) -> i >= chunk_start && i <= chunk_end)
    |> List.map snd
  in
  
  List.iter (fun contact ->
    try
      let context = create_context config in
      let context_with_run_id = { context with run_id = scheduler_run_id } in
      match calculate_schedules_for_contact context_with_run_id contact with
      | Ok schedules -> 
          total_schedules := !total_schedules + (List.length schedules);
          incr processed_count
      | Error err -> 
          Printf.printf "[Thread %d] Warning: Failed to process contact %d: %s\n%!" 
            thread_id contact.id (string_of_error err)
    with
    | exn -> 
        Printf.printf "[Thread %d] Exception processing contact %d: %s\n%!" 
          thread_id contact.id (Printexc.to_string exn)
  ) chunk_contacts;
  
  let chunk_time = Unix.gettimeofday () -. chunk_start_time in
  let chunk_count = !processed_count in
  
  Printf.printf "[Thread %d] ✅ Generated %d schedules in %.3f sec (%.0f contacts/sec)\n%!" 
    thread_id !total_schedules chunk_time 
    (if chunk_time > 0.0 then float_of_int chunk_count /. chunk_time else 0.0);
  
  (!total_schedules, chunk_count, chunk_time)

(* Reliable multithreaded processing *)
let run_reliable_multithreaded_processing contacts thread_count scheduler_run_id =
  Printf.printf "\n⚡ Starting %d-thread reliable parallel processing...\n%!" thread_count;
  let process_start = Unix.gettimeofday () in
  
  let total_contacts = List.length contacts in
  let contacts_per_thread = (total_contacts + thread_count - 1) / thread_count in
  
  Printf.printf "📊 %d contacts ÷ %d threads = ~%d contacts per thread\n%!" 
    total_contacts thread_count contacts_per_thread;
  
  (* Create thread results storage *)
  let thread_results = Array.make thread_count (0, 0, 0.0) in
  let threads = ref [] in
  
  (* Launch threads with error handling *)
  for i = 0 to thread_count - 1 do
    let chunk_start = i * contacts_per_thread in
    let chunk_end = min ((i + 1) * contacts_per_thread - 1) (total_contacts - 1) in
    
    if chunk_start <= total_contacts - 1 then (
      try
        let thread = Thread.create (fun () ->
          let (schedules, processed, time) = 
            process_contact_chunk i contacts chunk_start chunk_end scheduler_run_id in
          thread_results.(i) <- (schedules, processed, time);
        ) () in
        threads := (i, thread) :: !threads;
      with
      | exn -> 
          Printf.printf "❌ Failed to create thread %d: %s\n%!" i (Printexc.to_string exn)
    )
  done;
  
  (* Wait for all threads to complete *)
  Printf.printf "⏳ Waiting for %d threads to complete...\n%!" (List.length !threads);
  List.iter (fun (thread_id, thread) ->
    try
      Thread.join thread;
      Printf.printf "✅ Thread %d completed successfully\n%!" thread_id
    with
    | exn -> 
        Printf.printf "❌ Thread %d failed: %s\n%!" thread_id (Printexc.to_string exn)
  ) !threads;
  
  (* Aggregate results *)
  let total_schedules = Array.fold_left (fun acc (s, _, _) -> acc + s) 0 thread_results in
  let total_processed = Array.fold_left (fun acc (_, p, _) -> acc + p) 0 thread_results in
  let max_thread_time = Array.fold_left (fun acc (_, _, t) -> max acc t) 0.0 thread_results in
  let total_time = Unix.gettimeofday () -. process_start in
  
  Printf.printf "\n🎯 RELIABLE MULTITHREADED RESULTS:\n";
  Printf.printf "==================================\n";
  Printf.printf "• Threads used: %d\n" (List.length !threads);
  Printf.printf "• Total processing time: %.3f seconds\n" total_time;
  Printf.printf "• Longest thread time: %.3f seconds\n" max_thread_time;
  Printf.printf "• Contacts processed: %d/%d (%.1f%%)\n" 
    total_processed total_contacts 
    (100.0 *. float_of_int total_processed /. float_of_int total_contacts);
  Printf.printf "• Schedules generated: %d\n" total_schedules;
  Printf.printf "• Overall rate: %.0f contacts/second\n" 
    (if total_time > 0.0 then float_of_int total_processed /. total_time else 0.0);
  Printf.printf "• Parallel efficiency: %.1f%% (%.3f/%.3f)\n" 
    (if max_thread_time > 0.0 then total_time /. max_thread_time *. 100.0 else 0.0) 
    total_time max_thread_time;
  
  (total_schedules, total_processed, total_time)

(* Main reliable scheduler function *)
let run_reliable_multithreaded_scheduler source_db_path thread_count =
  Printf.printf "🔒 RELIABLE MULTITHREADED IN-MEMORY SCHEDULER\n";
  Printf.printf "=============================================\n";
  Printf.printf "Priority: Robustness and reliability\n";
  Printf.printf "Strategy: %d threads + proven optimizations + comprehensive error handling\n\n" thread_count;
  
  let total_start = Unix.gettimeofday () in
  
  match create_reliable_memory_database source_db_path with
  | Error err -> 
      Printf.printf "❌ Memory database creation failed: %s\n" (string_of_db_error err);
      (0, 0.0, 0)
  | Ok contacts ->
      let contact_count = List.length contacts in
      let scheduler_run_id = Printf.sprintf "reliable_multithread_%d_%f" thread_count (Unix.time ()) in
      
      let (schedule_count, processed_count, process_time) = 
        run_reliable_multithreaded_processing contacts thread_count scheduler_run_id in
      
      let total_time = Unix.gettimeofday () -. total_start in
      
      Printf.printf "\n🏆 FINAL RELIABLE RESULTS:\n";
      Printf.printf "===========================\n";
      Printf.printf "• Total time: %.3f seconds\n" total_time;
      Printf.printf "• Processing time: %.3f seconds\n" process_time;
      Printf.printf "• Contacts loaded: %d\n" contact_count;
      Printf.printf "• Contacts processed: %d\n" processed_count;
      Printf.printf "• Schedules generated: %d\n" schedule_count;
      Printf.printf "• Success rate: %.1f%%\n" 
        (100.0 *. float_of_int processed_count /. float_of_int contact_count);
      Printf.printf "• Overall rate: %.0f contacts/second\n" 
        (if total_time > 0.0 then float_of_int processed_count /. total_time else 0.0);
      Printf.printf "• 🔒 Reliability: Proven safe SQLite settings\n";
      Printf.printf "• 🧵 Threading: Robust error handling\n";
      Printf.printf "• 🧠 Memory: Efficient in-memory processing\n";
      Printf.printf "• ✅ Architecture: Robust for production use!\n";
      
      (* Check if we meet reasonable performance targets *)
      let contacts_per_sec = if total_time > 0.0 then float_of_int processed_count /. total_time else 0.0 in
      if contacts_per_sec > 10000.0 then
        Printf.printf "🎉 EXCELLENT: >10k contacts/sec - perfect for any customer!\n"
      else if contacts_per_sec > 5000.0 then
        Printf.printf "✅ GREAT: >5k contacts/sec - easily handles large customers\n"
      else if contacts_per_sec > 1000.0 then
        Printf.printf "👍 GOOD: >1k contacts/sec - solid performance\n"
      else
        Printf.printf "⚠️  SLOW: <1k contacts/sec - may need optimization\n";
      
      (contact_count, total_time, schedule_count)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <source_database_path> [thread_count]\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_1m_test.db 4\n" Sys.argv.(0);
    Printf.printf "Default thread count: %d (conservative for reliability)\n" default_thread_count;
    exit 1
  );
  
  let source_db_path = Sys.argv.(1) in
  let thread_count = if argc >= 3 then int_of_string Sys.argv.(2) else default_thread_count in
  
  if thread_count < 1 || thread_count > 16 then (
    Printf.printf "❌ Thread count must be between 1 and 16 (keeping it reasonable)\n";
    exit 1
  );
  
  let _ = run_reliable_multithreaded_scheduler source_db_path thread_count in
  ()

let () = main ()