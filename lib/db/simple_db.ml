open Types
open Simple_date

(* Simple database interface using shell commands *)
let db_path = "org-206.sqlite3"

let escape_string s =
  let s = String.map (function '\'' -> '"' | c -> c) s in
  "'" ^ s ^ "'"

let execute_sql sql =
  let cmd = Printf.sprintf "sqlite3 %s %s" db_path (escape_string sql) in
  let ic = Unix.open_process_in cmd in
  let result = ref [] in
  (try
    while true do
      let line = input_line ic in
      result := line :: !result
    done
  with End_of_file -> ());
  let _ = Unix.close_process_in ic in
  List.rev !result

let execute_sql_single sql =
  match execute_sql sql with
  | [line] -> Some line
  | [] -> None
  | _ -> failwith "Expected single result"

(* Get contacts from database *)
let get_contacts_from_db () =
  let sql = "SELECT id, email, zip_code, state, birth_date, effective_date FROM contacts WHERE email IS NOT NULL AND zip_code IS NOT NULL" in
  let rows = execute_sql sql in
  List.filter_map (fun row ->
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
  ) rows

(* Clear existing pre-scheduled emails *)
let clear_pre_scheduled_emails () =
  let sql = "DELETE FROM email_schedules WHERE status IN ('pre-scheduled', 'scheduled')" in
  let _ = execute_sql sql in
  ()

(* Insert email schedules *)
let insert_email_schedule schedule =
  let scheduled_date_str = string_of_date schedule.scheduled_date in
  let scheduled_time_str = string_of_time schedule.scheduled_time in
  let status_str = match schedule.status with
    | PreScheduled -> "pre-scheduled"
    | Skipped _reason -> "skipped"
    | _ -> "unknown"
  in
  let sql = Printf.sprintf 
    "INSERT INTO email_schedules (contact_id, email_type, scheduled_send_date, scheduled_send_time, status, skip_reason, scheduler_run_id, created_at, updated_at) VALUES (%d, '%s', '%s', '%s', '%s', '%s', '%s', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
    schedule.contact_id
    (string_of_email_type schedule.email_type)
    scheduled_date_str
    scheduled_time_str
    status_str
    (match schedule.status with Skipped reason -> reason | _ -> "")
    schedule.scheduler_run_id
  in
  let _ = execute_sql sql in
  ()

(* Insert batch of email schedules *)
let insert_email_schedules schedules =
  List.iter insert_email_schedule schedules

(* Get contact count *)
let get_contact_count () =
  match execute_sql_single "SELECT COUNT(*) FROM contacts WHERE email IS NOT NULL AND zip_code IS NOT NULL" with
  | Some count_str -> int_of_string count_str
  | None -> 0

(* Get sent emails for followup logic *)
let get_sent_emails_for_followup () =
  let sql = "SELECT contact_id, email_type, actual_send_datetime FROM email_schedules WHERE status = 'sent' AND actual_send_datetime > datetime('now', '-35 days')" in
  let rows = execute_sql sql in
  List.filter_map (fun row ->
    let parts = String.split_on_char '|' row in
    match parts with
    | [contact_id_str; email_type; send_datetime] ->
        (try
          let contact_id = int_of_string contact_id_str in
          Some (contact_id, email_type, send_datetime)
        with _ -> None)
    | _ -> None
  ) rows

(* Check if contact has clicks *)
let contact_has_clicks contact_id =
  let sql = Printf.sprintf "SELECT COUNT(*) FROM tracking_clicks WHERE contact_id = %d" contact_id in
  match execute_sql_single sql with
  | Some count_str -> int_of_string count_str > 0
  | None -> false

(* Check if contact answered health questions *)
let contact_answered_health_questions contact_id =
  let sql = Printf.sprintf "SELECT COUNT(*) FROM contact_events WHERE contact_id = %d AND event_type = 'eligibility_answered'" contact_id in
  match execute_sql_single sql with
  | Some count_str -> int_of_string count_str > 0
  | None -> false