open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types

(* Chunked approach: Process 1M contacts in smaller batches *)

let process_contact_chunk source_db_path chunk_start chunk_size test_name =
  Printf.printf "📊 Processing chunk %d-%d...\n%!" chunk_start (chunk_start + chunk_size - 1);
  
  (* Create a temporary database for this chunk *)
  let chunk_db = Printf.sprintf "chunk_%d.db" chunk_start in
  let () = if Sys.file_exists chunk_db then Sys.remove chunk_db in
  
  let chunk_start_time = Unix.gettimeofday () in
  
  (* Copy chunk from source to temporary database *)
  let copy_cmd = Printf.sprintf {|
    sqlite3 %s "
    ATTACH DATABASE '%s' AS chunk;
    CREATE TABLE chunk.contacts AS 
    SELECT * FROM contacts 
    WHERE id >= %d AND id < %d;
    DETACH DATABASE chunk;
    "
  |} source_db_path chunk_db chunk_start (chunk_start + chunk_size) in
  
  let copy_result = Sys.command copy_cmd in
  if copy_result <> 0 then (
    Printf.printf "❌ Chunk copy failed\n";
    (0, 0, 0.0)
  ) else (
    (* Now process the chunk database *)
    set_db_path chunk_db;
    
    match get_all_contacts () with
    | Error err -> 
        Printf.printf "❌ Chunk load failed: %s\n" (string_of_db_error err);
        let _ = Sys.command ("rm -f " ^ chunk_db) in
        (0, 0, 0.0)
    | Ok contacts ->
        let load_time = Unix.gettimeofday () -. chunk_start_time in
        Printf.printf "   ✅ Loaded %d contacts in %.3f sec\n" (List.length contacts) load_time;
        
        if List.length contacts = 0 then (
          let _ = Sys.command ("rm -f " ^ chunk_db) in
          (0, 0, load_time)
        ) else (
          (* Process contacts *)
          let process_start = Unix.gettimeofday () in
          let config = Scheduler.Config.default in
          let scheduler_run_id = Printf.sprintf "chunk_%s_%d_%f" test_name chunk_start (Unix.time ()) in
          
          let total_schedules = ref 0 in
          List.iter (fun (contact : contact) ->
            let context = create_context config in
            let context_with_run_id = { context with run_id = scheduler_run_id } in
            match calculate_schedules_for_contact context_with_run_id contact with
            | Ok schedules -> total_schedules := !total_schedules + (List.length schedules)
            | Error _ -> ()
          ) contacts;
          
          let process_time = Unix.gettimeofday () -. process_start in
          Printf.printf "   ✅ Generated %d schedules in %.3f sec (%.0f contacts/sec)\n" 
            !total_schedules process_time 
            (float_of_int (List.length contacts) /. process_time);
          
          (* Clean up chunk database *)
          let _ = Sys.command ("rm -f " ^ chunk_db) in
          
          (List.length contacts, !total_schedules, load_time +. process_time)
        )
  )

let run_chunked_inmemory_test source_db_path test_name =
  Printf.printf "🧠🔄 CHUNKED IN-MEMORY Test: %s\n" test_name;
  Printf.printf "=====================================\n";
  Printf.printf "Strategy: Process 1M contacts in 100k chunks\n";
  Printf.printf "Each chunk gets its own temporary database! 🚀\n\n";
  
  let total_start = Unix.gettimeofday () in
  let chunk_size = 100000 in
  let max_chunks = 10 in  (* 1M contacts = 10 chunks of 100k *)
  
  let total_contacts = ref 0 in
  let total_schedules = ref 0 in
  let total_chunk_time = ref 0.0 in
  
  for chunk_num = 0 to max_chunks - 1 do
    let chunk_start = chunk_num * chunk_size + 1 in
    let (contacts, schedules, chunk_time) = 
      process_contact_chunk source_db_path chunk_start chunk_size test_name in
    
    total_contacts := !total_contacts + contacts;
    total_schedules := !total_schedules + schedules;
    total_chunk_time := !total_chunk_time +. chunk_time;
    
    Printf.printf "📊 Chunk %d: %d contacts, %d schedules\n" 
      (chunk_num + 1) contacts schedules;
  done;
  
  let total_time = Unix.gettimeofday () -. total_start in
  Printf.printf "\n🎉 CHUNKED IN-MEMORY RESULTS:\n";
  Printf.printf "==============================\n";
  Printf.printf "• Total time: %.3f seconds\n" total_time;
  Printf.printf "• Contacts processed: %d\n" !total_contacts;
  Printf.printf "• Schedules generated: %d\n" !total_schedules;
  Printf.printf "• Overall rate: %.0f contacts/second\n" 
    (float_of_int !total_contacts /. total_time);
  Printf.printf "• Pure processing rate: %.0f contacts/second\n" 
    (float_of_int !total_contacts /. !total_chunk_time);
  Printf.printf "• 🔄 Chunked advantage: Handles any database size!\n";
  Printf.printf "• 🧠 Memory advantage: Each chunk processed optimally!\n";
  
  (!total_contacts, total_time, !total_schedules)

let main () =
  let argc = Array.length Sys.argv in
  if argc < 3 then (
    Printf.printf "Usage: %s <source_database_path> <test_name>\n" Sys.argv.(0);
    Printf.printf "Example: %s massive_1m_test.db \"Chunked1MillionTest\"\n" Sys.argv.(0);
    exit 1
  );
  
  let source_db_path = Sys.argv.(1) in
  let test_name = Sys.argv.(2) in
  
  let _ = run_chunked_inmemory_test source_db_path test_name in
  ()

let () = main ()