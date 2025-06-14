open Scheduler.Db.Database

let test_inmemory_creation () =
  Printf.printf "Testing in-memory database creation...\n";
  
  (* Test 1: Can we set memory path? *)
  set_db_path ":memory:";
  Printf.printf "✅ Set database path to :memory:\n";
  
  (* Test 2: Can we execute a simple query? *)
  (match execute_sql_no_result "CREATE TABLE test_table (id INTEGER PRIMARY KEY)" with
   | Error err -> Printf.printf "❌ Simple CREATE failed: %s\n" (string_of_db_error err)
   | Ok () -> Printf.printf "✅ Simple CREATE worked\n");
  
  (* Test 3: What happens with initialize_database? *)
  Printf.printf "Testing initialize_database...\n";
  (match initialize_database () with
   | Error err -> Printf.printf "❌ initialize_database failed: %s\n" (string_of_db_error err)
   | Ok () -> Printf.printf "✅ initialize_database worked\n");
  
  (* Test 4: Can we query the database? *)
  Printf.printf "Testing simple query...\n";
  (match execute_sql_safe "SELECT name FROM sqlite_master WHERE type='table'" with
   | Error err -> Printf.printf "❌ Query failed: %s\n" (string_of_db_error err)
   | Ok tables -> Printf.printf "✅ Found %d tables in memory database\n" (List.length tables))

let () = test_inmemory_creation ();;