open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Simple approach: Copy disk DB to memory, process in memory, write back *)

let copy_database_to_memory source_db_path =
  Printf.printf "📋 Copying database from %s to memory...\n%!" source_db_path;
  
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
      
      (* Step 2: Create memory database with basic schema *)
      let memory_start = Unix.gettimeofday () in
      set_db_path ":memory:";
      
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
      |} in
      
      (match execute_sql_no_result schema_sql with
       | Error err -> 
           Printf.printf "❌ Failed to create memory schema: %s\n" (string_of_db_error err);
           Error err
       | Ok () ->
           Printf.printf "✅ Created memory schema in %.3f seconds\n" 
             (Unix.gettimeofday () -. memory_start);
           
           (* Step 3: Insert contacts into memory *)
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
               Printf.printf "❌ Failed to insert into memory: %s\n" (string_of_db_error err);
               Error err
           | Ok count ->
               Printf.printf "✅ Inserted %d contacts into memory in %.3f seconds\n" 
                 count (Unix.gettimeofday () -. insert_start);
               Printf.printf "📊 Total memory setup: %.3f seconds\n" 
                 (Unix.gettimeofday () -. memory_start);
               Ok contacts)

let process_in_memory contacts test_name =
  Printf.printf "\n⚡ Processing %d contacts in memory...\n%!" (List.length contacts);
  let start_time = Unix.gettimeofday () in
  
  (* Generate schedules using in-memory database *)
  let config = Scheduler.Config.default in
  let scheduler_run_id = Printf.sprintf "inmem_%s_%f" test_name (Unix.time ()) in
  
  let total_schedules = ref 0 in
  List.iter (fun (contact : contact) ->
    let context = create_context config in
    let context_with_run_id = { context with run_id = scheduler_run_id } in
    match calculate_schedules_for_contact context_with_run_id contact with
    | Ok schedules -> total_schedules := !total_schedules + (List.length schedules)
    | Error _ -> ()
  ) contacts;
  
  let process_time = Unix.gettimeofday () -. start_time in
  Printf.printf "✅ Generated %d schedules in %.3f seconds\n" !total_schedules process_time;
  Printf.printf "📈 In-memory processing rate: %.0f contacts/second\n" 
    (float_of_int (List.length contacts) /. process_time);
  
  (!total_schedules, process_time)

let run_simple_inmemory_test source_db_path test_name =
  Printf.printf "🧠 Simple In-Memory Performance Test: %s\n" test_name;
  Printf.printf "===============================================\n";
  Printf.printf "Strategy: Copy to memory → Process in memory → Report results\n\n";
  
  let total_start = Unix.gettimeofday () in
  
  match copy_database_to_memory source_db_path with
  | Error err -> 
      Printf.printf "❌ Database copy failed: %s\n" (string_of_db_error err);
      (0, 0.0, 0)
  | Ok contacts ->
      let contact_count = List.length contacts in
      
      let (schedule_count, process_time) = process_in_memory contacts test_name in
      
      let total_time = Unix.gettimeofday () -. total_start in
      Printf.printf "\n🎉 IN-MEMORY TEST RESULTS:\n";
      Printf.printf "==========================\n";
      Printf.printf "• Total time: %.3f seconds\n" total_time;
      Printf.printf "• Contacts: %d\n" contact_count;
      Printf.printf "• Schedules: %d\n" schedule_count;
      Printf.printf "• Overall rate: %.0f contacts/second\n" 
        (float_of_int contact_count /. total_time);
      Printf.printf "• Pure processing rate: %.0f contacts/second\n" 
        (float_of_int contact_count /. process_time);
      Printf.printf "• Memory advantage: 100%% zero disk I/O during processing! 🚀\n";
      
      (contact_count, total_time, schedule_count)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.printf "Usage: %s <source_database_path> <test_name>\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_750k_test.db \"SimpleInMemory750K\"\n" Sys.argv.(0);
    exit 1
  );
  
  let source_db_path = Sys.argv.(1) in
  let test_name = Sys.argv.(2) in
  
  let _ = run_simple_inmemory_test source_db_path test_name in
  ()

let () = main ()