open Scheduler.Types
open Scheduler.Date_time
open Scheduler.Dsl
open Scheduler.Contact
open Scheduler.Exclusion_window

(* Helper function to create a default organization config for tests *)
let default_org_config = {
  id = 1;
  name = "Test Organization";
  enable_post_window_emails = true;
  effective_date_first_email_months = 11;
  exclude_failed_underwriting_global = false;
  send_without_zipcode_for_universal = true;
  pre_exclusion_buffer_days = 60;
  birthday_days_before = 14;
  effective_date_days_before = 30;
  send_time_hour = 8;
  send_time_minute = 30;
  timezone = "America/Chicago";
  max_emails_per_period = 3;
  frequency_period_days = 30;
  size_profile = Medium;
  config_overrides = None;
}

let test_date_arithmetic () =
  let date = (2024, 1, 15) in
  let future_date = add_days date 30 in
  let (year, month, day) = future_date in
  assert (year = 2024 && month = 2 && day = 14);
  
  let past_date = add_days date (-10) in
  let (year, month, day) = past_date in
  assert (year = 2024 && month = 1 && day = 5);
  
  Printf.printf " Date arithmetic tests passed\n"

let test_next_anniversary () =
  let today = (2024, 6, 5) in
  let birthday = (1990, 12, 25) in
  let next_bday = next_anniversary today birthday in
  let (year, month, day) = next_bday in
  assert (year = 2024 && month = 12 && day = 25);
  
  let birthday_passed = (1990, 3, 15) in
  let next_bday_passed = next_anniversary today birthday_passed in
  let (year, month, day) = next_bday_passed in
  assert (year = 2025 && month = 3 && day = 15);
  
  Printf.printf " Anniversary calculation tests passed\n"

let test_leap_year_handling () =
  let leap_birthday = (1992, 2, 29) in
  let non_leap_today = (2023, 1, 1) in
  let next_bday = next_anniversary non_leap_today leap_birthday in
  let (year, month, day) = next_bday in
  assert (year = 2023 && month = 2 && day = 28);
  
  Printf.printf " Leap year handling tests passed\n"

let test_state_rules () =
  let ca_rule = rules_for_state CA in
  let ct_rule = rules_for_state CT in
  
  assert (match ca_rule with BirthdayWindow _ -> true | _ -> false);
  assert (match ct_rule with YearRoundExclusion -> true | _ -> false);
  
  Printf.printf " State rules tests passed\n"

let test_zip_code_lookup () =
  let _ = Scheduler.Zip_data.load_zip_data () in
  
  let ca_state = Scheduler.Zip_data.state_from_zip_code "90210" in
  Printf.printf "Debug: CA state = %s\n" (match ca_state with Some s -> string_of_state s | None -> "None");
  assert (ca_state = Some CA);
  
  let ny_state = Scheduler.Zip_data.state_from_zip_code "10001" in
  assert (ny_state = Some NY);
  
  Printf.printf " ZIP code lookup tests passed\n"

let test_contact_validation () =
  let valid_contact = {
    id = 1;
    email = "test@example.com";
    zip_code = Some "90210";
    state = Some CA;
    birthday = Some (1990, 6, 15);
    effective_date = Some (2020, 1, 1);
    carrier = None;
    failed_underwriting = false;
  } in
  
  assert (is_valid_for_scheduling valid_contact);
  
  let invalid_contact = {
    valid_contact with
    email = "invalid-email"
  } in
  
  assert (not (is_valid_for_scheduling invalid_contact));
  
  Printf.printf " Contact validation tests passed\n"

let test_exclusion_windows () =
  let org_config = {
    id = 1;
    name = "Test Organization";
    enable_post_window_emails = true;
    effective_date_first_email_months = 11;
    exclude_failed_underwriting_global = false;
    send_without_zipcode_for_universal = true;
    pre_exclusion_buffer_days = 60;
    birthday_days_before = 14;
    effective_date_days_before = 30;
    send_time_hour = 8;
    send_time_minute = 30;
    timezone = "America/Chicago";
    max_emails_per_period = 3;
    frequency_period_days = 30;
    size_profile = Medium;
    config_overrides = None;
  } in
  
  let ca_contact = {
    id = 1;
    email = "test@example.com";
    zip_code = Some "90210";
    state = Some CA;
    birthday = Some (1990, 6, 15);
    effective_date = None;
    carrier = None;
    failed_underwriting = false;
  } in
  
  let check_date = (2024, 6, 10) in
  let result = check_exclusion_window default_org_config ca_contact check_date in
  
  assert (match result with Excluded _ -> true | NotExcluded -> false);
  
  Printf.printf " Exclusion window tests passed\n"

let run_all_tests () =
  Printf.printf "Running email scheduler tests...\n";
  test_date_arithmetic ();
  test_next_anniversary ();
  test_leap_year_handling ();
  test_state_rules ();
  test_zip_code_lookup ();
  test_contact_validation ();
  test_exclusion_windows ();
  Printf.printf "All tests passed! \n"

let () = run_all_tests ()