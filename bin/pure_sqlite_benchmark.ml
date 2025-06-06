open Scheduler.Db.Database

(* Pure SQLite insertion benchmark *)
let benchmark_pure_inserts count =
  Printf.printf "🚀 Pure SQLite Insertion Benchmark\n";
  Printf.printf "===================================\n";
  
  set_db_path "golden_dataset.sqlite3";
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err)
  | Ok () ->
      (* Apply PRAGMA optimizations *)
      let optimizations = [
        "PRAGMA synchronous = OFF";
        "PRAGMA journal_mode = MEMORY";
        "PRAGMA cache_size = 50000";
        "PRAGMA temp_store = MEMORY";
        "PRAGMA locking_mode = EXCLUSIVE";
      ] in
      
      List.iter (fun pragma ->
        match execute_sql_safe pragma with
        | Ok _ -> Printf.printf "✓ Applied: %s\n" pragma
        | Error _ -> Printf.printf "✗ Failed: %s\n" pragma
      ) optimizations;
      
      (* Test different batch sizes *)
      let batch_sizes = [1; 10; 50; 100; 500; 1000] in
      
      List.iter (fun batch_size ->
        Printf.printf "\n📊 Testing batch size: %d\n" batch_size;
        
        (* Clear test table *)
        let _ = execute_sql_safe "DELETE FROM email_schedules WHERE batch_id LIKE 'benchmark_%'" in
        
        let start_time = Unix.time () in
        
        (* Insert in batches *)
        let total_batches = (count + batch_size - 1) / batch_size in
        let inserted = ref 0 in
        
        for i = 0 to total_batches - 1 do
          let start_idx = i * batch_size in
          let end_idx = min (start_idx + batch_size) count in
          let chunk_size = end_idx - start_idx in
          
          if chunk_size > 0 then (
            (* Build batch VALUES statement *)
            let values_list = ref [] in
            for j = start_idx to end_idx - 1 do
              let value_tuple = Printf.sprintf "(%d, 'birthday', 2025, 12, 25, '2025-12-25', '09:00:00', 'pre-scheduled', '', 'benchmark_%d')"
                (j + 1) batch_size in
              values_list := value_tuple :: !values_list
            done;
            
            let batch_sql = Printf.sprintf {|
              INSERT INTO email_schedules (
                contact_id, email_type, event_year, event_month, event_day,
                scheduled_send_date, scheduled_send_time, status, skip_reason, batch_id
              ) VALUES %s
            |} (String.concat ", " (List.rev !values_list)) in
            
            match execute_sql_safe batch_sql with
            | Ok _ -> inserted := !inserted + chunk_size
            | Error err -> 
                Printf.printf "❌ Batch failed: %s\n" (string_of_db_error err);
          )
        done;
        
        let end_time = Unix.time () in
        let duration = end_time -. start_time in
        let throughput = float_of_int !inserted /. duration in
        
        Printf.printf "   Inserted: %d records\n" !inserted;
        Printf.printf "   Time: %.3f seconds\n" duration;
        Printf.printf "   Throughput: %.0f inserts/second\n" throughput;
      ) batch_sizes;
      
      (* Restore safety *)
      let _ = execute_sql_safe "PRAGMA synchronous = NORMAL" in
      let _ = execute_sql_safe "PRAGMA journal_mode = DELETE" in
      let _ = execute_sql_safe "PRAGMA locking_mode = NORMAL" in
      
      Printf.printf "\n✅ Benchmark complete!\n"

let () = 
  let count = 
    try
      if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 10000
    with Failure _ -> 10000
  in
  benchmark_pure_inserts count 