open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Dsl
open Scheduler.Contact
open Scheduler.Exclusion_window

let test_date_arithmetic () =
  let date = make_date 2024 1 15 in
  let future_date = add_days date 30 in
  assert (future_date.year = 2024 && future_date.month = 2 && future_date.day = 14);
  
  let past_date = add_days date (-10) in
  assert (past_date.year = 2024 && past_date.month = 1 && past_date.day = 5);
  
  Printf.printf " Date arithmetic tests passed\n"

let test_next_anniversary () =
  let today = make_date 2024 6 5 in
  let birthday = make_date 1990 12 25 in
  let next_bday = next_anniversary today birthday in
  assert (next_bday.year = 2024 && next_bday.month = 12 && next_bday.day = 25);
  
  let birthday_passed = make_date 1990 3 15 in
  let next_bday_passed = next_anniversary today birthday_passed in
  assert (next_bday_passed.year = 2025 && next_bday_passed.month = 3 && next_bday_passed.day = 15);
  
  Printf.printf " Anniversary calculation tests passed\n"

let test_leap_year_handling () =
  let leap_birthday = make_date 1992 2 29 in
  let non_leap_today = make_date 2023 1 1 in
  let next_bday = next_anniversary non_leap_today leap_birthday in
  assert (next_bday.year = 2023 && next_bday.month = 2 && next_bday.day = 28);
  
  Printf.printf " Leap year handling tests passed\n"

let test_state_rules () =
  let ca_rule = rules_for_state CA in
  let ct_rule = rules_for_state CT in
  
  assert (match ca_rule with BirthdayWindow _ -> true | _ -> false);
  assert (match ct_rule with YearRoundExclusion -> true | _ -> false);
  
  Printf.printf " State rules tests passed\n"

let test_zip_code_lookup () =
  let _ = Scheduler.Zip_data.load_zip_data () in
  
  let ca_state = Scheduler.Zip_data.state_from_zip_code "90210" in
  Printf.printf "Debug: CA state = %s\n" (match ca_state with Some s -> string_of_state s | None -> "None");
  assert (ca_state = Some CA);
  
  let ny_state = Scheduler.Zip_data.state_from_zip_code "10001" in
  assert (ny_state = Some NY);
  
  Printf.printf " ZIP code lookup tests passed\n"

let test_contact_validation () =
  let valid_contact = {
    id = 1;
    email = "test@example.com";
    zip_code = Some "90210";
    state = Some CA;
    birthday = Some (make_date 1990 6 15);
    effective_date = Some (make_date 2020 1 1);
  } in
  
  assert (is_valid_for_scheduling valid_contact);
  
  let invalid_contact = {
    valid_contact with
    email = "invalid-email"
  } in
  
  assert (not (is_valid_for_scheduling invalid_contact));
  
  Printf.printf " Contact validation tests passed\n"

let test_exclusion_windows () =
  let ca_contact = {
    id = 1;
    email = "test@example.com";
    zip_code = Some "90210";
    state = Some CA;
    birthday = Some (make_date 1990 6 15);
    effective_date = None;
  } in
  
  let check_date = make_date 2024 6 10 in
  let result = check_exclusion_window ca_contact check_date in
  
  assert (match result with Excluded _ -> true | NotExcluded -> false);
  
  Printf.printf " Exclusion window tests passed\n"

let run_all_tests () =
  Printf.printf "Running email scheduler tests...\n";
  test_date_arithmetic ();
  test_next_anniversary ();
  test_leap_year_handling ();
  test_state_rules ();
  test_zip_code_lookup ();
  test_contact_validation ();
  test_exclusion_windows ();
  Printf.printf "All tests passed! \n"

let () = run_all_tests ()