(* Turso FFI Integration using OCaml-Rust FFI *)
(* This module provides direct access to libSQL via Rust FFI, eliminating the copy/diff workflow *)

(* External function declarations - these come from the Rust FFI library *)
external turso_init_runtime : unit -> unit = "turso_init_runtime"

external turso_create_synced_db : string -> string -> string -> (string, string) result
  = "turso_create_synced_db"

external turso_sync : string -> (unit, string) result = "turso_sync"

external turso_query : string -> string -> (string list list, string) result
  = "turso_query"

external turso_execute : string -> string -> (int64, string) result = "turso_execute"

external turso_execute_batch : string -> string list -> (int64, string) result
  = "turso_execute_batch"

external turso_close_connection : string -> (unit, string) result
  = "turso_close_connection"

external turso_connection_count : unit -> int = "turso_connection_count"

(* High-level OCaml interface *)

type connection_id = string

type db_error = 
  | ConnectionError of string
  | SqlError of string
  | SyncError of string

let string_of_db_error = function
  | ConnectionError msg -> "Connection error: " ^ msg
  | SqlError msg -> "SQL error: " ^ msg
  | SyncError msg -> "Sync error: " ^ msg

(* Global state *)
let initialized = ref false
let current_connection = ref None

(* Initialize the Rust runtime (call once) *)
let init_runtime () =
  if not !initialized then (
    turso_init_runtime ();
    initialized := true;
    Printf.printf "✅ Turso FFI runtime initialized\n%!"
  )

(* Create a synced database connection *)
let create_synced_database ~db_path ~url ~token =
  init_runtime ();
  match turso_create_synced_db db_path url token with
  | Ok connection_id -> 
    current_connection := Some connection_id;
    Printf.printf "✅ Created synced database connection: %s\n%!" connection_id;
    Ok connection_id
  | Error msg -> Error (ConnectionError msg)

(* Get current connection or error *)
let get_connection () =
  match !current_connection with
  | Some conn_id -> Ok conn_id
  | None -> Error (ConnectionError "No active connection. Call create_synced_database first.")

(* Sync with remote Turso *)
let sync_database () =
  match get_connection () with
  | Ok conn_id -> 
    (match turso_sync conn_id with
     | Ok () -> 
       Printf.printf "✅ Database synced successfully\n%!";
       Ok ()
     | Error msg -> Error (SyncError msg))
  | Error err -> Error err

(* Execute a query and return results *)
let execute_query sql =
  match get_connection () with
  | Ok conn_id ->
    (match turso_query conn_id sql with
     | Ok results -> Ok results
     | Error msg -> Error (SqlError msg))
  | Error err -> Error err

(* Execute a statement (INSERT, UPDATE, DELETE) *)
let execute_statement sql =
  match get_connection () with
  | Ok conn_id ->
    (match turso_execute conn_id sql with
     | Ok affected_rows -> Ok (Int64.to_int affected_rows)
     | Error msg -> Error (SqlError msg))
  | Error err -> Error err

(* Execute multiple statements as a transaction *)
let execute_batch statements =
  match get_connection () with
  | Ok conn_id ->
    (match turso_execute_batch conn_id statements with
     | Ok affected_rows -> Ok (Int64.to_int affected_rows)
     | Error msg -> Error (SqlError msg))
  | Error err -> Error err

(* Close the current connection *)
let close_connection () =
  match !current_connection with
  | Some conn_id ->
    (match turso_close_connection conn_id with
     | Ok () -> 
       current_connection := None;
       Printf.printf "✅ Connection closed\n%!";
       Ok ()
     | Error msg -> Error (ConnectionError msg))
  | None -> Ok () (* Already closed *)

(* Get connection statistics *)
let connection_count () = turso_connection_count ()

(* High-level integration functions compatible with existing code *)

let working_database_path = "working_copy.db"

(* Environment configuration *)
let get_env_var name =
  try
    Some (Sys.getenv name)
  with Not_found -> None

let get_turso_config () =
  match (get_env_var "TURSO_DATABASE_URL", get_env_var "TURSO_AUTH_TOKEN") with
  | (Some url, Some token) -> Ok (url, token)
  | (None, _) -> Error (ConnectionError "TURSO_DATABASE_URL not set")
  | (_, None) -> Error (ConnectionError "TURSO_AUTH_TOKEN not set")

(* Initialize connection with environment variables *)
let initialize_turso_connection () =
  match get_turso_config () with
  | Ok (url, token) -> 
    create_synced_database ~db_path:working_database_path ~url ~token
  | Error err -> Error err

(* Get database connection (compatible with existing Database_native interface) *)
let get_database_connection () =
  if not !initialized then (
    match initialize_turso_connection () with
    | Ok _conn_id -> 
      (* Initial sync to pull latest data *)
      (match sync_database () with
       | Ok () -> Ok "Connected via Turso FFI"
       | Error err -> Error err)
    | Error err -> Error err
  ) else (
    Ok "Already connected via Turso FFI"
  )

(* Execute SQL safely (compatible with Database_native interface) *)
let execute_sql_safe sql =
  match execute_query sql with
  | Ok results -> Ok results
  | Error err -> Error err

(* Execute SQL without result (compatible with Database_native interface) *)
let execute_sql_no_result sql =
  match execute_statement sql with
  | Ok _affected -> Ok ()
  | Error err -> Error err

(* Batch insert compatible with existing interface *)
let batch_insert_with_prepared_statement _table_sql _values_list =
  Error (SqlError "Use execute_batch for batch operations with FFI")

(* Smart batch insert (enhanced version using FFI) *)
let smart_batch_insert_schedules schedules current_run_id =
  if schedules = [] then Ok 0 else (
    Printf.printf "🔄 Converting schedules to SQL statements...\n%!";
    
    (* Convert schedules to SQL statements *)
    let sql_statements = List.map (fun (schedule : Types.email_schedule) ->
      Printf.sprintf 
        "INSERT INTO email_schedules (contact_id, email_type, send_date, run_id, campaign_id, follow_up_parent_id, created_at) VALUES (%d, '%s', '%s', '%s', %s, %s, datetime('now'))"
        schedule.contact_id
        (Types.string_of_email_type schedule.email_type)
        schedule.send_date
        current_run_id
        (match schedule.campaign_id with Some id -> string_of_int id | None -> "NULL")
        (match schedule.follow_up_parent_id with Some id -> string_of_int id | None -> "NULL")
    ) schedules in
    
    Printf.printf "🚀 Executing batch insert of %d schedules via FFI...\n%!" (List.length schedules);
    
    match execute_batch sql_statements with
    | Ok affected_rows -> 
      Printf.printf "✅ Successfully inserted %d schedules via Turso FFI\n%!" affected_rows;
      (* Auto-sync after writes *)
      (match sync_database () with
       | Ok () -> Ok affected_rows
       | Error err -> 
         Printf.printf "⚠️ Insert succeeded but sync failed: %s\n%!" (string_of_db_error err);
         Ok affected_rows (* Don't fail the insert due to sync issues *))
    | Error err -> Error err
  )

(* Sync suggestions and status *)
let suggest_sync_check () =
  Printf.printf "💡 Tip: Database changes are automatically synced with Turso via FFI\n%!";
  Printf.printf "📊 Active connections: %d\n%!" (connection_count ())

let print_sync_instructions () =
  Printf.printf "\n🎯 Using Turso FFI Integration:\n";
  Printf.printf "   • No manual sync needed - changes auto-sync to Turso\n";
  Printf.printf "   • No copy/diff workflow - direct libSQL access\n";
  Printf.printf "   • Real-time bidirectional sync\n";
  Printf.printf "   • Automatic transaction handling\n\n%!"

let is_initialized () = !initialized

(* Cleanup function *)
let shutdown () =
  match close_connection () with
  | Ok () -> Printf.printf "✅ Turso FFI shutdown complete\n%!"
  | Error err -> Printf.printf "⚠️ Shutdown warning: %s\n%!" (string_of_db_error err)