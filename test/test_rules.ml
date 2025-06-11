open Alcotest
open Scheduler.Types
open Scheduler.Exclusion_window

(* Helper function to create a test contact *)
let make_contact ?(state=None) ?(birthday=None) ?(effective_date=None) () =
  {
    id = 1;
    email = "test@example.com";
    zip_code = Some "12345";
    state = state;
    birthday = birthday;
    effective_date = effective_date;
    carrier = None;
    failed_underwriting = false;
  }

(* Helper function to create a default organization config *)
let make_org_config () = {
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

(* Helper function to create a date *)
let make_date year month day = (year, month, day)

let test_ca_birthday_exclusion () =
  let org_config = make_org_config () in
  let contact = make_contact 
    ~state:(Some CA) 
    ~birthday:(Some (make_date 1990 6 15)) () in
  
  (* Test cases for CA: 30 days before, 60 days after birthday *)
  
  (* Inside exclusion window - 20 days before birthday *)
  let check_date = make_date 2024 5 26 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded { reason; _ } -> 
       let () = check string "Expected CA birthday exclusion" 
         "Birthday exclusion window for CA" reason in ()
   | NotExcluded -> 
       let () = fail "Should be excluded during CA birthday window" in ());
  
  (* Outside exclusion window - 40 days before birthday *)
  let check_date = make_date 2024 5 6 in
  (match check_exclusion_window org_config contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Should not be excluded 40 days before birthday");
  
  (* Inside exclusion window - 50 days after birthday *)
  let check_date = make_date 2024 8 4 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded { reason; _ } -> 
       let () = check string "Expected CA birthday exclusion" 
         "Birthday exclusion window for CA" reason in ()
   | NotExcluded -> 
       let () = fail "Should be excluded 50 days after CA birthday" in ());
  
  (* Outside exclusion window - 70 days after birthday *)
  let check_date = make_date 2024 8 24 in
  (match check_exclusion_window org_config contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Should not be excluded 70 days after birthday")

let test_nv_birthday_exclusion () =
  let org_config = make_org_config () in
  let contact = make_contact 
    ~state:(Some NV) 
    ~birthday:(Some (make_date 1990 6 15)) () in
  
  (* Test NV special rule: use_month_start=true, 0 days before, 60 days after *)
  
  (* Inside exclusion window - birthday month *)
  let check_date = make_date 2024 6 20 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded { reason; _ } -> 
       let () = check string "Expected NV birthday exclusion" 
         "Birthday exclusion window for NV" reason in ()
   | NotExcluded -> 
       let () = fail "Should be excluded during NV birthday month" in ());
  
  (* Outside exclusion window - month before *)
  let check_date = make_date 2024 5 20 in
  (match check_exclusion_window org_config contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Should not be excluded in month before birthday")

let test_mo_effective_date_exclusion () =
  let org_config = make_org_config () in
  let contact = make_contact 
    ~state:(Some MO) 
    ~effective_date:(Some (make_date 2020 8 10)) () in
  
  (* Test MO: 30 days before, 33 days after effective date *)
  
  (* Inside exclusion window - 20 days before effective date *)
  let check_date = make_date 2024 7 21 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded { reason; _ } -> 
       let () = check string "Expected MO effective date exclusion" 
         "Effective date exclusion window for MO" reason in ()
   | NotExcluded -> 
       let () = fail "Should be excluded during MO effective date window" in ());
  
  (* Outside exclusion window - 40 days before effective date *)
  let check_date = make_date 2024 7 1 in
  (match check_exclusion_window org_config contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Should not be excluded 40 days before effective date");
  
  (* Inside exclusion window - 30 days after effective date *)
  let check_date = make_date 2024 9 9 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded { reason; _ } -> 
       let () = check string "Expected MO effective date exclusion" 
         "Effective date exclusion window for MO" reason in ()
   | NotExcluded -> 
       let () = fail "Should be excluded 30 days after MO effective date" in ());
  
  (* Outside exclusion window - 40 days after effective date *)
  let check_date = make_date 2024 9 19 in
  (match check_exclusion_window org_config contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Should not be excluded 40 days after effective date")

let test_year_round_exclusion_states () =
  let org_config = make_org_config () in
  let ny_contact = make_contact ~state:(Some NY) () in
  let ct_contact = make_contact ~state:(Some CT) () in
  let ma_contact = make_contact ~state:(Some MA) () in
  let wa_contact = make_contact ~state:(Some WA) () in
  
  let check_date = make_date 2024 7 15 in
  
  (* Test NY year-round exclusion *)
  (match check_exclusion_window org_config ny_contact check_date with
   | Excluded { reason; window_end = None; _ } -> 
       let () = check string "Expected NY year-round exclusion" 
         "Year-round exclusion for NY" reason in ()
   | _ -> fail "NY should have year-round exclusion");
  
  (* Test CT year-round exclusion *)
  (match check_exclusion_window org_config ct_contact check_date with
   | Excluded { reason; window_end = None; _ } -> 
       let () = check string "Expected CT year-round exclusion" 
         "Year-round exclusion for CT" reason in ()
   | _ -> fail "CT should have year-round exclusion");
  
  (* Test MA year-round exclusion *)
  (match check_exclusion_window org_config ma_contact check_date with
   | Excluded { reason; window_end = None; _ } -> 
       let () = check string "Expected MA year-round exclusion" 
         "Year-round exclusion for MA" reason in ()
   | _ -> fail "MA should have year-round exclusion");
  
  (* Test WA year-round exclusion *)
  (match check_exclusion_window org_config wa_contact check_date with
   | Excluded { reason; window_end = None; _ } -> 
       let () = check string "Expected WA year-round exclusion" 
         "Year-round exclusion for WA" reason in ()
   | _ -> fail "WA should have year-round exclusion")

let test_leap_year_scenarios () =
  let org_config = make_org_config () in
  (* Test leap year birthday handling *)
  let leap_year_contact = make_contact 
    ~state:(Some CA) 
    ~birthday:(Some (make_date 1992 2 29)) () in
  
  (* Check behavior in non-leap year *)
  let check_date = make_date 2023 2 28 in
  (match check_exclusion_window org_config leap_year_contact check_date with
   | NotExcluded | Excluded _ -> () (* Both are acceptable - test that it doesn't crash *));
  
  let check_date = make_date 2023 3 1 in
  (match check_exclusion_window org_config leap_year_contact check_date with
   | NotExcluded | Excluded _ -> () (* Both are acceptable - test that it doesn't crash *))

let test_boundary_conditions () =
  let org_config = make_org_config () in
  let contact = make_contact 
    ~state:(Some CA) 
    ~birthday:(Some (make_date 1990 6 15)) () in
  
  (* Test exactly on birthday *)
  let check_date = make_date 2024 6 15 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded _ -> ()
   | NotExcluded -> fail "Should be excluded exactly on birthday");
  
  (* Test exactly 30 days before (boundary of CA window) *)
  let check_date = make_date 2024 5 16 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded _ -> ()
   | NotExcluded -> fail "Should be excluded exactly 30 days before birthday");
  
  (* Test exactly 60 days after (boundary of CA window) *)
  let check_date = make_date 2024 8 14 in
  (match check_exclusion_window org_config contact check_date with
   | Excluded _ -> ()
   | NotExcluded -> fail "Should be excluded exactly 60 days after birthday")

let test_no_exclusion_states () =
  let org_config = make_org_config () in
  let other_contact = make_contact 
    ~state:(Some (Other "XX")) 
    ~birthday:(Some (make_date 1990 6 15)) () in
  
  let check_date = make_date 2024 6 15 in
  (match check_exclusion_window org_config other_contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Other states should have no exclusion")

let test_missing_data () =
  let org_config = make_org_config () in
  (* Contact with no state *)
  let no_state_contact = make_contact 
    ~state:None 
    ~birthday:(Some (make_date 1990 6 15)) () in
  
  let check_date = make_date 2024 6 15 in
  (match check_exclusion_window org_config no_state_contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Contact with no state should not be excluded");
  
  (* Contact with no birthday *)
  let no_birthday_contact = make_contact 
    ~state:(Some CA) 
    ~birthday:None () in
  
  (match check_exclusion_window org_config no_birthday_contact check_date with
   | NotExcluded -> ()
   | Excluded _ -> fail "Contact with no birthday should not be excluded")

(* Test suite definition *)
let exclusion_window_tests = [
  test_case "CA birthday exclusion rules" `Quick test_ca_birthday_exclusion;
  test_case "NV birthday exclusion with month_start" `Quick test_nv_birthday_exclusion;
  test_case "MO effective date exclusion rules" `Quick test_mo_effective_date_exclusion;
  test_case "Year-round exclusion states (NY, CT, MA, WA)" `Quick test_year_round_exclusion_states;
  test_case "Leap year birthday scenarios" `Quick test_leap_year_scenarios;
  test_case "Boundary conditions" `Quick test_boundary_conditions;
  test_case "No exclusion states" `Quick test_no_exclusion_states;
  test_case "Missing data handling" `Quick test_missing_data;
]

let () =
  run "Exclusion Window Rules" [
    "exclusion_window", exclusion_window_tests;
  ]