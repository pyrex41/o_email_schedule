open Scheduler.Db.Database

let test_inmemory_creation () =
  Printf.printf "Testing in-memory database creation...\n";
  
  (* Test 1: Can we set memory path? *)
  set_db_path ":memory:";
  Printf.printf "✅ Set database path to :memory:\n";
  
  (* Test 2: Can we get a connection? *)
  (match get_db_connection () with
   | Error err -> Printf.printf "❌ Connection failed: %s\n" (string_of_db_error err)
   | Ok _db -> Printf.printf "✅ Got in-memory database connection\n");
  
  (* Test 3: Can we execute a simple query? *)
  (match execute_sql_no_result "CREATE TABLE test_table (id INTEGER PRIMARY KEY)" with
   | Error err -> Printf.printf "❌ Simple CREATE failed: %s\n" (string_of_db_error err)
   | Ok () -> Printf.printf "✅ Simple CREATE worked\n");
  
  (* Test 4: What happens with initialize_database? *)
  Printf.printf "Testing initialize_database...\n";
  (match initialize_database () with
   | Error err -> Printf.printf "❌ initialize_database failed: %s\n" (string_of_db_error err)
   | Ok () -> Printf.printf "✅ initialize_database worked\n");

let () = test_inmemory_creation ()