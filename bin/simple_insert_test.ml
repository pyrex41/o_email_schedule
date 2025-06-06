open Scheduler.Db.Database

let test_raw_performance () =
  Printf.printf "🚀 Simple SQLite Performance Test\n";
  Printf.printf "==================================\n";
  
  set_db_path "golden_dataset.sqlite3";
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err)
  | Ok () ->
      (* Test 1: Current performance with our existing approach *)
      Printf.printf "\n📊 Test 1: Current approach (2000 per batch)\n";
      let start_time = Unix.time () in
      let _ = execute_sql_safe "DELETE FROM email_schedules WHERE batch_id = 'test_current'" in
      
      (* Generate 15,000 test records using current approach *)
      let records = ref [] in
      for i = 1 to 15000 do
        let record = Printf.sprintf "(%d, 'test_email', 2025, 6, %d, '2025-12-25', '09:00:00', 'pre-scheduled', '', 'test_current')"
          (1000000 + i) (1 + (i mod 30)) in
        records := record :: !records;
        
        (* Insert in batches of 2000 like our optimized version *)
        if i mod 2000 = 0 || i = 15000 then (
          let batch_sql = Printf.sprintf {|
            INSERT INTO email_schedules (
              contact_id, email_type, event_year, event_month, event_day,
              scheduled_send_date, scheduled_send_time, status, skip_reason, batch_id
            ) VALUES %s
          |} (String.concat ", " !records) in
          
          let _ = execute_sql_safe batch_sql in
          records := []
        )
      done;
      
      let end_time = Unix.time () in
      let duration = end_time -. start_time in
      Printf.printf "   Time: %.3f seconds\n" duration;
      Printf.printf "   Throughput: %.0f inserts/second\n" (15000.0 /. duration);
      
      (* Test 2: Apply PRAGMA optimizations *)
      Printf.printf "\n📊 Test 2: With PRAGMA optimizations\n";
      let _ = execute_sql_safe "PRAGMA synchronous = OFF" in
      let _ = execute_sql_safe "PRAGMA journal_mode = MEMORY" in
      let _ = execute_sql_safe "PRAGMA cache_size = 50000" in
      
      let start_time2 = Unix.time () in
      let _ = execute_sql_safe "DELETE FROM email_schedules WHERE batch_id = 'test_pragma'" in
      
      let records = ref [] in
      for i = 1 to 15000 do
        let record = Printf.sprintf "(%d, 'test_email', 2025, 6, %d, '2025-12-25', '09:00:00', 'pre-scheduled', '', 'test_pragma')"
          (2000000 + i) (1 + (i mod 30)) in
        records := record :: !records;
        
        if i mod 2000 = 0 || i = 15000 then (
          let batch_sql = Printf.sprintf {|
            INSERT INTO email_schedules (
              contact_id, email_type, event_year, event_month, event_day,
              scheduled_send_date, scheduled_send_time, status, skip_reason, batch_id
            ) VALUES %s
          |} (String.concat ", " !records) in
          
          let _ = execute_sql_safe batch_sql in
          records := []
        )
      done;
      
      let end_time2 = Unix.time () in
      let duration2 = end_time2 -. start_time2 in
      Printf.printf "   Time: %.3f seconds\n" duration2;
      Printf.printf "   Throughput: %.0f inserts/second\n" (15000.0 /. duration2);
      Printf.printf "   Improvement: %.1fx faster\n" (duration /. duration2);
      
      (* Restore normal settings *)
      let _ = execute_sql_safe "PRAGMA synchronous = NORMAL" in
      let _ = execute_sql_safe "PRAGMA journal_mode = DELETE" in
      
      Printf.printf "\n✅ Performance test complete!\n"

let () = test_raw_performance () 