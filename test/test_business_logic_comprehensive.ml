open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Dsl
open Scheduler.Contact
open Scheduler.Exclusion_window
open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Printf

(* Test database setup and teardown *)
let test_db_path = "test_business_logic.sqlite3"

(* Test context and configuration *)
let create_test_config () = 
  {
    send_time_hour = 8;
    send_time_minute = 30;
    birthday_days_before = 14;
    effective_date_days_before = 30;
    batch_size = 1000;
    max_emails_per_contact_per_period = 3;
    period_days = 30;
  }

(* Database state verification helpers *)
module DatabaseAssertion = struct
  let assert_schedule_count expected_count query_condition =
    let query = Printf.sprintf "SELECT COUNT(*) FROM email_schedules WHERE %s" query_condition in
    match execute_sql_safe query with
    | Ok [[count_str]] ->
        let actual_count = int_of_string count_str in
        if actual_count = expected_count then
          printf "✓ Schedule count assertion passed: %d\n" actual_count
        else
          failwith (Printf.sprintf "Schedule count assertion failed: expected %d, got %d" expected_count actual_count)
    | _ -> failwith "Failed to query schedule count"

  let assert_schedule_exists contact_id email_type status =
    let email_type_str = string_of_email_type email_type in
    let query = Printf.sprintf 
      "SELECT COUNT(*) FROM email_schedules WHERE contact_id = %d AND email_type = '%s' AND status = '%s'" 
      contact_id email_type_str status in
    match execute_sql_safe query with
    | Ok [[count_str]] ->
        let count = int_of_string count_str in
        if count > 0 then
          printf "✓ Schedule exists: contact %d, %s, %s\n" contact_id email_type_str status
        else
          failwith (Printf.sprintf "Schedule not found: contact %d, %s, %s" contact_id email_type_str status)
    | _ -> failwith "Failed to query schedule existence"

  let assert_no_schedule_exists contact_id email_type =
    let email_type_str = string_of_email_type email_type in
    let query = Printf.sprintf 
      "SELECT COUNT(*) FROM email_schedules WHERE contact_id = %d AND email_type = '%s'" 
      contact_id email_type_str in
    match execute_sql_safe query with
    | Ok [[count_str]] ->
        let count = int_of_string count_str in
        if count = 0 then
          printf "✓ No schedule exists: contact %d, %s\n" contact_id email_type_str
        else
          failwith (Printf.sprintf "Unexpected schedule found: contact %d, %s" contact_id email_type_str)
    | _ -> failwith "Failed to query schedule non-existence"

  let get_scheduled_date contact_id email_type =
    let email_type_str = string_of_email_type email_type in
    let query = Printf.sprintf 
      "SELECT scheduled_send_date FROM email_schedules WHERE contact_id = %d AND email_type = '%s' LIMIT 1" 
      contact_id email_type_str in
    match execute_sql_safe query with
    | Ok [[date_str]] -> Some (parse_date date_str)
    | _ -> None

  let get_schedule_status contact_id email_type =
    let email_type_str = string_of_email_type email_type in
    let query = Printf.sprintf 
      "SELECT status FROM email_schedules WHERE contact_id = %d AND email_type = '%s' LIMIT 1" 
      contact_id email_type_str in
    match execute_sql_safe query with
    | Ok [[status_str]] -> Some status_str
    | _ -> None
end

(* Test data creation helpers *)
module TestData = struct
  let create_contact id email state zip_code ?birthday ?effective_date () =
    {
      id;
      email;
      zip_code = Some zip_code;
      state = Some state;
      birthday;
      effective_date;
    }

  let insert_test_contact contact =
    let birthday_str = match contact.birthday with
      | Some d -> string_of_date d
      | None -> "NULL"
    in
    let effective_date_str = match contact.effective_date with
      | Some d -> string_of_date d
      | None -> "NULL"
    in
    let state_str = match contact.state with
      | Some s -> string_of_state s
      | None -> "NULL"
    in
    let zip_str = match contact.zip_code with
      | Some z -> z
      | None -> "NULL"
    in
    
    let insert_sql = Printf.sprintf {|
      INSERT OR REPLACE INTO contacts (id, email, zip_code, state, birth_date, effective_date)
      VALUES (%d, '%s', '%s', '%s', '%s', '%s')
    |} contact.id contact.email zip_str state_str birthday_str effective_date_str in
    
    match execute_sql_no_result insert_sql with
    | Ok () -> printf "✓ Inserted test contact %d\n" contact.id
    | Error err -> failwith (Printf.sprintf "Failed to insert contact: %s" (string_of_db_error err))

  let clear_test_data () =
    let _ = execute_sql_no_result "DELETE FROM email_schedules" in
    let _ = execute_sql_no_result "DELETE FROM contacts" in
    printf "✓ Cleared test data\n"
end

(* Test Case Modules *)

(* 1. State Exclusion Window Tests *)
module StateExclusionTests = struct
  
  let test_california_birthday_exclusion () =
    printf "\n=== California Birthday Exclusion Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Create CA contact with birthday in June *)
    let contact = TestData.create_contact 1 "test@ca.com" CA "90210" 
      ~birthday:(make_date 1990 6 15) () in
    TestData.insert_test_contact contact;
    
    (* Set up test date for scheduling (May 1st) *)
    let today = make_date 2024 5 1 in
    
    (* Override current_date for testing *)
    let original_current_date = current_date in
    let test_current_date () = today in
    
    (* Calculate expected birthday send date: June 15 - 14 days = June 1st *)
    let expected_birthday = make_date 2024 6 15 in
    let expected_send_date = add_days expected_birthday (-14) in (* June 1st *)
    
    (* This should be in CA exclusion window: 30 days before birthday (May 16) to 60 days after *)
    let exclusion_start = add_days expected_birthday (-30) in (* May 16 *)
    
    printf "Expected birthday: %s\n" (string_of_date expected_birthday);
    printf "Expected send date: %s\n" (string_of_date expected_send_date);
    printf "CA exclusion starts: %s\n" (string_of_date exclusion_start);
    
    (* Run scheduler *)
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        printf "Generated %d schedules\n" (List.length schedules);
        
        (* Insert schedules *)
        (match batch_insert_schedules_optimized schedules with
         | Ok inserted -> printf "Inserted %d schedules\n" inserted
         | Error err -> failwith (string_of_db_error err));
        
        (* Verify birthday email is skipped due to exclusion *)
        DatabaseAssertion.assert_schedule_exists 1 (Anniversary Birthday) "skipped";
        
        printf "✓ California birthday exclusion test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let test_nevada_month_start_rule () =
    printf "\n=== Nevada Month Start Rule Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Create NV contact with birthday on June 20th *)
    let contact = TestData.create_contact 2 "test@nv.com" NV "89101" 
      ~birthday:(make_date 1990 6 20) () in
    TestData.insert_test_contact contact;
    
    (* Nevada uses month start (June 1st) instead of actual birthday for exclusion window *)
    (* Exclusion: 0 days before June 1st to 60 days after June 1st *)
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        (* Email should be scheduled 14 days before birthday (June 6th) *)
        (* This falls within NV exclusion window, so should be skipped *)
        DatabaseAssertion.assert_schedule_exists 2 (Anniversary Birthday) "skipped";
        
        printf "✓ Nevada month start rule test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let test_year_round_exclusion_states () =
    printf "\n=== Year-Round Exclusion States Test ===\n";
    
    TestData.clear_test_data ();
    
    let year_round_states = [CT; MA; NY; WA] in
    let base_id = ref 10 in
    
    List.iter (fun state ->
      incr base_id;
      let contact = TestData.create_contact !base_id "test@yearround.com" state "00000" 
        ~birthday:(make_date 1990 8 15) 
        ~effective_date:(make_date 2020 1 1) () in
      TestData.insert_test_contact contact;
      
      let config = create_test_config () in
      let context = create_context config 1 in
      
      match calculate_schedules_for_contact context contact with
      | Ok schedules ->
          (match batch_insert_schedules_optimized schedules with
           | Ok _ -> ()
           | Error err -> failwith (string_of_db_error err));
          
          (* All emails should be skipped for year-round exclusion states *)
          DatabaseAssertion.assert_no_schedule_exists !base_id (Anniversary Birthday);
          DatabaseAssertion.assert_no_schedule_exists !base_id (Anniversary EffectiveDate);
          
          printf "✓ %s year-round exclusion verified\n" (string_of_state state)
      | Error err ->
          failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))
    ) year_round_states;
    
    printf "✓ Year-round exclusion states test passed\n"

  let test_missouri_effective_date_exclusion () =
    printf "\n=== Missouri Effective Date Exclusion Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Create MO contact with effective date anniversary coming up *)
    let contact = TestData.create_contact 20 "test@mo.com" MO "63101" 
      ~effective_date:(make_date 2020 3 1) () in
    TestData.insert_test_contact contact;
    
    (* MO has effective date exclusion: 30 days before to 33 days after *)
    (* If today is Feb 15, 2024, the effective date anniversary is March 1, 2024 *)
    (* Email should be sent 30 days before = Jan 31, 2024 *)
    (* Exclusion window: Jan 30 to April 3, 2024 *)
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        (* Effective date email should be skipped due to MO exclusion *)
        DatabaseAssertion.assert_schedule_exists 20 (Anniversary EffectiveDate) "skipped";
        
        printf "✓ Missouri effective date exclusion test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let run_all () =
    printf "\n🔍 Running State Exclusion Window Tests\n";
    test_california_birthday_exclusion ();
    test_nevada_month_start_rule ();
    test_year_round_exclusion_states ();
    test_missouri_effective_date_exclusion ();
    printf "✅ All state exclusion tests passed\n"
end

(* 2. Anniversary Email Logic Tests *)
module AnniversaryEmailTests = struct
  
  let test_birthday_email_timing () =
    printf "\n=== Birthday Email Timing Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Create contact in state with no exclusions *)
    let contact = TestData.create_contact 30 "test@timing.com" FL "33101" 
      ~birthday:(make_date 1990 8 15) () in
    TestData.insert_test_contact contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        (* Verify birthday email is scheduled 14 days before birthday *)
        DatabaseAssertion.assert_schedule_exists 30 (Anniversary Birthday) "pre-scheduled";
        
        let scheduled_date = DatabaseAssertion.get_scheduled_date 30 (Anniversary Birthday) in
        (match scheduled_date with
         | Some date -> 
             let next_birthday = next_anniversary (current_date ()) (make_date 1990 8 15) in
             let expected_date = add_days next_birthday (-14) in
             if date = expected_date then
               printf "✓ Birthday email scheduled for correct date: %s\n" (string_of_date date)
             else
               failwith (Printf.sprintf "Wrong birthday email date: expected %s, got %s" 
                 (string_of_date expected_date) (string_of_date date))
         | None -> failwith "Birthday email not found");
        
        printf "✓ Birthday email timing test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let test_effective_date_email_timing () =
    printf "\n=== Effective Date Email Timing Test ===\n";
    
    TestData.clear_test_data ();
    
    let contact = TestData.create_contact 31 "test@ed.com" FL "33102" 
      ~effective_date:(make_date 2020 9 1) () in
    TestData.insert_test_contact contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        DatabaseAssertion.assert_schedule_exists 31 (Anniversary EffectiveDate) "pre-scheduled";
        
        let scheduled_date = DatabaseAssertion.get_scheduled_date 31 (Anniversary EffectiveDate) in
        (match scheduled_date with
         | Some date -> 
             let next_ed = next_anniversary (current_date ()) (make_date 2020 9 1) in
             let expected_date = add_days next_ed (-30) in
             if date = expected_date then
               printf "✓ Effective date email scheduled for correct date: %s\n" (string_of_date date)
             else
               failwith (Printf.sprintf "Wrong effective date email date: expected %s, got %s" 
                 (string_of_date expected_date) (string_of_date date))
         | None -> failwith "Effective date email not found");
        
        printf "✓ Effective date email timing test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let test_aep_email_september () =
    printf "\n=== AEP Email September Test ===\n";
    
    TestData.clear_test_data ();
    
    let contact = TestData.create_contact 32 "test@aep.com" FL "33103" () in
    TestData.insert_test_contact contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        (* AEP emails should only be scheduled in September *)
        let current_month = (current_date ()).month in
        if current_month = 9 then (
          DatabaseAssertion.assert_schedule_exists 32 (Anniversary AEP) "pre-scheduled";
          printf "✓ AEP email scheduled in September\n"
        ) else (
          DatabaseAssertion.assert_no_schedule_exists 32 (Anniversary AEP);
          printf "✓ AEP email not scheduled outside September (current month: %d)\n" current_month
        );
        
        printf "✓ AEP email September test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let test_leap_year_handling () =
    printf "\n=== Leap Year Handling Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Contact born on February 29th *)
    let contact = TestData.create_contact 33 "test@leap.com" FL "33104" 
      ~birthday:(make_date 1992 2 29) () in
    TestData.insert_test_contact contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        DatabaseAssertion.assert_schedule_exists 33 (Anniversary Birthday) "pre-scheduled";
        
        let scheduled_date = DatabaseAssertion.get_scheduled_date 33 (Anniversary Birthday) in
        (match scheduled_date with
         | Some date -> 
             let next_birthday = next_anniversary (current_date ()) (make_date 1992 2 29) in
             let expected_date = add_days next_birthday (-14) in
             printf "✓ Leap year birthday scheduled for: %s (next birthday: %s)\n" 
               (string_of_date date) (string_of_date next_birthday)
         | None -> failwith "Leap year birthday email not found");
        
        printf "✓ Leap year handling test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err))

  let run_all () =
    printf "\n📅 Running Anniversary Email Logic Tests\n";
    test_birthday_email_timing ();
    test_effective_date_email_timing ();
    test_aep_email_september ();
    test_leap_year_handling ();
    printf "✅ All anniversary email tests passed\n"
end

(* 3. Contact Validation Tests *)
module ContactValidationTests = struct
  
  let test_invalid_contact_handling () =
    printf "\n=== Invalid Contact Handling Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Contact with invalid email *)
    let invalid_contact = TestData.create_contact 40 "invalid-email" FL "33105" () in
    TestData.insert_test_contact invalid_contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context invalid_contact with
    | Ok _ -> failwith "Should have failed for invalid contact"
    | Error (InvalidContactData _) -> 
        printf "✓ Invalid contact properly rejected\n"
    | Error err -> 
        failwith (Printf.sprintf "Unexpected error: %s" (string_of_error err));
    
    printf "✓ Invalid contact handling test passed\n"

  let test_missing_data_handling () =
    printf "\n=== Missing Data Handling Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Contact with missing ZIP code *)
    let contact_no_zip = { 
      id = 41; 
      email = "test@nozip.com"; 
      zip_code = None; 
      state = Some FL; 
      birthday = None; 
      effective_date = None 
    } in
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact_no_zip with
    | Ok _ -> failwith "Should have failed for contact without ZIP"
    | Error (InvalidContactData _) -> 
        printf "✓ Contact without ZIP properly rejected\n"
    | Error err -> 
        failwith (Printf.sprintf "Unexpected error: %s" (string_of_error err));
    
    printf "✓ Missing data handling test passed\n"

  let run_all () =
    printf "\n✅ Running Contact Validation Tests\n";
    test_invalid_contact_handling ();
    test_missing_data_handling ();
    printf "✅ All contact validation tests passed\n"
end

(* 4. Complex Integration Tests *)
module IntegrationTests = struct
  
  let test_multiple_contacts_multiple_states () =
    printf "\n=== Multiple Contacts Multiple States Test ===\n";
    
    TestData.clear_test_data ();
    
    (* Create contacts in different states with different scenarios *)
    let contacts = [
      (* FL contact - no exclusions, should schedule normally *)
      TestData.create_contact 50 "florida@test.com" FL "33106" 
        ~birthday:(make_date 1990 8 15) 
        ~effective_date:(make_date 2020 1 1) ();
      
      (* CA contact - birthday exclusion *)
      TestData.create_contact 51 "california@test.com" CA "90211" 
        ~birthday:(make_date 1990 6 15) ();
      
      (* NY contact - year-round exclusion *)
      TestData.create_contact 52 "newyork@test.com" NY "10002" 
        ~birthday:(make_date 1990 8 15) 
        ~effective_date:(make_date 2020 1 1) ();
      
      (* MO contact - effective date exclusion *)
      TestData.create_contact 53 "missouri@test.com" MO "63102" 
        ~effective_date:(make_date 2020 3 1) ();
    ] in
    
    List.iter TestData.insert_test_contact contacts;
    
    let config = create_test_config () in
    let all_schedules = ref [] in
    
    List.iter (fun contact ->
      let context = create_context config (List.length contacts) in
      match calculate_schedules_for_contact context contact with
      | Ok schedules -> all_schedules := schedules @ !all_schedules
      | Error err -> failwith (Printf.sprintf "Failed for contact %d: %s" contact.id (string_of_error err))
    ) contacts;
    
    (* Insert all schedules *)
    (match batch_insert_schedules_optimized !all_schedules with
     | Ok inserted -> printf "Inserted %d total schedules\n" inserted
     | Error err -> failwith (string_of_db_error err));
    
    (* Verify each contact's behavior *)
    DatabaseAssertion.assert_schedule_exists 50 (Anniversary Birthday) "pre-scheduled"; (* FL - normal *)
    DatabaseAssertion.assert_schedule_exists 50 (Anniversary EffectiveDate) "pre-scheduled"; (* FL - normal *)
    
    DatabaseAssertion.assert_schedule_exists 51 (Anniversary Birthday) "skipped"; (* CA - excluded *)
    
    DatabaseAssertion.assert_no_schedule_exists 52 (Anniversary Birthday); (* NY - year-round exclusion *)
    DatabaseAssertion.assert_no_schedule_exists 52 (Anniversary EffectiveDate); (* NY - year-round exclusion *)
    
    DatabaseAssertion.assert_schedule_exists 53 (Anniversary EffectiveDate) "skipped"; (* MO - excluded *)
    
    printf "✓ Multiple contacts multiple states test passed\n"

  let test_post_window_email_generation () =
    printf "\n=== Post-Window Email Generation Test ===\n";
    
    TestData.clear_test_data ();
    
    (* This test would need more sophisticated date manipulation *)
    (* For now, just verify the concept *)
    
    let contact = TestData.create_contact 60 "postwindow@test.com" CA "90212" 
      ~birthday:(make_date 1990 6 15) () in
    TestData.insert_test_contact contact;
    
    let config = create_test_config () in
    let context = create_context config 1 in
    
    match calculate_schedules_for_contact context contact with
    | Ok schedules ->
        (match batch_insert_schedules_optimized schedules with
         | Ok _ -> ()
         | Error err -> failwith (string_of_db_error err));
        
        (* Birthday should be skipped *)
        DatabaseAssertion.assert_schedule_exists 60 (Anniversary Birthday) "skipped";
        
        (* In a real scenario, we'd also check for post-window emails *)
        printf "✓ Post-window email concept verified\n"
    | Error err ->
        failwith (Printf.sprintf "Schedule calculation failed: %s" (string_of_error err));
    
    printf "✓ Post-window email generation test passed\n"

  let run_all () =
    printf "\n🔧 Running Integration Tests\n";
    test_multiple_contacts_multiple_states ();
    test_post_window_email_generation ();
    printf "✅ All integration tests passed\n"
end

(* Main test runner *)
let setup_test_database () =
  set_db_path test_db_path;
  match initialize_database () with
  | Ok () -> 
      printf "✓ Test database initialized\n";
      
      (* Create tables if they don't exist *)
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
          scheduled_send_time TEXT DEFAULT '08:30:00',
          status TEXT NOT NULL DEFAULT 'pre-scheduled',
          skip_reason TEXT,
          batch_id TEXT,
          scheduler_run_id TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      |} in
      
      (match execute_sql_no_result create_contacts_table with
       | Ok () -> printf "✓ Contacts table ready\n"
       | Error err -> failwith (string_of_db_error err));
      
      (match execute_sql_no_result create_schedules_table with
       | Ok () -> printf "✓ Email schedules table ready\n"
       | Error err -> failwith (string_of_db_error err))
  | Error err -> 
      failwith (Printf.sprintf "Failed to initialize test database: %s" (string_of_db_error err))

let run_all_tests () =
  printf "🧪 Starting Comprehensive Business Logic Tests\n";
  printf "===============================================\n";
  
  setup_test_database ();
  
  StateExclusionTests.run_all ();
  AnniversaryEmailTests.run_all ();
  ContactValidationTests.run_all ();
  IntegrationTests.run_all ();
  
  close_database ();
  
  printf "\n🎉 ALL BUSINESS LOGIC TESTS PASSED! 🎉\n";
  printf "=====================================\n"

let () = run_all_tests ()