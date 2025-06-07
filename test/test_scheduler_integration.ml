open Alcotest
open Types
open Simple_date
open Email_scheduler

(* Test database setup *)
let setup_test_database () =
  (* Use in-memory database for testing *)
  Database.set_db_path ":memory:";
  
  (* Initialize the database schema *)
  let create_contacts_table = {|
    CREATE TABLE IF NOT EXISTS contacts (
      id INTEGER PRIMARY KEY,
      email TEXT NOT NULL,
      zip_code TEXT,
      state TEXT,
      birth_date TEXT,
      effective_date TEXT
    )
  |} in
  
  let create_schedules_table = {|
    CREATE TABLE IF NOT EXISTS email_schedules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      contact_id INTEGER NOT NULL,
      email_type TEXT NOT NULL,
      event_year INTEGER,
      event_month INTEGER,
      event_day INTEGER,
      scheduled_send_date TEXT NOT NULL,
      scheduled_send_time TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pre-scheduled',
      skip_reason TEXT DEFAULT '',
      batch_id TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (contact_id) REFERENCES contacts(id)
    )
  |} in
  
  match Database.execute_sql_no_result create_contacts_table with
  | Ok () -> 
      (match Database.execute_sql_no_result create_schedules_table with
       | Ok () -> Ok ()
       | Error err -> Error err)
  | Error err -> Error err

let insert_test_contact id email state birthday effective_date =
  let birthday_str = match birthday with 
    | Some date -> string_of_date date 
    | None -> "" 
  in
  let effective_date_str = match effective_date with 
    | Some date -> string_of_date date 
    | None -> "" 
  in
  let state_str = match state with 
    | Some s -> string_of_state s 
    | None -> "" 
  in
  
  let sql = Printf.sprintf {|
    INSERT INTO contacts (id, email, zip_code, state, birth_date, effective_date)
    VALUES (%d, '%s', '12345', '%s', '%s', '%s')
  |} id email state_str birthday_str effective_date_str in
  
  Database.execute_sql_no_result sql

(* Helper function to create a date *)
let make_date year month day = { year; month; day }

let test_ca_contact_exclusion () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert CA contact with birthday in exclusion window *)
      let birthday = make_date 1990 6 15 in
      match insert_test_contact 1 "ca_test@example.com" (Some CA) (Some birthday) None with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Calculate schedules for a date within exclusion window *)
          let check_date = make_date 2024 6 20 in (* 5 days after birthday *)
          match calculate_schedules_for_contact 1 (Anniversary Birthday) check_date "test_run_123" with
          | Error err -> fail ("Schedule calculation failed: " ^ Database.string_of_db_error err)
          | Ok schedule ->
              (* Should be skipped due to exclusion window *)
              (match schedule.status with
               | Skipped reason -> 
                   let () = check string "Expected CA exclusion reason" 
                     "Birthday exclusion window for CA" reason in ()
               | _ -> fail "CA contact should be skipped during exclusion window")

let test_mo_contact_effective_date_exclusion () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert MO contact with effective date in exclusion window *)
      let effective_date = make_date 2020 8 10 in
      match insert_test_contact 2 "mo_test@example.com" (Some MO) None (Some effective_date) with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Calculate schedules for a date within effective date exclusion window *)
          let check_date = make_date 2024 8 15 in (* 5 days after effective date anniversary *)
          match calculate_schedules_for_contact 2 (Anniversary EffectiveDate) check_date "test_run_456" with
          | Error err -> fail ("Schedule calculation failed: " ^ Database.string_of_db_error err)
          | Ok schedule ->
              (* Should be skipped due to exclusion window *)
              (match schedule.status with
               | Skipped reason -> 
                   let () = check string "Expected MO exclusion reason" 
                     "Effective date exclusion window for MO" reason in ()
               | _ -> fail "MO contact should be skipped during effective date exclusion window")

let test_non_excluded_contact () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert contact from state with no exclusion rules *)
      let birthday = make_date 1990 6 15 in
      match insert_test_contact 3 "other_test@example.com" (Some (Other "XX")) (Some birthday) None with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Calculate schedules for birthday *)
          let check_date = make_date 2024 6 15 in
          match calculate_schedules_for_contact 3 (Anniversary Birthday) check_date "test_run_789" with
          | Error err -> fail ("Schedule calculation failed: " ^ Database.string_of_db_error err)
          | Ok schedule ->
              (* Should be pre-scheduled *)
              (match schedule.status with
               | PreScheduled -> 
                   let () = check string "Expected correct scheduled date" 
                     (string_of_date check_date) (string_of_date schedule.scheduled_date) in ()
               | _ -> fail "Contact from non-excluded state should be pre-scheduled")

let test_ca_contact_outside_exclusion () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert CA contact *)
      let birthday = make_date 1990 6 15 in
      match insert_test_contact 4 "ca_outside_test@example.com" (Some CA) (Some birthday) None with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Calculate schedules for a date well outside exclusion window *)
          let check_date = make_date 2024 4 1 in (* Well before birthday exclusion window *)
          match calculate_schedules_for_contact 4 (Anniversary Birthday) check_date "test_run_abc" with
          | Error err -> fail ("Schedule calculation failed: " ^ Database.string_of_db_error err)
          | Ok schedule ->
              (* Should be pre-scheduled since we're outside exclusion window *)
              (match schedule.status with
               | PreScheduled -> 
                   (* Verify the scheduled date is the actual birthday *)
                   let expected_birthday = make_date 2024 6 15 in
                   let () = check string "Expected birthday as scheduled date" 
                     (string_of_date expected_birthday) (string_of_date schedule.scheduled_date) in ()
               | _ -> fail "CA contact outside exclusion window should be pre-scheduled")

let test_year_round_exclusion () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert NY contact (year-round exclusion) *)
      let birthday = make_date 1990 6 15 in
      match insert_test_contact 5 "ny_test@example.com" (Some NY) (Some birthday) None with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Calculate schedules for any date *)
          let check_date = make_date 2024 12 1 in (* Any date should be excluded *)
          match calculate_schedules_for_contact 5 (Anniversary Birthday) check_date "test_run_xyz" with
          | Error err -> fail ("Schedule calculation failed: " ^ Database.string_of_db_error err)
          | Ok schedule ->
              (* Should be skipped due to year-round exclusion *)
              (match schedule.status with
               | Skipped reason -> 
                   let () = check string "Expected NY year-round exclusion" 
                     "Year-round exclusion for NY" reason in ()
               | _ -> fail "NY contact should always be skipped due to year-round exclusion")

let test_missing_contact_data () =
  (* Setup database *)
  match setup_test_database () with
  | Error err -> fail ("Database setup failed: " ^ Database.string_of_db_error err)
  | Ok () ->
      
      (* Insert contact with missing birthday *)
      match insert_test_contact 6 "no_birthday@example.com" (Some CA) None None with
      | Error err -> fail ("Contact insert failed: " ^ Database.string_of_db_error err)
      | Ok () ->
          
          (* Try to calculate birthday schedule for contact without birthday *)
          let check_date = make_date 2024 6 15 in
          match calculate_schedules_for_contact 6 (Anniversary Birthday) check_date "test_run_missing" with
          | Error _ -> () (* Expected to fail - no birthday data *)
          | Ok schedule ->
              (* If it succeeds, should be skipped due to missing data *)
              (match schedule.status with
               | Skipped _ -> ()
               | _ -> fail "Contact without birthday should be skipped or cause error")

(* Test suite definition *)
let scheduler_integration_tests = [
  test_case "CA contact in exclusion window" `Quick test_ca_contact_exclusion;
  test_case "MO contact effective date exclusion" `Quick test_mo_contact_effective_date_exclusion;
  test_case "Non-excluded contact scheduling" `Quick test_non_excluded_contact;
  test_case "CA contact outside exclusion window" `Quick test_ca_contact_outside_exclusion;
  test_case "Year-round exclusion (NY)" `Quick test_year_round_exclusion;
  test_case "Missing contact data handling" `Quick test_missing_contact_data;
]

let () =
  run "Email Scheduler Integration Tests" [
    "scheduler_integration", scheduler_integration_tests;
  ]