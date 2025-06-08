open Types
open Date_time

(* Native high-performance database interface using proper SQLite bindings *)

let db_handle = ref None
let db_path = ref "org-206.sqlite3"

(** 
 * [set_db_path]: Sets the database file path for SQLite connections
 * 
 * Purpose:
 *   Configures the SQLite database file location for all subsequent database
 *   operations, enabling environment-specific database configuration.
 * 
 * Parameters:
 *   - path: String path to SQLite database file
 * 
 * Returns:
 *   Unit (side effect: updates global database path reference)
 * 
 * Business Logic:
 *   - Updates global database path configuration
 *   - Enables switching between development, test, and production databases
 *   - Must be called before database operations in different environments
 * 
 * Usage Example:
 *   Called during application initialization to set environment-specific database
 * 
 * Error Cases:
 *   - None expected (simple reference assignment)
 * 
 * @integration_point
 *)
let set_db_path path = db_path := path

(* Error handling with Result types *)
type db_error = 
  | SqliteError of string
  | ParseError of string
  | ConnectionError of string

(** 
 * [string_of_db_error]: Converts database error to human-readable string
 * 
 * Purpose:
 *   Provides standardized error message formatting for database errors
 *   to enable consistent error reporting and debugging.
 * 
 * Parameters:
 *   - db_error variant: Specific database error type
 * 
 * Returns:
 *   String with formatted error message including error type
 * 
 * Business Logic:
 *   - Categorizes errors for targeted debugging
 *   - Provides clear error context for troubleshooting
 *   - Enables consistent error handling across application
 * 
 * Usage Example:
 *   Used in error reporting and logging throughout database operations
 * 
 * Error Cases:
 *   - None expected (pure string formatting)
 * 
 * @integration_point
 *)
let string_of_db_error = function
  | SqliteError msg -> "SQLite error: " ^ msg
  | ParseError msg -> "Parse error: " ^ msg
  | ConnectionError msg -> "Connection error: " ^ msg

(* Get or create database connection *)
let get_db_connection () =
  match !db_handle with
  | Some db -> Ok db
  | None ->
      try
        let db = Sqlite3.db_open !db_path in
        db_handle := Some db;
        Ok db
      with Sqlite3.Error msg ->
        Error (ConnectionError msg)

(* Parse datetime from SQLite timestamp string *)
let parse_datetime datetime_str =
  if datetime_str = "" || datetime_str = "NULL" then
    current_datetime ()
  else
    try
      (* Handle common SQLite datetime formats: "YYYY-MM-DD HH:MM:SS" *)
      match String.split_on_char ' ' datetime_str with
      | [date_part; time_part] ->
          let date = parse_date date_part in
          let time_components = String.split_on_char ':' time_part in
          (match time_components with
           | [hour_str; minute_str; second_str] ->
               let hour = int_of_string hour_str in
               let minute = int_of_string minute_str in
               (* Handle fractional seconds and short second strings safely *)
               let second = 
                 if String.length second_str >= 2 then
                   int_of_string (String.sub second_str 0 2)
                 else
                   int_of_string second_str
               in
               let time_tuple = (hour, minute, second) in
               make_datetime date time_tuple
           | _ -> current_datetime ())
      | [date_part] ->
          (* Date only, assume midnight *)
          let date = parse_date date_part in
          make_datetime date (0, 0, 0)
      | _ -> current_datetime ()
    with _ -> current_datetime ()

(* Execute SQL with proper error handling *)
let execute_sql_safe sql =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      try
        let rows = ref [] in
        let callback row _headers =
          let row_data = Array.to_list (Array.map (function Some s -> s | None -> "") row) in
          rows := row_data :: !rows
        in
        match Sqlite3.exec db ~cb:callback sql with
        | Sqlite3.Rc.OK -> Ok (List.rev !rows)
        | rc -> Error (SqliteError (Sqlite3.Rc.to_string rc))
      with Sqlite3.Error msg ->
        Error (SqliteError msg)

(* Execute SQL without result data (INSERT, UPDATE, DELETE) *)
let execute_sql_no_result sql =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      try
        match Sqlite3.exec db sql with
        | Sqlite3.Rc.OK -> Ok ()
        | rc -> Error (SqliteError (Sqlite3.Rc.to_string rc))
      with Sqlite3.Error msg ->
        Error (SqliteError msg)

(* High-performance prepared statement batch insertion *)
let batch_insert_with_prepared_statement table_sql values_list =
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      try
        (* Prepare the statement once *)
        let stmt = Sqlite3.prepare db table_sql in
        let total_inserted = ref 0 in
        
        (* Begin transaction for batch *)
        (match Sqlite3.exec db "BEGIN TRANSACTION" with
         | Sqlite3.Rc.OK -> ()
         | rc -> failwith ("Transaction begin failed: " ^ Sqlite3.Rc.to_string rc));
        
        (* Execute for each set of values *)
        List.iter (fun values ->
          (* Reset and bind parameters *)
          ignore (Sqlite3.reset stmt);
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
        (match Sqlite3.exec db "COMMIT" with
         | Sqlite3.Rc.OK -> Ok !total_inserted
         | rc -> 
             let _ = Sqlite3.exec db "ROLLBACK" in
             Error (SqliteError ("Commit failed: " ^ Sqlite3.Rc.to_string rc)))
        
      with 
      | Sqlite3.Error msg -> 
          let _ = Sqlite3.exec db "ROLLBACK" in
          Error (SqliteError msg)
      | Failure msg ->
          let _ = Sqlite3.exec db "ROLLBACK" in
          Error (SqliteError msg)

(* Parse contact data from SQLite row with new fields *)
let parse_contact_row = function
  | [id_str; email; zip_code; state; birth_date; effective_date; carrier; failed_underwriting_str] ->
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
        let zip_code_opt = if zip_code = "" || zip_code = "NULL" then None else Some zip_code in
        let carrier_opt = if carrier = "" || carrier = "NULL" then None else Some carrier in
        let failed_underwriting = (failed_underwriting_str = "1" || failed_underwriting_str = "true") in
        Some {
          id;
          email;
          zip_code = zip_code_opt;
          state = state_opt;
          birthday;
          effective_date = effective_date_opt;
          carrier = carrier_opt;
          failed_underwriting;
        }
      with _ -> None)
  | [id_str; email; zip_code; state; birth_date; effective_date] ->
      (* Backward compatibility for old schema without carrier/underwriting fields *)
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
        let zip_code_opt = if zip_code = "" || zip_code = "NULL" then None else Some zip_code in
        Some {
          id;
          email;
          zip_code = zip_code_opt;
          state = state_opt;
          birthday;
          effective_date = effective_date_opt;
          carrier = None;
          failed_underwriting = false;
        }
      with _ -> None)
  | _ -> None

(* Query-driven contact fetching with native SQLite - updated for new fields *)
let get_contacts_in_scheduling_window lookahead_days lookback_days =
  let today = current_date () in
  let active_window_end = add_days today lookahead_days in
  let lookback_window_start = add_days today (-lookback_days) in
  
  (* Format dates for SQL pattern matching *)
  let (_, start_month, start_day) = lookback_window_start in
  let (_, end_month, end_day) = active_window_end in
  let start_str = Printf.sprintf "%02d-%02d" start_month start_day in
  let end_str = Printf.sprintf "%02d-%02d" end_month end_day in
  
  (* Updated query to include new fields with fallback for old schema *)
  let query = 
    if start_month <= end_month then
      (* Window doesn't cross year boundary - simple case *)
      Printf.sprintf {|
        SELECT id, email, 
               COALESCE(zip_code, '') as zip_code, 
               COALESCE(state, '') as state, 
               COALESCE(birth_date, '') as birth_date, 
               COALESCE(effective_date, '') as effective_date,
               COALESCE(carrier, '') as carrier,
               COALESCE(failed_underwriting, 0) as failed_underwriting
        FROM contacts
        WHERE email IS NOT NULL AND email != '' 
        AND (
          (strftime('%%m-%%d', birth_date) BETWEEN '%s' AND '%s') OR
          (strftime('%%m-%%d', effective_date) BETWEEN '%s' AND '%s')
        )
      |} start_str end_str start_str end_str
    else
      (* Window crosses year boundary - need to handle two ranges *)
      Printf.sprintf {|
        SELECT id, email, 
               COALESCE(zip_code, '') as zip_code, 
               COALESCE(state, '') as state, 
               COALESCE(birth_date, '') as birth_date, 
               COALESCE(effective_date, '') as effective_date,
               COALESCE(carrier, '') as carrier,
               COALESCE(failed_underwriting, 0) as failed_underwriting
        FROM contacts
        WHERE email IS NOT NULL AND email != '' 
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

(* Get all contacts with native SQLite - updated for new fields *)
let get_all_contacts () =
  let query = {|
    SELECT id, email, 
           COALESCE(zip_code, '') as zip_code, 
           COALESCE(state, '') as state, 
           COALESCE(birth_date, '') as birth_date, 
           COALESCE(effective_date, '') as effective_date,
           COALESCE(carrier, '') as carrier,
           COALESCE(failed_underwriting, 0) as failed_underwriting
    FROM contacts
    WHERE email IS NOT NULL AND email != '' 
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

(* Helper type for existing schedule comparison *)
type existing_schedule_record = {
  contact_id: int;
  email_type: string;
  scheduled_date: string;
  scheduled_time: string;
  status: string;
  skip_reason: string;
  scheduler_run_id: string;
  created_at: string;
}

(** 
 * [schedule_content_changed]: Intelligently compares schedule content to detect real changes
 * 
 * Purpose:
 *   Core smart update logic that determines if email schedule content has actually
 *   changed, ignoring metadata to preserve audit trails and prevent unnecessary updates.
 * 
 * Parameters:
 *   - existing_record: Existing schedule record from database
 *   - new_schedule: New schedule to compare against existing
 * 
 * Returns:
 *   Boolean indicating if content has meaningfully changed
 * 
 * Business Logic:
 *   - Compares essential schedule fields: type, date, time, status, skip reason
 *   - Ignores metadata fields like run_id and timestamps for audit preservation
 *   - Logs preservation decisions for audit trail transparency
 *   - Enables smart database updates that preserve history when appropriate
 *   - Critical for maintaining scheduler run tracking across multiple executions
 * 
 * Usage Example:
 *   Called by smart_batch_insert_schedules to determine update necessity
 * 
 * Error Cases:
 *   - None expected (pure comparison logic)
 * 
 * @business_rule @performance
 *)
let schedule_content_changed existing_record (new_schedule : email_schedule) =
  let new_scheduled_date_str = string_of_date new_schedule.scheduled_date in
  let new_scheduled_time_str = string_of_time new_schedule.scheduled_time in
  let new_status_str = match new_schedule.status with
    | PreScheduled -> "pre-scheduled"
    | Skipped _reason -> "skipped"
    | _ -> "unknown"
  in
  let new_skip_reason = match new_schedule.status with 
    | Skipped reason -> reason 
    | _ -> ""
  in
  let new_email_type_str = string_of_email_type new_schedule.email_type in
  
  let content_changed = 
    existing_record.email_type <> new_email_type_str ||
    existing_record.scheduled_date <> new_scheduled_date_str ||
    existing_record.scheduled_time <> new_scheduled_time_str ||
    existing_record.status <> new_status_str ||
    existing_record.skip_reason <> new_skip_reason
  in
  
  (* Use audit fields for business logic - log preservation of original scheduler_run_id *)
  if not content_changed then
    Printf.printf "📝 Content unchanged for contact %d - preserving original scheduler_run_id: %s (created: %s)\n%!" 
      new_schedule.contact_id existing_record.scheduler_run_id existing_record.created_at;
  
  content_changed

(* Find existing schedule for a new schedule *)
let find_existing_schedule existing_schedules (new_schedule : email_schedule) =
  let new_email_type_str = string_of_email_type new_schedule.email_type in
  let new_scheduled_date_str = string_of_date new_schedule.scheduled_date in
  
  List.find_opt (fun existing ->
    existing.contact_id = new_schedule.contact_id &&
    existing.email_type = new_email_type_str &&
    existing.scheduled_date = new_scheduled_date_str
  ) existing_schedules

(** 
 * [smart_batch_insert_schedules]: Intelligent bulk schedule update with audit preservation
 * 
 * Purpose:
 *   Flagship smart update function that minimizes database operations by detecting
 *   unchanged schedules and preserving their audit trails while updating only changed content.
 * 
 * Parameters:
 *   - schedules: List of new email schedules to process
 *   - current_run_id: Run identifier for new schedules
 * 
 * Returns:
 *   Result containing number of processed records or database error
 * 
 * Business Logic:
 *   - Retrieves all existing schedules for intelligent comparison
 *   - Categorizes each schedule as new, changed, or unchanged
 *   - INSERT for new schedules with current run_id
 *   - UPDATE for changed schedules with current run_id and audit logging
 *   - PRESERVE unchanged schedules with original run_id for audit continuity
 *   - Uses single transaction for atomicity and performance
 *   - Provides detailed metrics for monitoring and optimization
 * 
 * Usage Example:
 *   Primary database update function called by scheduling orchestration
 * 
 * Error Cases:
 *   - Database errors with automatic rollback for data consistency
 *   - Comprehensive error logging for troubleshooting
 * 
 * @business_rule @performance @integration_point
 *)
let smart_batch_insert_schedules schedules current_run_id =
  if schedules = [] then Ok 0 else (
  
  Printf.printf "🔍 Getting existing schedules for comparison...\n%!";
  match get_existing_schedules_for_comparison () with
  | Error err -> Error err
  | Ok existing_schedules ->
      Printf.printf "📊 Found %d existing schedules to compare against\n%!" (List.length existing_schedules);
      
      match get_db_connection () with
      | Error err -> Error err
      | Ok db ->
          try
            (* Begin transaction *)
            (match Sqlite3.exec db "BEGIN TRANSACTION" with
             | Sqlite3.Rc.OK -> ()
             | rc -> failwith ("Transaction begin failed: " ^ Sqlite3.Rc.to_string rc));
            
            let total_processed = ref 0 in
            let unchanged_count = ref 0 in
            let changed_count = ref 0 in
            let new_count = ref 0 in
            
            (* Process each schedule with truly smart logic *)
            List.iter (fun (schedule : email_schedule) ->
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
              
              let (current_year, _, _) = current_date () in
              let (event_year, event_month, event_day) = match schedule.email_type with
                | Anniversary Birthday -> (current_year, 1, 1)
                | Anniversary EffectiveDate -> (current_year, 1, 2)
                | Anniversary AEP -> (current_year, 9, 15)
                | _ -> (current_year, 1, 1)
              in
              
              (* Determine what action to take *)
              (match find_existing_schedule existing_schedules schedule with
                | None -> 
                    (* New schedule - INSERT *)
                    incr new_count;
                    let insert_sql = Printf.sprintf {|
                      INSERT INTO email_schedules (
                        contact_id, email_type, event_year, event_month, event_day,
                        scheduled_send_date, scheduled_send_time, status, skip_reason,
                        batch_id
                      ) VALUES (%d, '%s', %d, %d, %d, '%s', '%s', '%s', '%s', '%s')
                    |} 
                      schedule.contact_id
                      (string_of_email_type schedule.email_type)
                      event_year event_month event_day
                      scheduled_date_str
                      scheduled_time_str
                      status_str
                      skip_reason
                      current_run_id
                    in
                    (match Sqlite3.exec db insert_sql with
                     | Sqlite3.Rc.OK -> incr total_processed
                     | rc -> failwith ("Insert failed: " ^ Sqlite3.Rc.to_string rc))
                     
                | Some existing ->
                    if schedule_content_changed existing schedule then (
                      (* Content changed - UPDATE with new run_id and log audit trail *)
                      incr changed_count;
                      Printf.printf "🔄 Updating schedule for contact %d: %s → %s (original run: %s, created: %s)\n%!" 
                        schedule.contact_id existing.status status_str existing.scheduler_run_id existing.created_at;
                      
                      let update_sql = Printf.sprintf {|
                        UPDATE email_schedules SET
                          email_type = '%s', event_year = %d, event_month = %d, event_day = %d,
                          scheduled_send_date = '%s', scheduled_send_time = '%s', 
                          status = '%s', skip_reason = '%s', batch_id = '%s',
                          updated_at = CURRENT_TIMESTAMP
                        WHERE contact_id = %d AND email_type = '%s' AND scheduled_send_date = '%s'
                      |} 
                        (string_of_email_type schedule.email_type)
                        event_year event_month event_day
                        scheduled_date_str
                        scheduled_time_str
                        status_str
                        skip_reason
                        current_run_id
                        schedule.contact_id
                        existing.email_type
                        existing.scheduled_date
                      in
                      (match Sqlite3.exec db update_sql with
                       | Sqlite3.Rc.OK -> incr total_processed
                       | rc -> failwith ("Update failed: " ^ Sqlite3.Rc.to_string rc))
                    ) else (
                      (* Content unchanged - preserve existing record with full audit info *)
                      incr unchanged_count;
                      incr total_processed;
                      Printf.printf "✅ Preserving unchanged record for contact %d (run: %s, age: %s)\n%!" 
                        schedule.contact_id existing.scheduler_run_id existing.created_at;
                      (* No database operation needed - smart preservation! *)
                    )
              )
            ) schedules;
            
            (* Commit transaction *)
            (match Sqlite3.exec db "COMMIT" with
             | Sqlite3.Rc.OK -> 
                 Printf.printf "✅ Truly smart update complete: %d total, %d new, %d changed, %d unchanged (skipped)\n%!" 
                   !total_processed !new_count !changed_count !unchanged_count;
                 Ok !total_processed
             | rc -> 
                 let _ = Sqlite3.exec db "ROLLBACK" in
                 Error (SqliteError ("Commit failed: " ^ Sqlite3.Rc.to_string rc)))
            
          with 
          | Sqlite3.Error msg -> 
              let _ = Sqlite3.exec db "ROLLBACK" in
              Error (SqliteError msg)
          | Failure msg ->
              let _ = Sqlite3.exec db "ROLLBACK" in
              Error (SqliteError msg)
  )

(* Modified clear function that doesn't delete everything *)
let smart_clear_outdated_schedules new_schedules =
  if new_schedules = [] then Ok 0 else
  
  (* Build list of (contact_id, email_type, scheduled_date) for schedules we're keeping *)
  let keeping_schedules = List.map (fun (schedule : email_schedule) ->
    let email_type_str = string_of_email_type schedule.email_type in
    let scheduled_date_str = string_of_date schedule.scheduled_date in
    Printf.sprintf "(%d, '%s', '%s')" 
      schedule.contact_id email_type_str scheduled_date_str
  ) new_schedules in
  
  let keeping_list = String.concat ", " keeping_schedules in
  
  (* Delete only schedules not in our new list *)
  let delete_query = Printf.sprintf {|
    DELETE FROM email_schedules 
    WHERE status IN ('pre-scheduled', 'scheduled', 'skipped')
    AND (contact_id, email_type, scheduled_send_date) NOT IN (%s)
  |} keeping_list in
  
  match execute_sql_no_result delete_query with
  | Ok () -> 
      Printf.printf "🗑️  Cleaned up outdated schedules\n%!";
      Ok 1
  | Error err -> Error err

(* Apply high-performance SQLite PRAGMA settings *)
let optimize_sqlite_for_bulk_inserts () =
  let optimizations = [
    "PRAGMA synchronous = OFF";           (* Don't wait for OS write confirmation - major speedup *)
    "PRAGMA journal_mode = WAL";          (* WAL mode - test for real workload performance *)
    "PRAGMA cache_size = 500000";          (* Much larger cache - 200MB+ *)
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

(** 
 * [batch_insert_schedules_native]: Ultra high-performance batch insertion using prepared statements
 * 
 * Purpose:
 *   Provides maximum performance bulk insertion using SQLite prepared statements
 *   with aggressive optimizations for large-scale email schedule operations.
 * 
 * Parameters:
 *   - schedules: List of email schedules to insert
 * 
 * Returns:
 *   Result containing number of inserted records or database error
 * 
 * Business Logic:
 *   - Applies performance optimizations before insertion
 *   - Uses prepared statements for optimal SQL execution
 *   - Processes schedules in single transaction for atomicity
 *   - Converts schedule records to parameter arrays efficiently
 *   - Handles event date calculations for database storage
 *   - Restores safety settings after completion
 * 
 * Usage Example:
 *   Used for large-scale schedule insertions during batch processing
 * 
 * Error Cases:
 *   - Database errors with automatic safety restoration
 *   - Transaction rollback on any failure
 * 
 * @performance @integration_point
 *)
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
      let values_list = List.map (fun (schedule : email_schedule) ->
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
        
        let (current_year, _, _) = current_date () in
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

(* Batch insert with improved transaction handling - for smaller datasets *)
let batch_insert_schedules_transactional schedules =
  if schedules = [] then Ok 0 else
  
  match get_db_connection () with
  | Error err -> Error err
  | Ok db ->
      try
        (* Begin transaction *)
        (match Sqlite3.exec db "BEGIN TRANSACTION" with
         | Sqlite3.Rc.OK -> ()
         | rc -> failwith ("Transaction begin failed: " ^ Sqlite3.Rc.to_string rc));
        
        let total_inserted = ref 0 in
        
        (* Process each schedule individually within the transaction *)
        List.iter (fun (schedule : email_schedule) ->
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
          
          let (current_year, _, _) = current_date () in
          let (event_year, event_month, event_day) = match schedule.email_type with
            | Anniversary Birthday -> (current_year, 1, 1)
            | Anniversary EffectiveDate -> (current_year, 1, 2)
            | Anniversary AEP -> (current_year, 9, 15)
            | _ -> (current_year, 1, 1)
          in
          
          let insert_sql = Printf.sprintf {|
            INSERT OR REPLACE INTO email_schedules (
              contact_id, email_type, event_year, event_month, event_day,
              scheduled_send_date, scheduled_send_time, status, skip_reason,
              batch_id
            ) VALUES (%d, '%s', %d, %d, %d, '%s', '%s', '%s', '%s', '%s')
          |} 
            schedule.contact_id
            (string_of_email_type schedule.email_type)
            event_year event_month event_day
            scheduled_date_str
            scheduled_time_str
            status_str
            skip_reason
            schedule.scheduler_run_id
          in
          
          match Sqlite3.exec db insert_sql with
          | Sqlite3.Rc.OK -> incr total_inserted
          | rc -> failwith ("Insert failed: " ^ Sqlite3.Rc.to_string rc)
        ) schedules;
        
        (* Commit transaction *)
        (match Sqlite3.exec db "COMMIT" with
         | Sqlite3.Rc.OK -> Ok !total_inserted
         | rc -> 
             let _ = Sqlite3.exec db "ROLLBACK" in
             Error (SqliteError ("Commit failed: " ^ Sqlite3.Rc.to_string rc)))
        
      with 
      | Sqlite3.Error msg -> 
          let _ = Sqlite3.exec db "ROLLBACK" in
          Error (SqliteError msg)
      | Failure msg ->
          let _ = Sqlite3.exec db "ROLLBACK" in
          Error (SqliteError msg)

(* Chunked batch insert with automatic chunk size optimization *)
let batch_insert_schedules_chunked schedules chunk_size =
  (* For large datasets, use the optimized prepared statement approach *)
  if List.length schedules > 1000 then
    batch_insert_schedules_native schedules
  else
    (* For smaller datasets, use the transactional approach *)
    if schedules = [] then Ok 0 else
    
    let rec chunk_list lst size =
      match lst with
      | [] -> []
      | _ ->
          let (chunk, rest) = 
            let rec take n lst acc =
              match lst, n with
              | [], _ -> (List.rev acc, [])
              | _, 0 -> (List.rev acc, lst)
              | x :: xs, n -> take (n-1) xs (x :: acc)
            in
            take size lst []
          in
          chunk :: chunk_list rest size
    in
    
    let chunks = chunk_list schedules chunk_size in
    let total_inserted = ref 0 in
    
    let rec process_chunks remaining_chunks =
      match remaining_chunks with
      | [] -> Ok !total_inserted
      | chunk :: rest ->
          match batch_insert_schedules_transactional chunk with
          | Ok count -> 
              total_inserted := !total_inserted + count;
              process_chunks rest
          | Error err -> Error err
    in
    
    process_chunks chunks

(* NEW: Smart update workflow - replaces clear_pre_scheduled_emails + batch_insert *)
let smart_update_schedules schedules current_run_id =
  if schedules = [] then Ok 0 else (
  
  Printf.printf "🚀 Starting smart schedule update with %d schedules...\n%!" (List.length schedules);
  
  (* Step 1: Smart insert/update with scheduler_run_id preservation *)
  match smart_batch_insert_schedules schedules current_run_id with
  | Error err -> Error err
  | Ok inserted_count ->
      (* Step 2: Clean up schedules that are no longer needed *)
      match smart_clear_outdated_schedules schedules with
      | Error err -> Error err
      | Ok _ ->
          Printf.printf "🎉 Smart update complete! Processed %d schedules\n%!" inserted_count;
          Ok inserted_count
  )

(* Legacy function for backward compatibility *)
let update_schedules_legacy schedules _current_run_id =
  Printf.printf "⚠️  Using legacy update method (clear all + insert all)\n%!";
  match clear_pre_scheduled_emails () with
  | Error err -> Error err
  | Ok _ ->
      match batch_insert_schedules_chunked schedules 1000 with
      | Error err -> Error err
      | Ok count -> Ok count

(* Main entry point - uses smart update by default *)
let update_email_schedules ?(use_smart_update=true) schedules current_run_id =
  if use_smart_update then
    smart_update_schedules schedules current_run_id
  else
    update_schedules_legacy schedules current_run_id

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

(* Create performance indexes *)
let ensure_performance_indexes () =
  let indexes = [
    "CREATE INDEX IF NOT EXISTS idx_contacts_state_birthday ON contacts(state, birth_date)";
    "CREATE INDEX IF NOT EXISTS idx_contacts_state_effective ON contacts(state, effective_date)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_lookup ON email_schedules(contact_id, email_type, scheduled_send_date)";
    "CREATE INDEX IF NOT EXISTS idx_schedules_status_date ON email_schedules(status, scheduled_send_date)";
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

(* Initialize database and ensure schema *)
let initialize_database () =
  match ensure_performance_indexes () with
  | Ok () -> Ok ()
  | Error err -> Error err

(* Close database connection *)
let close_database () =
  match !db_handle with
  | None -> ()
  | Some db ->
      ignore (Sqlite3.db_close db);
      db_handle := None 

(* Campaign database functions *)

(* Parse campaign_type_config from database row with new fields *)
let parse_campaign_type_config_row = function
  | [name; respect_exclusion_windows; enable_followups; days_before_event; target_all_contacts; priority; active; spread_evenly; skip_failed_underwriting] ->
      (try
        Some {
          name;
          respect_exclusion_windows = (respect_exclusion_windows = "1");
          enable_followups = (enable_followups = "1");
          days_before_event = int_of_string days_before_event;
          target_all_contacts = (target_all_contacts = "1");
          priority = int_of_string priority;
          active = (active = "1");
          spread_evenly = (spread_evenly = "1");
          skip_failed_underwriting = (skip_failed_underwriting = "1");
        }
      with _ -> None)
  | [name; respect_exclusion_windows; enable_followups; days_before_event; target_all_contacts; priority; active; spread_evenly] ->
      (* Backward compatibility for old schema without skip_failed_underwriting *)
      (try
        Some {
          name;
          respect_exclusion_windows = (respect_exclusion_windows = "1");
          enable_followups = (enable_followups = "1");
          days_before_event = int_of_string days_before_event;
          target_all_contacts = (target_all_contacts = "1");
          priority = int_of_string priority;
          active = (active = "1");
          spread_evenly = (spread_evenly = "1");
          skip_failed_underwriting = false;
        }
      with _ -> None)
  | _ -> None

(* Parse campaign_instance from database row with new fields *)
let parse_campaign_instance_row = function
  | [id_str; campaign_type; instance_name; email_template; sms_template; active_start_date; active_end_date; spread_start_date; spread_end_date; target_states; target_carriers; metadata; created_at; updated_at] ->
      (try
        let id = int_of_string id_str in
        let active_start_date_opt = 
          if active_start_date = "" || active_start_date = "NULL" then None
          else Some (parse_date active_start_date)
        in
        let active_end_date_opt = 
          if active_end_date = "" || active_end_date = "NULL" then None
          else Some (parse_date active_end_date)
        in
        let spread_start_date_opt = 
          if spread_start_date = "" || spread_start_date = "NULL" then None
          else Some (parse_date spread_start_date)
        in
        let spread_end_date_opt = 
          if spread_end_date = "" || spread_end_date = "NULL" then None
          else Some (parse_date spread_end_date)
        in
        let email_template_opt = if email_template = "" || email_template = "NULL" then None else Some email_template in
        let sms_template_opt = if sms_template = "" || sms_template = "NULL" then None else Some sms_template in
        let target_states_opt = if target_states = "" || target_states = "NULL" then None else Some target_states in
        let target_carriers_opt = if target_carriers = "" || target_carriers = "NULL" then None else Some target_carriers in
        let metadata_opt = if metadata = "" || metadata = "NULL" then None else Some metadata in
        Some {
          id;
          campaign_type;
          instance_name;
          email_template = email_template_opt;
          sms_template = sms_template_opt;
          active_start_date = active_start_date_opt;
          active_end_date = active_end_date_opt;
          spread_start_date = spread_start_date_opt;
          spread_end_date = spread_end_date_opt;
          target_states = target_states_opt;
          target_carriers = target_carriers_opt;
          metadata = metadata_opt;
          created_at = parse_datetime created_at;
          updated_at = parse_datetime updated_at;
        }
      with _ -> None)
  | [id_str; campaign_type; instance_name; email_template; sms_template; active_start_date; active_end_date; spread_start_date; spread_end_date; metadata; created_at; updated_at] ->
      (* Backward compatibility for old schema without targeting fields *)
      (try
        let id = int_of_string id_str in
        let active_start_date_opt = 
          if active_start_date = "" || active_start_date = "NULL" then None
          else Some (parse_date active_start_date)
        in
        let active_end_date_opt = 
          if active_end_date = "" || active_end_date = "NULL" then None
          else Some (parse_date active_end_date)
        in
        let spread_start_date_opt = 
          if spread_start_date = "" || spread_start_date = "NULL" then None
          else Some (parse_date spread_start_date)
        in
        let spread_end_date_opt = 
          if spread_end_date = "" || spread_end_date = "NULL" then None
          else Some (parse_date spread_end_date)
        in
        let email_template_opt = if email_template = "" || email_template = "NULL" then None else Some email_template in
        let sms_template_opt = if sms_template = "" || sms_template = "NULL" then None else Some sms_template in
        let metadata_opt = if metadata = "" || metadata = "NULL" then None else Some metadata in
        Some {
          id;
          campaign_type;
          instance_name;
          email_template = email_template_opt;
          sms_template = sms_template_opt;
          active_start_date = active_start_date_opt;
          active_end_date = active_end_date_opt;
          spread_start_date = spread_start_date_opt;
          spread_end_date = spread_end_date_opt;
          target_states = None;
          target_carriers = None;
          metadata = metadata_opt;
          created_at = parse_datetime created_at;
          updated_at = parse_datetime updated_at;
        }
      with _ -> None)
  | _ -> None

(* Parse contact_campaign from database row *)
let parse_contact_campaign_row = function
  | [id_str; contact_id_str; campaign_instance_id_str; trigger_date; status; metadata; created_at; updated_at] ->
      (try
        let id = int_of_string id_str in
        let contact_id = int_of_string contact_id_str in
        let campaign_instance_id = int_of_string campaign_instance_id_str in
        let trigger_date_opt = 
          if trigger_date = "" || trigger_date = "NULL" then None
          else Some (parse_date trigger_date)
        in
        let metadata_opt = if metadata = "" || metadata = "NULL" then None else Some metadata in
        Some {
          id;
          contact_id;
          campaign_instance_id;
          trigger_date = trigger_date_opt;
          status;
          metadata = metadata_opt;
          created_at = parse_datetime created_at;
          updated_at = parse_datetime updated_at;
        }
      with _ -> None)
  | _ -> None

(* Get active campaign instances for current date - updated for new fields *)
let get_active_campaign_instances () =
  let today = current_date () in
  let today_str = string_of_date today in
  
  let query = Printf.sprintf {|
    SELECT id, campaign_type, instance_name, 
           COALESCE(email_template, '') as email_template, 
           COALESCE(sms_template, '') as sms_template,
           COALESCE(active_start_date, '') as active_start_date, 
           COALESCE(active_end_date, '') as active_end_date, 
           COALESCE(spread_start_date, '') as spread_start_date, 
           COALESCE(spread_end_date, '') as spread_end_date,
           COALESCE(target_states, '') as target_states,
           COALESCE(target_carriers, '') as target_carriers,
           COALESCE(metadata, '') as metadata, 
           created_at, updated_at
    FROM campaign_instances
    WHERE (active_start_date IS NULL OR active_start_date <= '%s')
    AND (active_end_date IS NULL OR active_end_date >= '%s')
    ORDER BY id
  |} today_str today_str in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let instances = List.filter_map parse_campaign_instance_row rows in
      Ok instances

(* Get campaign type configuration - updated for new fields *)
let get_campaign_type_config campaign_type_name =
  let query = Printf.sprintf {|
    SELECT name, 
           COALESCE(respect_exclusion_windows, 1) as respect_exclusion_windows, 
           COALESCE(enable_followups, 1) as enable_followups, 
           COALESCE(days_before_event, 0) as days_before_event,
           COALESCE(target_all_contacts, 0) as target_all_contacts, 
           COALESCE(priority, 10) as priority, 
           COALESCE(active, 1) as active, 
           COALESCE(spread_evenly, 0) as spread_evenly,
           COALESCE(skip_failed_underwriting, 0) as skip_failed_underwriting
    FROM campaign_types
    WHERE name = '%s' AND COALESCE(active, 1) = 1
  |} campaign_type_name in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok [row] ->
      (match parse_campaign_type_config_row row with
       | Some config -> Ok config
       | None -> Error (ParseError "Invalid campaign type config"))
  | Ok [] -> Error (ParseError "Campaign type not found")
  | Ok _ -> Error (ParseError "Multiple campaign types found")

(* Get contact campaigns for a specific campaign instance *)
let get_contact_campaigns_for_instance campaign_instance_id =
  let query = Printf.sprintf {|
    SELECT id, contact_id, campaign_instance_id, trigger_date, status, metadata, created_at, updated_at
    FROM contact_campaigns
    WHERE campaign_instance_id = %d
    AND status = 'pending'
    ORDER BY contact_id
  |} campaign_instance_id in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let contact_campaigns = List.filter_map parse_contact_campaign_row rows in
      Ok contact_campaigns

(* Get all contacts for "target_all_contacts" campaigns *)
let get_all_contacts_for_campaign () =
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

(* Helper function to parse state/carrier targeting strings *)
let parse_targeting_list targeting_str =
  if targeting_str = "" || targeting_str = "NULL" || targeting_str = "ALL" then
    `All
  else
    let items = String.split_on_char ',' targeting_str |> List.map String.trim in
    `Specific items

(* Check if contact matches campaign targeting criteria *)
let contact_matches_targeting contact campaign_instance =
  let state_matches = match campaign_instance.target_states with
    | None -> true
    | Some target_states ->
        (match parse_targeting_list target_states with
         | `All -> true
         | `Specific states ->
             (match contact.state with
              | None -> false
              | Some contact_state -> List.mem (string_of_state contact_state) states))
  in
  
  let carrier_matches = match campaign_instance.target_carriers with
    | None -> true
    | Some target_carriers ->
        (match parse_targeting_list target_carriers with
         | `All -> true
         | `Specific carriers ->
             (match contact.carrier with
              | None -> false
              | Some contact_carrier -> List.mem contact_carrier carriers))
  in
  
  state_matches && carrier_matches

(* Get all contacts for campaign with targeting filters *)
let get_contacts_for_campaign campaign_instance =
  match get_all_contacts () with
  | Error err -> Error err
  | Ok all_contacts ->
      let filtered_contacts = List.filter (fun contact -> contact_matches_targeting contact campaign_instance) all_contacts in
      Ok filtered_contacts
