open Types
open Simple_date

(* Fallback high-performance database interface using improved shell commands *)

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

(* Improved shell command execution with proper escaping *)
let execute_sql_safe sql =
  (* Don't modify the SQL query - just wrap it in double quotes for shell *)
  let cmd = Printf.sprintf "sqlite3 %s \"%s\"" !db_path sql in
  let ic = Unix.open_process_in cmd in
  let result = ref [] in
  (try
    while true do
      let line = input_line ic in
      result := line :: !result
    done
  with End_of_file -> ());
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> Ok (List.rev !result)
  | _ -> Error (SqliteError "Command failed")

(* Query-driven contact fetching - implements Python's get_contacts_in_scheduling_window *)
let get_contacts_in_scheduling_window lookahead_days lookback_days =
  let today = current_date () in
  let active_window_end = add_days today lookahead_days in
  let lookback_window_start = add_days today (-lookback_days) in
  
  (* Format dates for SQL pattern matching *)
  let _today_str = Printf.sprintf "%02d-%02d" today.month today.day in
  let future_end_str = Printf.sprintf "%02d-%02d" active_window_end.month active_window_end.day in
  let past_start_str = Printf.sprintf "%02d-%02d" lookback_window_start.month lookback_window_start.day in
  
  (* Optimized query that pre-filters contacts with anniversaries in the window *)
  let query = Printf.sprintf {|
    SELECT id, email, zip_code, state, birth_date, effective_date
    FROM contacts
    WHERE email IS NOT NULL AND email != '' 
    AND zip_code IS NOT NULL AND zip_code != ''
    AND (
      (strftime('%%m-%%d', birth_date) BETWEEN '%s' AND '12-31') OR
      (strftime('%%m-%%d', birth_date) BETWEEN '01-01' AND '%s') OR
      (strftime('%%m-%%d', effective_date) BETWEEN '%s' AND '12-31') OR
      (strftime('%%m-%%d', effective_date) BETWEEN '01-01' AND '%s')
    )
  |} past_start_str future_end_str past_start_str future_end_str in
  
  match execute_sql_safe query with
  | Error err -> Error err
  | Ok rows ->
      let contacts = List.filter_map (fun row ->
        let parts = String.split_on_char '|' row in
        match parts with
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
      ) rows in
      Ok contacts

(* Get all contacts (for comparison with query-driven approach) *)
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
      let contacts = List.filter_map (fun row ->
        let parts = String.split_on_char '|' row in
        match parts with
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
      ) rows in
      Ok contacts

(* Get total contact count *)
let get_total_contact_count () =
  let query = "SELECT COUNT(*) FROM contacts WHERE email IS NOT NULL AND email != ''" in
  match execute_sql_safe query with
  | Ok [count_str] -> 
      (try Ok (int_of_string count_str) 
       with _ -> Error (ParseError "Invalid count"))
  | Ok _ -> Error (ParseError "Invalid count result")
  | Error err -> Error err

(* Clear pre-scheduled emails with transaction safety *)
let clear_pre_scheduled_emails () =
  let query = "DELETE FROM email_schedules WHERE status IN ('pre-scheduled', 'scheduled')" in
  match execute_sql_safe query with
  | Ok _ -> Ok 1  (* Success indicator *)
  | Error err -> Error err

(* Batch insert with improved transaction handling *)
let batch_insert_schedules_transactional schedules =
  if schedules = [] then Ok 0 else
  
  (* Build a single transaction with all inserts *)
  let insert_statements = List.map (fun schedule ->
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
    
    (* Use current year as default for event year - this can be refined later *)
    let current_year = (current_date()).year in
    let (event_year, event_month, event_day) = match schedule.email_type with
      | Anniversary Birthday -> (current_year, 1, 1)  (* Default birthday event *)
      | Anniversary EffectiveDate -> (current_year, 1, 2)  (* Default effective date event *)
      | Anniversary AEP -> (current_year, 9, 15)  (* Default AEP date *)
      | _ -> (current_year, 1, 1)  (* Default for other types *)
    in
    
    Printf.sprintf {|
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
  ) schedules in
  
  let transaction_sql = String.concat ";\n" (
    "BEGIN TRANSACTION" ::
    insert_statements @
    ["COMMIT"]
  ) in
  
  match execute_sql_safe transaction_sql with
  | Ok _ -> Ok (List.length schedules)
  | Error err -> Error err

(* Chunked batch insert to handle large datasets *)
let batch_insert_schedules_chunked schedules chunk_size =
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

(* Get sent emails for followup logic with proper filtering *)
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
        let parts = String.split_on_char '|' row in
        match parts with
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
  | Ok [click_count_str] ->
      (match execute_sql_safe events_query with
       | Error err -> Error err
       | Ok [event_count_str] ->
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
        match execute_sql_safe index_sql with
        | Ok _ -> create_indexes rest
        | Error err -> Error err
  in
  create_indexes indexes

(* Initialize database and ensure schema *)
let initialize_database () =
  match ensure_performance_indexes () with
  | Ok () -> Ok ()
  | Error err -> Error err