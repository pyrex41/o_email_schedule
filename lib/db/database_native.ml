open Types
open Simple_date

(* Native high-performance database interface using proper SQLite bindings *)

let db_handle = ref None
let db_path = ref "org-206.sqlite3"

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

(* Get existing schedules for comparison *)
let get_existing_schedules_for_comparison () =
  let query = {|
    SELECT contact_id, email_type, scheduled_send_date, scheduled_send_time, 
           status, skip_reason, batch_id, created_at
    FROM email_schedules 
    WHERE status IN ('pre-scheduled', 'scheduled', 'skipped')
    ORDER BY contact_id, email_type
  |} in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let existing_schedules = List.filter_map (fun row ->
        match row with
        | [contact_id_str; email_type; scheduled_date; scheduled_time; status; skip_reason_val; batch_id; created_at] ->
            (try
              Some ({
                contact_id = int_of_string contact_id_str;
                email_type = email_type;
                scheduled_date = scheduled_date;
                scheduled_time = scheduled_time;
                status = status;
                skip_reason = skip_reason_val;
                scheduler_run_id = batch_id;
                created_at = created_at;
              } : existing_schedule_record)
            with _ -> None)
        | _ -> None
      ) rows in
      Ok existing_schedules

(* Check if schedule content actually changed (ignoring metadata) *)
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
  
  (* Compare meaningful fields *)
  existing_record.email_type <> new_email_type_str ||
  existing_record.scheduled_date <> new_scheduled_date_str ||
  existing_record.scheduled_time <> new_scheduled_time_str ||
  existing_record.status <> new_status_str ||
  existing_record.skip_reason <> new_skip_reason

(* Find existing schedule for a new schedule *)
let find_existing_schedule existing_schedules (new_schedule : email_schedule) =
  let new_email_type_str = string_of_email_type new_schedule.email_type in
  let new_scheduled_date_str = string_of_date new_schedule.scheduled_date in
  
  List.find_opt (fun existing ->
    existing.contact_id = new_schedule.contact_id &&
    existing.email_type = new_email_type_str &&
    existing.scheduled_date = new_scheduled_date_str
  ) existing_schedules

(* Smart batch insert that preserves scheduler_run_id when content unchanged *)
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
            
            let total_inserted = ref 0 in
            let unchanged_count = ref 0 in
            let changed_count = ref 0 in
            let new_count = ref 0 in
            
            (* Process each schedule with smart logic *)
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
              
              let current_year = (current_date()).year in
              let (event_year, event_month, event_day) = match schedule.email_type with
                | Anniversary Birthday -> (current_year, 1, 1)
                | Anniversary EffectiveDate -> (current_year, 1, 2)
                | Anniversary AEP -> (current_year, 9, 15)
                | _ -> (current_year, 1, 1)
              in
              
              (* Determine which scheduler_run_id to use *)
              let (scheduler_run_id_to_use, _change_type) = 
                match find_existing_schedule existing_schedules schedule with
                | None -> 
                    (* New schedule *)
                    incr new_count;
                    (current_run_id, "NEW")
                | Some existing ->
                    if schedule_content_changed existing schedule then (
                      (* Content changed, use new run_id *)
                      incr changed_count;
                      (current_run_id, "CHANGED")
                    ) else (
                      (* Content unchanged, preserve existing run_id *)
                      incr unchanged_count;
                      (existing.scheduler_run_id, "UNCHANGED")
                    )
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
                scheduler_run_id_to_use
              in
              
              match Sqlite3.exec db insert_sql with
              | Sqlite3.Rc.OK -> incr total_inserted
              | rc -> failwith ("Insert failed: " ^ Sqlite3.Rc.to_string rc)
            ) schedules;
            
            (* Commit transaction *)
            (match Sqlite3.exec db "COMMIT" with
             | Sqlite3.Rc.OK -> 
                 Printf.printf "✅ Smart update complete: %d total, %d new, %d changed, %d unchanged\n%!" 
                   !total_inserted !new_count !changed_count !unchanged_count;
                 Ok !total_inserted
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
          
          let current_year = (current_date()).year in
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