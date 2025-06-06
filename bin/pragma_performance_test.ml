open Scheduler.Db.Database

let test_pragma_and_chunk_combinations () =
  Printf.printf "🚀 PRAGMA & Chunk Size Performance Test\n";
  Printf.printf "========================================\n";
  
  set_db_path "golden_dataset.sqlite3";
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err)
  | Ok () ->
      let test_count = 15000 in
      
      let journal_modes = [
        ("DELETE", "PRAGMA journal_mode = DELETE");
        ("MEMORY", "PRAGMA journal_mode = MEMORY");
        ("WAL", "PRAGMA journal_mode = WAL");
      ] in
      
      let chunk_sizes = [500; 1000; 2000; 5000] in
      
      List.iter (fun (mode_name, journal_pragma) ->
        Printf.printf "\n🔧 Testing Journal Mode: %s\n" mode_name;
        Printf.printf "================================\n";
        
        (* Apply journal mode *)
        let _ = execute_sql_safe journal_pragma in
        let _ = execute_sql_safe "PRAGMA synchronous = OFF" in
        let _ = execute_sql_safe "PRAGMA cache_size = 50000" in
        
        List.iter (fun chunk_size ->
          Printf.printf "\n📊 Chunk size: %d\n" chunk_size;
          
          (* Clear test data *)
          let test_id = Printf.sprintf "%s_%d" mode_name chunk_size in
          let _ = execute_sql_safe (Printf.sprintf "DELETE FROM email_schedules WHERE batch_id = 'test_%s'" test_id) in
          
          let start_time = Unix.time () in
          
          (* Insert in chunks *)
          let total_chunks = (test_count + chunk_size - 1) / chunk_size in
          let inserted = ref 0 in
          
          for i = 0 to total_chunks - 1 do
            let start_idx = i * chunk_size in
            let end_idx = min (start_idx + chunk_size) test_count in
            let current_chunk_size = end_idx - start_idx in
            
            if current_chunk_size > 0 then (
              (* Build multi-VALUES statement *)
              let values_list = ref [] in
              for j = start_idx to end_idx - 1 do
                let value_tuple = Printf.sprintf "(%d, 'test_%s', 2025, 6, %d, '2025-12-25', '09:00:00', 'pre-scheduled', '', 'test_%s')"
                  (3000000 + j) test_id (1 + (j mod 30)) test_id in
                values_list := value_tuple :: !values_list
              done;
              
              let batch_sql = Printf.sprintf {|
                INSERT INTO email_schedules (
                  contact_id, email_type, event_year, event_month, event_day,
                  scheduled_send_date, scheduled_send_time, status, skip_reason, batch_id
                ) VALUES %s
              |} (String.concat ", " (List.rev !values_list)) in
              
              match execute_sql_safe batch_sql with
              | Ok _ -> inserted := !inserted + current_chunk_size
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
          
        ) chunk_sizes;
        
      ) journal_modes;
      
      (* Restore defaults *)
      let _ = execute_sql_safe "PRAGMA synchronous = NORMAL" in
      let _ = execute_sql_safe "PRAGMA journal_mode = DELETE" in
      
      Printf.printf "\n✅ Performance comparison complete!\n"

let () = test_pragma_and_chunk_combinations () 