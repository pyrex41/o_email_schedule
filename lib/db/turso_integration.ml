(* Enhanced Turso Integration using Rust FFI *)
(* This replaces the copy/diff workflow with direct libSQL access via Rust FFI *)

(* Use the new FFI module *)
open Turso_ffi

let working_database_path = "working_copy.db"

(* Initialize and get connection using FFI *)
let get_connection () =
  match Turso_ffi.get_database_connection () with
  | Ok _msg -> Ok "Connected via Turso FFI"
  | Error err -> Error (Database_native.ConnectionError (Turso_ffi.string_of_db_error err))

(* Check if initialized *)
let is_initialized () = Turso_ffi.is_initialized ()

(* Execute SQL safely using FFI *)
let execute_sql_safe sql =
  match Turso_ffi.execute_sql_safe sql with
  | Ok results -> Ok results
  | Error err -> Error (Database_native.SqliteError (Turso_ffi.string_of_db_error err))

(* Execute SQL without result using FFI *)
let execute_sql_no_result sql =
  match Turso_ffi.execute_sql_no_result sql with
  | Ok () -> Ok ()
  | Error err -> Error (Database_native.SqliteError (Turso_ffi.string_of_db_error err))

(* Enhanced example query with FFI *)
let example_query () =
  match get_connection () with
  | Error err -> 
    Printf.eprintf "Database connection failed: %s\n" (Database_native.string_of_db_error err);
    Lwt.return_unit
  | Ok _db ->
    match execute_sql_safe "SELECT COUNT(*) FROM email_schedules" with
    | Ok [[count]] -> 
      Printf.printf "📊 Email schedules count (via FFI): %s\n" count;
      Lwt.return_unit
    | Ok _ -> 
      Printf.printf "Unexpected query result format\n";
      Lwt.return_unit
    | Error err -> 
      Printf.eprintf "Query failed: %s\n" (Database_native.string_of_db_error err);
      Lwt.return_unit

(* Enhanced sync check - no manual sync needed with FFI *)
let suggest_sync_check () =
  Printf.printf "\n✨ Using Turso FFI - Real-time sync enabled!\n";
  Printf.printf "📊 Connection status: %s\n" 
    (if is_initialized () then "Connected" else "Not connected");
  Turso_ffi.suggest_sync_check ()

(* Print enhanced sync instructions *)
let print_sync_instructions () =
  Turso_ffi.print_sync_instructions ();
  Printf.printf "🚀 Quick start:\n";
  Printf.printf "   1. Set TURSO_DATABASE_URL and TURSO_AUTH_TOKEN\n";
  Printf.printf "   2. Run your OCaml application\n";
  Printf.printf "   3. Database changes auto-sync to Turso!\n\n%!"

(* Enhanced batch insert using FFI *)
let batch_insert_schedules schedules current_run_id =
  match Turso_ffi.smart_batch_insert_schedules schedules current_run_id with
  | Ok affected_rows -> 
    Printf.printf "✅ FFI batch insert successful: %d rows\n%!" affected_rows;
    Ok affected_rows
  | Error err -> 
    Printf.eprintf "❌ FFI batch insert failed: %s\n%!" (Turso_ffi.string_of_db_error err);
    Error (Database_native.SqliteError (Turso_ffi.string_of_db_error err))

(* Shutdown cleanup *)
let shutdown () = Turso_ffi.shutdown ()

(* Advanced FFI features *)

(* Direct sync control *)
let manual_sync () =
  match Turso_ffi.sync_database () with
  | Ok () -> 
    Printf.printf "✅ Manual sync completed\n%!";
    Ok ()
  | Error err -> 
    Printf.eprintf "❌ Manual sync failed: %s\n%!" (Turso_ffi.string_of_db_error err);
    Error (Database_native.SyncError (Turso_ffi.string_of_db_error err))

(* Execute batch transactions *)
let execute_transaction statements =
  match Turso_ffi.execute_batch statements with
  | Ok affected_rows ->
    Printf.printf "✅ Transaction completed: %d rows affected\n%!" affected_rows;
    Ok affected_rows
  | Error err ->
    Printf.eprintf "❌ Transaction failed: %s\n%!" (Turso_ffi.string_of_db_error err);
    Error (Database_native.SqliteError (Turso_ffi.string_of_db_error err))

(* Get database statistics *)
let get_database_stats () =
  let connection_count = Turso_ffi.connection_count () in
  Printf.printf "📊 Database Statistics:\n";
  Printf.printf "   • Active connections: %d\n" connection_count;
  Printf.printf "   • FFI initialized: %s\n" (if is_initialized () then "Yes" else "No");
  Printf.printf "   • Sync mode: Real-time via libSQL\n%!";
  connection_count

(* Compatibility layer for existing code *)

(* For Database_native compatibility *)
let get_db_connection = get_connection
let string_of_db_error = function
  | Database_native.SqliteError msg -> "SQLite error: " ^ msg
  | Database_native.ParseError msg -> "Parse error: " ^ msg  
  | Database_native.ConnectionError msg -> "Connection error: " ^ msg

(* High-level scheduler integration *)
let prepare_for_scheduling () =
  Printf.printf "🎯 Preparing Turso FFI for scheduling...\n%!";
  match get_connection () with
  | Ok _conn -> 
    (* Ensure we have latest data *)
    (match manual_sync () with
     | Ok () -> 
       Printf.printf "✅ Ready for scheduling with latest data\n%!";
       Ok ()
     | Error err -> Error err)
  | Error err -> Error err

let finalize_scheduling affected_rows =
  Printf.printf "🏁 Finalizing scheduling (%d schedules)...\n%!" affected_rows;
  (* Auto-sync happens automatically with FFI, but we can force one for confirmation *)
  match manual_sync () with
  | Ok () -> 
    Printf.printf "✅ All changes synced to Turso\n%!";
    Ok ()
  | Error err -> 
    Printf.printf "⚠️ Changes written but sync verification failed: %s\n%!" 
      (Database_native.string_of_db_error err);
    Ok () (* Don't fail the operation due to sync verification issues *)

(* Migration helper - detect and handle old vs new workflow *)
let detect_workflow_mode () =
  if Sys.file_exists "local_replica.db" && Sys.file_exists "working_copy.db" then (
    Printf.printf "🔄 Detected legacy copy/diff workflow files\n";
    Printf.printf "💡 Consider migrating to FFI workflow for better performance\n";
    Printf.printf "   • No more copy/diff steps needed\n";
    Printf.printf "   • Real-time sync instead of manual push/pull\n";
    Printf.printf "   • Better error handling and transactions\n%!";
    "legacy"
  ) else if is_initialized () then (
    Printf.printf "✨ Using modern Turso FFI workflow\n%!";
    "ffi"
  ) else (
    Printf.printf "🚀 Ready to initialize Turso FFI workflow\n%!";
    "uninitialized"
  ) 