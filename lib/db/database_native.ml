open Types
open Simple_date

(* Native high-performance database interface with advanced optimizations *)

(* Connection pool for better performance *)
type connection_pool = {
  mutable connections: Sqlite3.db list;
  mutable available: Sqlite3.db list;
  max_size: int;
  current_size: int ref;
}

let connection_pool = ref None
let db_path = ref "org-206.sqlite3"

(* Prepared statement cache for maximum performance *)
module PreparedStmtCache = struct
  let cache = Hashtbl.create 32
  
  let get_or_prepare db sql =
    match Hashtbl.find_opt cache sql with
    | Some stmt -> 
        (* Reset the cached statement *)
        ignore (Sqlite3.reset stmt);
        stmt
    | None ->
        let stmt = Sqlite3.prepare db sql in
        Hashtbl.add cache sql stmt;
        stmt
        
  let clear () = 
    Hashtbl.iter (fun _ stmt -> 
      ignore (Sqlite3.finalize stmt)
    ) cache;
    Hashtbl.clear cache
end

let set_db_path path = db_path := path

(* Error handling with Result types *)
type db_error = 
  | SqliteError of string
  | ParseError of string
  | ConnectionError of string

let string_of_db_error = function
  | SqliteError msg -> "SQLite error: " ^ msg
  | ParseError msg -> "Parse error: " ^ msg
  | ConnectionError msg -> "Connection error: " ^ msg

(* Initialize connection pool for maximum performance *)
let init_connection_pool max_size =
  let pool = {
    connections = [];
    available = [];
    max_size;
    current_size = ref 0;
  } in
  connection_pool := Some pool;
  Ok ()

(* Get database connection from pool or create new one *)
let get_db_connection () =
  match !connection_pool with
  | None ->
      (* Fallback to single connection *)
      (try
        let db = Sqlite3.db_open !db_path in
        Ok db
      with Sqlite3.Error msg ->
        Error (ConnectionError msg))
  | Some pool ->
      (match pool.available with
      | db :: rest ->
          pool.available <- rest;
          Ok db
      | [] when !(pool.current_size) < pool.max_size ->
          (try
            let db = Sqlite3.db_open !db_path in
            pool.connections <- db :: pool.connections;
            incr pool.current_size;
            Ok db
          with Sqlite3.Error msg ->
            Error (ConnectionError msg))
      | [] ->
          (* Pool exhausted, use first available *)
          (match pool.connections with
          | db :: _ -> Ok db
          | [] -> Error (ConnectionError "No connections available")))

(* Return connection to pool *)
let return_connection db =
  match !connection_pool with
  | None -> ignore (Sqlite3.db_close db)
  | Some pool ->
      if not (List.mem db pool.available) then
        pool.available <- db :: pool.available

(* Execute SQL with proper error handling and connection management *)
let execute_sql_safe sql =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      (try
        let rows = ref [] in
        let callback row _headers =
          let row_data = Array.to_list (Array.map (function Some s -> s | None -> "") row) in
          rows := row_data :: !rows
        in
        let result = match Sqlite3.exec db ~cb:callback sql with
        | Sqlite3.Rc.OK -> Ok (List.rev !rows)
        | rc -> Error (SqliteError (Sqlite3.Rc.to_string rc))
        in
        return_connection db;
        result
      with Sqlite3.Error msg ->
        return_connection db;
        Error (SqliteError msg))

(* Execute SQL without result data (INSERT, UPDATE, DELETE) *)
let execute_sql_no_result sql =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      (try
        let result = match Sqlite3.exec db sql with
        | Sqlite3.Rc.OK -> Ok ()
        | rc -> Error (SqliteError (Sqlite3.Rc.to_string rc))
        in
        return_connection db;
        result
      with Sqlite3.Error msg ->
        return_connection db;
        Error (SqliteError msg))

(* Ultra high-performance prepared statement batch insertion with caching *)
let batch_insert_with_prepared_statement table_sql values_list =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      (try
        (* Use cached prepared statement for maximum performance *)
        let stmt = PreparedStmtCache.get_or_prepare db table_sql in
        let total_inserted = ref 0 in
        
        (* Begin immediate transaction to prevent deadlocks *)
        (match Sqlite3.exec db "BEGIN IMMEDIATE" with
         | Sqlite3.Rc.OK -> ()
         | rc -> failwith ("Transaction begin failed: " ^ Sqlite3.Rc.to_string rc));
        
        (* Batch execute with optimized binding *)
        List.iter (fun values ->
          (* Reset statement *)
          ignore (Sqlite3.reset stmt);
          
          (* Bind all parameters efficiently *)
          Array.iteri (fun i value ->
            match Sqlite3.bind stmt (i + 1) (Sqlite3.Data.TEXT value) with
            | Sqlite3.Rc.OK -> ()
            | rc -> failwith ("Bind failed: " ^ Sqlite3.Rc.to_string rc)
          ) values;
          
          (* Execute the statement *)
          match Sqlite3.step stmt with
          | Sqlite3.Rc.DONE -> incr total_inserted
          | rc -> failwith ("Step failed: " ^ Sqlite3.Rc.to_string rc)
        ) values_list;
        
        (* Commit transaction *)
        let result = (match Sqlite3.exec db "COMMIT" with
         | Sqlite3.Rc.OK -> Ok !total_inserted
         | rc -> 
             let _ = Sqlite3.exec db "ROLLBACK" in
             Error (SqliteError ("Commit failed: " ^ Sqlite3.Rc.to_string rc)))
        in
        return_connection db;
        result
        
      with 
      | Sqlite3.Error msg -> 
          let _ = Sqlite3.exec db "ROLLBACK" in
          return_connection db;
          Error (SqliteError msg)
      | Failure msg ->
          let _ = Sqlite3.exec db "ROLLBACK" in
          return_connection db;
          Error (SqliteError msg))

(* Parse contact data from SQLite row *)
let parse_contact_row = function
  | [id_str; email; zip_code; state; birth_date; effective_date] ->
      (try
        let id = int_of_string id_str in
        let birthday = 
          if birth_date = "" || birth_date = "NULL" then None
          else Some (parse_date birth_date)
        in
        let effective_date_opt = 
          if effective_date = "" || effective_date = "NULL" then None
          else Some (parse_date effective_date)
        in
        let state_opt = if state = "" || state = "NULL" then None else Some (state_of_string state) in
        Some {
          id;
          email;
          zip_code = Some zip_code;
          state = state_opt;
          birthday;
          effective_date = effective_date_opt;
        }
      with _ -> None)
  | _ -> None

(* Query-driven contact fetching with native SQLite *)
let get_contacts_in_scheduling_window lookahead_days lookback_days =
  let today = current_date () in
  let active_window_end = add_days today lookahead_days in
  let lookback_window_start = add_days today (-lookback_days) in
  
  (* Format dates for SQL pattern matching *)
  let start_str = Printf.sprintf "%02d-%02d" lookback_window_start.month lookback_window_start.day in
  let end_str = Printf.sprintf "%02d-%02d" active_window_end.month active_window_end.day in
  
  (* Fixed query that properly handles date ranges within the same year *)
  let query = 
    if lookback_window_start.month <= active_window_end.month then
      (* Window doesn't cross year boundary - simple case *)
      Printf.sprintf {|
        SELECT id, email, zip_code, state, birth_date, effective_date
        FROM contacts
        WHERE email IS NOT NULL AND email != '' 
        AND zip_code IS NOT NULL AND zip_code != ''
        AND (
          (strftime('%%m-%%d', birth_date) BETWEEN '%s' AND '%s') OR
          (strftime('%%m-%%d', effective_date) BETWEEN '%s' AND '%s')
        )
      |} start_str end_str start_str end_str
    else
      (* Window crosses year boundary - need to handle two ranges *)
      Printf.sprintf {|
        SELECT id, email, zip_code, state, birth_date, effective_date
        FROM contacts
        WHERE email IS NOT NULL AND email != '' 
        AND zip_code IS NOT NULL AND zip_code != ''
        AND (
          (strftime('%%m-%%d', birth_date) >= '%s' OR strftime('%%m-%%d', birth_date) <= '%s') OR
          (strftime('%%m-%%d', effective_date) >= '%s' OR strftime('%%m-%%d', effective_date) <= '%s')
        )
      |} start_str end_str start_str end_str
  in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let contacts = List.filter_map parse_contact_row rows in
      Ok contacts

(* Get all contacts with native SQLite *)
let get_all_contacts () =
  let query = {|
    SELECT id, email, zip_code, state, birth_date, effective_date
    FROM contacts
    WHERE email IS NOT NULL AND email != '' 
    AND zip_code IS NOT NULL AND zip_code != ''
    ORDER BY id
  |} in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let contacts = List.filter_map parse_contact_row rows in
      Ok contacts

(* Get total contact count with native SQLite *)
let get_total_contact_count () =
  let query = "SELECT COUNT(*) FROM contacts WHERE email IS NOT NULL AND email != ''" in
  match execute_sql_safe query with
  | Ok [[count_str]] -> 
      (try Ok (int_of_string count_str) 
       with _ -> Error (ParseError "Invalid count"))
  | Ok _ -> Error (ParseError "Invalid count result")
  | Error err -> Error err

(* Clear pre-scheduled emails *)
let clear_pre_scheduled_emails () =
  match execute_sql_no_result "DELETE FROM email_schedules WHERE status IN ('pre-scheduled', 'scheduled')" with
  | Ok () -> Ok 1  (* Success indicator *)
  | Error err -> Error err

(* Enhanced SQLite PRAGMA settings for ultra performance *)
let optimize_sqlite_for_ultra_performance () =
  let optimizations = [
    "PRAGMA synchronous = OFF";           (* Maximum speed, some durability risk *)
    "PRAGMA journal_mode = MEMORY";       (* Memory journaling for speed *)
    "PRAGMA cache_size = 100000";         (* 400MB+ cache for large operations *)
    "PRAGMA page_size = 16384";           (* Larger pages for bulk operations *)
    "PRAGMA temp_store = MEMORY";         (* All temp data in memory *)
    "PRAGMA count_changes = OFF";         (* No change counting *)
    "PRAGMA auto_vacuum = 0";             (* No auto-vacuum during bulk ops *)
    "PRAGMA secure_delete = OFF";         (* Faster deletes *)
    "PRAGMA locking_mode = EXCLUSIVE";    (* Exclusive locking *)
    "PRAGMA mmap_size = 268435456";       (* 256MB memory mapping *)
    "PRAGMA threads = 4";                 (* Multi-threading support *)
    "PRAGMA optimize";                    (* Optimize query planner *)
  ] in
  
  let rec apply_pragmas remaining =
    match remaining with
    | [] -> Ok ()
    | pragma :: rest ->
        match execute_sql_no_result pragma with
        | Ok () -> apply_pragmas rest
        | Error err -> Error err
  in
  apply_pragmas optimizations

(* Apply high-performance SQLite PRAGMA settings *)
let optimize_sqlite_for_bulk_inserts () =
  let optimizations = [
    "PRAGMA synchronous = OFF";           (* Don't wait for OS write confirmation - major speedup *)
    "PRAGMA journal_mode = WAL";          (* WAL mode - test for real workload performance *)
    "PRAGMA cache_size = 50000";          (* Much larger cache - 200MB+ *)
    "PRAGMA page_size = 8192";            (* Larger page size for bulk operations *)
    "PRAGMA temp_store = MEMORY";         (* Store temporary tables in memory *)
    "PRAGMA count_changes = OFF";         (* Don't count changes - slight speedup *)
    "PRAGMA auto_vacuum = 0";             (* Disable auto-vacuum during bulk inserts *)
    "PRAGMA secure_delete = OFF";         (* Don't securely delete - faster *)
    "PRAGMA locking_mode = EXCLUSIVE";    (* Exclusive access for bulk operations *)
  ] in
  
  let rec apply_pragmas remaining =
    match remaining with
    | [] -> Ok ()
    | pragma :: rest ->
        match execute_sql_no_result pragma with
        | Ok () -> apply_pragmas rest
        | Error err -> Error err
  in
  apply_pragmas optimizations

(* Database warmup for better performance *)
let warmup_database () =
  let warmup_queries = [
    "SELECT COUNT(*) FROM contacts";
    "SELECT COUNT(*) FROM email_schedules";
    "SELECT sqlite_version()";
  ] in
  
  let rec run_warmup remaining =
    match remaining with
    | [] -> Ok ()
    | query :: rest ->
        match execute_sql_safe query with
        | Ok _ -> run_warmup rest
        | Error err -> Error err
  in
  run_warmup warmup_queries

(* Analyze database statistics for optimization *)
let analyze_database_performance () =
  let analysis_queries = [
    ("table_info", "SELECT name, sql FROM sqlite_master WHERE type='table'");
    ("index_info", "SELECT name, sql FROM sqlite_master WHERE type='index'");
    ("cache_stats", "PRAGMA cache_size");
    ("page_size", "PRAGMA page_size");
    ("journal_mode", "PRAGMA journal_mode");
  ] in
  
  let rec collect_stats remaining acc =
    match remaining with
    | [] -> Ok acc
    | (label, query) :: rest ->
        match execute_sql_safe query with
        | Ok result -> 
            let stats = (label, result) in
            collect_stats rest (stats :: acc)
        | Error err -> Error err
  in
  collect_stats analysis_queries []

(* Enhanced indexes for maximum performance *)
let ensure_performance_indexes () =
  let indexes = [
    (* Core contact indexes *)
    "CREATE INDEX IF NOT EXISTS idx_contacts_state_birthday ON contacts(state, birth_date)";
    "CREATE INDEX IF NOT EXISTS idx_contacts_state_effective ON contacts(state, effective_date)";
    "CREATE INDEX IF NOT EXISTS idx_contacts_email_zip ON contacts(email, zip_code)";
    "CREATE INDEX IF NOT EXISTS idx_contacts_state_only ON contacts(state)";
    
    (* Email schedule indexes *)
    "CREATE INDEX IF NOT EXISTS idx_schedules_lookup ON email_schedules(contact_id, email_type, scheduled_send_date)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_status_date ON email_schedules(status, scheduled_send_date)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_run_id ON email_schedules(scheduler_run_id)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_send_date ON email_schedules(scheduled_send_date)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_contact_status ON email_schedules(contact_id, status)";
    
    (* Performance indexes for complex queries *)
    "CREATE INDEX IF NOT EXISTS idx_contacts_valid_scheduling ON contacts(email, zip_code, state) WHERE email IS NOT NULL AND zip_code IS NOT NULL";
    "CREATE INDEX IF NOT EXISTS idx_schedules_prestatus ON email_schedules(status, scheduled_send_date) WHERE status IN ('pre-scheduled', 'scheduled')";
  ] in
  
  let rec create_indexes remaining =
    match remaining with
    | [] -> Ok ()
    | index_sql :: rest ->
        match execute_sql_no_result index_sql with
        | Ok () -> create_indexes rest
        | Error err -> Error err
  in
  create_indexes indexes

(* Initialize database with full optimization *)
let initialize_database () =
  match init_connection_pool 4 with
  | Error err -> Error err
  | Ok () ->
      match optimize_sqlite_for_bulk_inserts () with
      | Error err -> Error err
      | Ok () ->
          match ensure_performance_indexes () with
          | Error err -> Error err
          | Ok () ->
              match warmup_database () with
              | Error err -> Error err
              | Ok () -> Ok ()

(* Clean shutdown *)
let close_database () =
  match !connection_pool with
  | None -> ()
  | Some pool ->
      PreparedStmtCache.clear ();
      List.iter (fun db -> ignore (Sqlite3.db_close db)) pool.connections;
      connection_pool := None 

(* Restore safe SQLite settings after bulk operations *)
let restore_sqlite_safety () =
  let safety_settings = [
    "PRAGMA synchronous = NORMAL";        (* Restore safe synchronous mode *)
    "PRAGMA journal_mode = WAL";          (* Keep WAL mode - it's safe and fast *)
    "PRAGMA auto_vacuum = 1";             (* Re-enable auto-vacuum *)
    "PRAGMA secure_delete = ON";          (* Re-enable secure delete *)
    "PRAGMA locking_mode = NORMAL";       (* Restore normal locking *)
  ] in
  
  let rec apply_pragmas remaining =
    match remaining with
    | [] -> Ok ()
    | pragma :: rest ->
        match execute_sql_no_result pragma with
        | Ok () -> apply_pragmas rest
        | Error err -> Error err
  in
  apply_pragmas safety_settings

(* Ultra high-performance batch insert using prepared statements *)
let batch_insert_schedules_native schedules =
  if schedules = [] then Ok 0 else
  
  (* Apply performance optimizations *)
  match optimize_sqlite_for_bulk_inserts () with
  | Error err -> Error err
  | Ok _ ->
      (* Prepare statement template *)
      let insert_sql = {|
        INSERT OR REPLACE INTO email_schedules (
          contact_id, email_type, event_year, event_month, event_day,
          scheduled_send_date, scheduled_send_time, status, skip_reason,
          batch_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      |} in
      
      (* Convert schedules to parameter arrays *)
      let values_list = List.map (fun schedule ->
        let scheduled_date_str = string_of_date schedule.scheduled_date in
        let scheduled_time_str = string_of_time schedule.scheduled_time in
        let status_str = match schedule.status with
          | PreScheduled -> "pre-scheduled"
          | Skipped _reason -> "skipped"
          | _ -> "unknown"
        in
        let skip_reason = match schedule.status with 
          | Skipped reason -> reason 
          | _ -> ""
        in
        
        let current_year = (current_date()).year in
        let (event_year, event_month, event_day) = match schedule.email_type with
          | Anniversary Birthday -> (current_year, 1, 1)
          | Anniversary EffectiveDate -> (current_year, 1, 2)
          | Anniversary AEP -> (current_year, 9, 15)
          | _ -> (current_year, 1, 1)
        in
        
        [|
          string_of_int schedule.contact_id;
          string_of_email_type schedule.email_type;
          string_of_int event_year;
          string_of_int event_month;
          string_of_int event_day;
          scheduled_date_str;
          scheduled_time_str;
          status_str;
          skip_reason;
          schedule.scheduler_run_id;
        |]
      ) schedules in
      
      (* Use prepared statement batch insertion *)
      match batch_insert_with_prepared_statement insert_sql values_list with
      | Ok total ->
          (* Restore safety settings *)
          let _ = restore_sqlite_safety () in
          Ok total
      | Error err -> 
          let _ = restore_sqlite_safety () in
          Error err

(* Simple but highly effective batch insert using native SQLite *)
let batch_insert_schedules_optimized schedules =
  batch_insert_schedules_native schedules

(* Get sent emails for followup *)
let get_sent_emails_for_followup lookback_days =
  let lookback_date = add_days (current_date ()) (-lookback_days) in
  let query = Printf.sprintf {|
    SELECT contact_id, email_type, 
           COALESCE(actual_send_datetime, scheduled_send_date) as sent_time,
           id
    FROM email_schedules 
    WHERE status IN ('sent', 'delivered')
    AND scheduled_send_date >= '%s'
    AND email_type IN ('birthday', 'effective_date', 'aep')
    ORDER BY contact_id, sent_time DESC
  |} (string_of_date lookback_date) in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let sent_emails = List.filter_map (fun row ->
        match row with
        | [contact_id_str; email_type; sent_time; id_str] ->
            (try
              let contact_id = int_of_string contact_id_str in
              let id = int_of_string id_str in
              Some (contact_id, email_type, sent_time, id)
            with _ -> None)
        | _ -> None
      ) rows in
      Ok sent_emails

(* Check contact interaction data for followup classification *)
let get_contact_interactions contact_id since_date =
  let clicks_query = Printf.sprintf {|
    SELECT COUNT(*) FROM tracking_clicks 
    WHERE contact_id = %d AND clicked_at >= '%s'
  |} contact_id since_date in
  
  let events_query = Printf.sprintf {|
    SELECT COUNT(*) FROM contact_events
    WHERE contact_id = %d AND created_at >= '%s' AND event_type = 'eligibility_answered'
  |} contact_id since_date in
  
  match execute_sql_safe clicks_query with
  | Error err -> Error err
  | Ok [[click_count_str]] ->
      (match execute_sql_safe events_query with
       | Error err -> Error err
       | Ok [[event_count_str]] ->
           (try
             let has_clicks = int_of_string click_count_str > 0 in
             let has_health_answers = int_of_string event_count_str > 0 in
             Ok (has_clicks, has_health_answers)
           with _ -> Error (ParseError "Invalid interaction count"))
       | Ok _ -> Error (ParseError "Invalid event result"))
  | Ok _ -> Error (ParseError "Invalid click result") 