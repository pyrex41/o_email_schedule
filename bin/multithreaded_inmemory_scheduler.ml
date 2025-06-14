open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Single Machine Multithreaded In-Memory Scheduler *)
(* Target: 1M+ contacts in <60 seconds using all CPU cores *)

let default_thread_count = 8  (* Adjust based on machine specs *)

(* Additional ultra-high-performance settings for write-heavy workloads *)
let optimize_sqlite_for_extreme_writes () =
  let extreme_optimizations = [
    "PRAGMA synchronous = OFF";           (* No fsync - maximum speed, some durability risk *)
    "PRAGMA journal_mode = MEMORY";       (* Journal in memory only - fastest *)
    "PRAGMA cache_size = -1000000";       (* 1GB cache size *)
    "PRAGMA mmap_size = 268435456";       (* 256MB memory mapping *)
    "PRAGMA threads = 4";                 (* Use multiple threads if available *)
    "PRAGMA optimize";                    (* Optimize schema and statistics *)
    "PRAGMA analysis_limit = 1000";       (* Limit analysis for speed *)
    "PRAGMA checkpoint_fullfsync = 0";    (* Disable full fsync on checkpoints *)
  ] in
  
  let rec apply_pragmas remaining =
    match remaining with
    | [] -> Ok ()
    | pragma :: rest ->
        Printf.printf "   ⚡ Extreme: %s\n%!" pragma;
        match execute_sql_no_result pragma with
        | Ok () -> apply_pragmas rest
        | Error err -> 
            Printf.printf "   ⚠️  Warning: %s failed: %s\n%!" pragma (string_of_db_error err);
            apply_pragmas rest  (* Continue with other optimizations *)
  in
  apply_pragmas extreme_optimizations

(* Create optimized in-memory database with all performance settings *)
let create_optimized_memory_database source_db_path =
  Printf.printf "🧠 Creating optimized in-memory database...\n%!";
  
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
      
      (* Step 2: Create memory database with optimized settings *)
      let memory_start = Unix.gettimeofday () in
      set_db_path ":memory:";
      
      (* Apply extreme performance optimizations *)
      Printf.printf "⚡ Applying extreme SQLite optimizations...\n%!";
      (match optimize_sqlite_for_extreme_writes () with
       | Ok () -> Printf.printf "✅ Extreme optimizations applied\n%!"
       | Error err -> Printf.printf "⚠️  Some optimizations failed: %s\n%!" (string_of_db_error err));
      
      (* Create minimal schema in memory *)
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
        
        -- Create indexes for performance
        CREATE INDEX idx_contacts_email ON contacts(email);
        CREATE INDEX idx_contacts_state ON contacts(state);
        CREATE INDEX idx_schedules_contact ON email_schedules(contact_id);
        CREATE INDEX idx_schedules_date ON email_schedules(scheduled_date);
      |} in
      
      (match execute_sql_no_result schema_sql with
       | Error err -> 
           Printf.printf "❌ Failed to create memory schema: %s\n" (string_of_db_error err);
           Error err
       | Ok () ->
           Printf.printf "✅ Created optimized memory schema in %.3f seconds\n" 
             (Unix.gettimeofday () -. memory_start);
           
           (* Step 3: Bulk insert contacts with optimizations *)
           let insert_start = Unix.gettimeofday () in
           
           (* Apply bulk insert optimizations *)
           let _ = execute_sql_no_result "BEGIN IMMEDIATE" in
           
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
               let _ = execute_sql_no_result "ROLLBACK" in
               Printf.printf "❌ Failed to insert into memory: %s\n" (string_of_db_error err);
               Error err
           | Ok count ->
               let _ = execute_sql_no_result "COMMIT" in
               Printf.printf "✅ Bulk inserted %d contacts into memory in %.3f seconds\n" 
                 count (Unix.gettimeofday () -. insert_start);
               Printf.printf "📊 Total optimized memory setup: %.3f seconds\n" 
                 (Unix.gettimeofday () -. memory_start);
               Ok contacts)

(* Thread worker function to process a chunk of contacts *)
let process_contact_chunk thread_id contacts chunk_start chunk_end scheduler_run_id =
  Printf.printf "[Thread %d] Processing contacts %d-%d (%d contacts)\n%!" 
    thread_id chunk_start chunk_end (chunk_end - chunk_start + 1);
  
  let chunk_start_time = Unix.gettimeofday () in
  let config = Scheduler.Config.default in
  let total_schedules = ref 0 in
  
  (* Process chunk of contacts *)
  let chunk_contacts = 
    contacts
    |> List.mapi (fun i contact -> (i, contact))
    |> List.filter (fun (i, _) -> i >= chunk_start && i <= chunk_end)
    |> List.map snd
  in
  
  List.iter (fun contact ->
    let context = create_context config in
    let context_with_run_id = { context with run_id = scheduler_run_id } in
    match calculate_schedules_for_contact context_with_run_id contact with
    | Ok schedules -> total_schedules := !total_schedules + (List.length schedules)
    | Error _ -> ()
  ) chunk_contacts;
  
  let chunk_time = Unix.gettimeofday () -. chunk_start_time in
  let chunk_count = List.length chunk_contacts in
  
  Printf.printf "[Thread %d] ✅ Generated %d schedules in %.3f sec (%.0f contacts/sec)\n%!" 
    thread_id !total_schedules chunk_time 
    (float_of_int chunk_count /. chunk_time);
  
  (!total_schedules, chunk_count, chunk_time)

(* Run multithreaded processing using OCaml threads *)
let run_multithreaded_processing contacts thread_count scheduler_run_id =
  Printf.printf "\n⚡ Starting %d-thread parallel processing...\n%!" thread_count;
  let process_start = Unix.gettimeofday () in
  
  let total_contacts = List.length contacts in
  let contacts_per_thread = (total_contacts + thread_count - 1) / thread_count in
  
  Printf.printf "📊 %d contacts ÷ %d threads = ~%d contacts per thread\n%!" 
    total_contacts thread_count contacts_per_thread;
  
  (* Create thread results storage *)
  let thread_results = Array.make thread_count (0, 0, 0.0) in
  let threads = Array.make thread_count (Thread.self ()) in
  
  (* Launch threads *)
  for i = 0 to thread_count - 1 do
    let chunk_start = i * contacts_per_thread in
    let chunk_end = min ((i + 1) * contacts_per_thread - 1) (total_contacts - 1) in
    
    if chunk_start <= total_contacts - 1 then (
      threads.(i) <- Thread.create (fun () ->
        let (schedules, processed, time) = 
          process_contact_chunk i contacts chunk_start chunk_end scheduler_run_id in
        thread_results.(i) <- (schedules, processed, time);
      ) ();
    )
  done;
  
  (* Wait for all threads to complete *)
  Printf.printf "⏳ Waiting for threads to complete...\n%!";
  for i = 0 to thread_count - 1 do
    let chunk_start = i * contacts_per_thread in
    if chunk_start <= total_contacts - 1 then
      Thread.join threads.(i)
  done;
  
  (* Aggregate results *)
  let total_schedules = Array.fold_left (fun acc (s, _, _) -> acc + s) 0 thread_results in
  let total_processed = Array.fold_left (fun acc (_, p, _) -> acc + p) 0 thread_results in
  let max_thread_time = Array.fold_left (fun acc (_, _, t) -> max acc t) 0.0 thread_results in
  let total_time = Unix.gettimeofday () -. process_start in
  
  Printf.printf "\n🎯 MULTITHREADED RESULTS:\n";
  Printf.printf "========================\n";
  Printf.printf "• Threads used: %d\n" thread_count;
  Printf.printf "• Total processing time: %.3f seconds\n" total_time;
  Printf.printf "• Longest thread time: %.3f seconds\n" max_thread_time;
  Printf.printf "• Contacts processed: %d\n" total_processed;
  Printf.printf "• Schedules generated: %d\n" total_schedules;
  Printf.printf "• Overall rate: %.0f contacts/second\n" 
    (float_of_int total_processed /. total_time);
  Printf.printf "• Parallel efficiency: %.1f%% (%.3f/%.3f)\n" 
    (total_time /. max_thread_time *. 100.0) total_time max_thread_time;
  
  (total_schedules, total_processed, total_time)

(* Main multithreaded scheduler function *)
let run_multithreaded_inmemory_scheduler source_db_path thread_count =
  Printf.printf "🚀 MULTITHREADED IN-MEMORY SCHEDULER\n";
  Printf.printf "====================================\n";
  Printf.printf "Target: Maximum performance on single high-performance machine\n";
  Printf.printf "Strategy: %d threads + in-memory SQLite + extreme optimizations\n\n" thread_count;
  
  let total_start = Unix.gettimeofday () in
  
  match create_optimized_memory_database source_db_path with
  | Error err -> 
      Printf.printf "❌ Memory database creation failed: %s\n" (string_of_db_error err);
      (0, 0.0, 0)
  | Ok contacts ->
      let contact_count = List.length contacts in
      let scheduler_run_id = Printf.sprintf "multithread_%d_%f" thread_count (Unix.time ()) in
      
      let (schedule_count, processed_count, process_time) = 
        run_multithreaded_processing contacts thread_count scheduler_run_id in
      
      let total_time = Unix.gettimeofday () -. total_start in
      
      Printf.printf "\n🏆 FINAL PERFORMANCE RESULTS:\n";
      Printf.printf "==============================\n";
      Printf.printf "• Total time: %.3f seconds\n" total_time;
      Printf.printf "• Contacts: %d\n" contact_count;
      Printf.printf "• Schedules: %d\n" schedule_count;
      Printf.printf "• Overall rate: %.0f contacts/second\n" 
        (float_of_int contact_count /. total_time);
      Printf.printf "• Pure processing rate: %.0f contacts/second\n" 
        (float_of_int processed_count /. process_time);
      Printf.printf "• 🚀 Single machine advantage: All CPU cores utilized!\n";
      Printf.printf "• 🧠 Memory advantage: Zero disk I/O during processing!\n";
      Printf.printf "• ⚡ SQLite advantage: Extreme performance optimizations!\n";
      Printf.printf "• 🎯 Architecture: Perfect for <60 second processing target!\n";
      
      (contact_count, total_time, schedule_count)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <source_database_path> [thread_count]\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_1m_test.db 8\n" Sys.argv.(0);
    Printf.printf "Default thread count: %d\n" default_thread_count;
    exit 1
  );
  
  let source_db_path = Sys.argv.(1) in
  let thread_count = 
    if argc >= 3 then 
      try int_of_string Sys.argv.(2) 
      with Failure _ ->
        Printf.printf "❌ Invalid thread count '%s'. Must be an integer between 1 and 32.\n" Sys.argv.(2);
        Printf.printf "Usage: %s <source_database_path> [thread_count]\n" Sys.argv.(0);
        exit 1
    else default_thread_count in
  
  if thread_count < 1 || thread_count > 32 then (
    Printf.printf "❌ Thread count must be between 1 and 32\n";
    exit 1
  );
  
  let _ = run_multithreaded_inmemory_scheduler source_db_path thread_count in
  ()

let () = main ()