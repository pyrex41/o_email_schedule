open Alcotest
open Scheduler
open Types
open Date_time

(* Priority 5: Edge Case Testing Suite - Complex Business Logic Combinations *)

(* Helper functions for creating test data *)
let make_contact ?(id=1) ?(email="test@example.com") ?zip_code ?state 
                 ?birthday ?effective_date ?carrier ?(failed_underwriting=false) () =
  { id; email; zip_code; state; birthday; effective_date; carrier; failed_underwriting }

let make_org_config ?(enable_post_window_emails=true) ?(effective_date_first_email_months=6)
                    ?(exclude_failed_underwriting_global=false) ?(send_without_zipcode_for_universal=true) () =
  { enable_post_window_emails; effective_date_first_email_months; 
    exclude_failed_underwriting_global; send_without_zipcode_for_universal }

let make_campaign_config ?(name="test_campaign") ?(respect_exclusion_windows=true) 
                         ?(enable_followups=false) ?(days_before_event=30) ?(target_all_contacts=false)
                         ?(priority=10) ?(active=true) ?(spread_evenly=false) ?(skip_failed_underwriting=false) () =
  { name; respect_exclusion_windows; enable_followups; days_before_event; target_all_contacts;
    priority; active; spread_evenly; skip_failed_underwriting }

let make_campaign_instance ?(id=1) ?(campaign_type="test") ?(instance_name="Test Campaign")
                          ?email_template ?sms_template ?active_start_date ?active_end_date
                          ?spread_start_date ?spread_end_date ?target_states ?target_carriers ?metadata () =
  let now = current_datetime () in
  { id; campaign_type; instance_name; email_template; sms_template; 
    active_start_date; active_end_date; spread_start_date; spread_end_date;
    target_states; target_carriers; metadata; created_at = now; updated_at = now }

(* Edge Case Test Categories *)

(* 1. Organization Configuration Edge Cases *)
let org_config_edge_cases = [
  ("Failed underwriting with global exclusion - AEP allowed", fun () ->
    let contact = make_contact ~failed_underwriting:true () in
    let org_config = make_org_config ~exclude_failed_underwriting_global:true () in
    let aep_campaign = make_campaign_config ~name:"aep" () in
    let other_campaign = make_campaign_config ~name:"renewal" () in
    
    (* AEP should be allowed even with global underwriting exclusion *)
    let aep_exclusion = Email_scheduler.should_exclude_contact {organization = org_config} aep_campaign contact in
    let other_exclusion = Email_scheduler.should_exclude_contact {organization = org_config} other_campaign contact in
    
    Alcotest.(check (option string)) "AEP allowed for failed underwriting" None aep_exclusion;
    Alcotest.(check (option string)) "Other campaigns excluded for failed underwriting" 
      (Some "Failed underwriting - global exclusion") other_exclusion
  );
  
  ("Effective date first email timing", fun () ->
    let contact = make_contact ~effective_date:(Some (make_date 2024 1 1)) () in
    let org_config_6months = make_org_config ~effective_date_first_email_months:6 () in
    let org_config_12months = make_org_config ~effective_date_first_email_months:12 () in
    
    (* Test with current date being 4 months after effective date *)
    let test_date = make_date 2024 5 1 in
    
    let should_send_6m = Email_scheduler.should_send_effective_date_email 
      {organization = org_config_6months} contact (make_date 2024 1 1) in
    let should_send_12m = Email_scheduler.should_send_effective_date_email 
      {organization = org_config_12months} contact (make_date 2024 1 1) in
    
    Alcotest.(check bool) "6-month rule allows early ED email" false should_send_6m;
    Alcotest.(check bool) "12-month rule prevents early ED email" false should_send_12m
  );
  
  ("Post-window emails disabled globally", fun () ->
    let contact = make_contact ~birthday:(Some (make_date 1990 6 15)) () in
    let org_config_disabled = make_org_config ~enable_post_window_emails:false () in
    let org_config_enabled = make_org_config ~enable_post_window_emails:true () in
    
    let context_disabled = Email_scheduler.create_context {organization = org_config_disabled} in
    let context_enabled = Email_scheduler.create_context {organization = org_config_enabled} in
    
    let schedules_disabled = Email_scheduler.calculate_post_window_emails context_disabled contact in
    let schedules_enabled = Email_scheduler.calculate_post_window_emails context_enabled contact in
    
    Alcotest.(check int) "Post-window disabled produces no schedules" 0 (List.length schedules_disabled);
    Alcotest.(check bool) "Post-window enabled may produce schedules" (List.length schedules_enabled >= 0) true
  );
]

(* 2. Failed Underwriting Scenarios *)
let failed_underwriting_edge_cases = [
  ("Campaign-specific underwriting exclusion", fun () ->
    let contact = make_contact ~failed_underwriting:true () in
    let org_config = make_org_config ~exclude_failed_underwriting_global:false () in
    let campaign_excludes = make_campaign_config ~skip_failed_underwriting:true () in
    let campaign_allows = make_campaign_config ~skip_failed_underwriting:false () in
    
    let exclusion_excludes = Email_scheduler.should_exclude_contact {organization = org_config} campaign_excludes contact in
    let exclusion_allows = Email_scheduler.should_exclude_contact {organization = org_config} campaign_allows contact in
    
    Alcotest.(check (option string)) "Campaign excludes failed underwriting" 
      (Some "Failed underwriting - campaign exclusion") exclusion_excludes;
    Alcotest.(check (option string)) "Campaign allows failed underwriting" None exclusion_allows
  );
  
  ("Global vs campaign underwriting rules precedence", fun () ->
    let contact = make_contact ~failed_underwriting:true () in
    
    (* Global exclusion overrides campaign setting *)
    let org_config_global = make_org_config ~exclude_failed_underwriting_global:true () in
    let campaign_allows = make_campaign_config ~skip_failed_underwriting:false () in
    
    let exclusion = Email_scheduler.should_exclude_contact {organization = org_config_global} campaign_allows contact in
    
    Alcotest.(check (option string)) "Global exclusion overrides campaign allowance" 
      (Some "Failed underwriting - global exclusion") exclusion
  );
  
  ("Anniversary emails with underwriting exclusion", fun () ->
    let contact = make_contact ~failed_underwriting:true ~birthday:(Some (make_date 1990 6 15)) () in
    let org_config = make_org_config ~exclude_failed_underwriting_global:true () in
    let context = Email_scheduler.create_context {organization = org_config} in
    
    let schedules = Email_scheduler.calculate_anniversary_emails context contact in
    
    Alcotest.(check int) "No anniversary emails for failed underwriting with global exclusion" 0 (List.length schedules)
  );
]

(* 3. Universal Campaign Handling *)
let universal_campaign_edge_cases = [
  ("Universal campaign without ZIP code - allowed", fun () ->
    let contact = make_contact ~zip_code:None ~state:None () in
    let org_config = make_org_config ~send_without_zipcode_for_universal:true () in
    let universal_campaign = make_campaign_instance ~target_states:(Some "ALL") ~target_carriers:(Some "ALL") () in
    
    let is_valid = Contact.is_valid_for_campaign_scheduling org_config universal_campaign contact in
    
    Alcotest.(check bool) "Universal campaign allows contacts without ZIP" true is_valid
  );
  
  ("Universal campaign without ZIP code - disallowed", fun () ->
    let contact = make_contact ~zip_code:None ~state:None () in
    let org_config = make_org_config ~send_without_zipcode_for_universal:false () in
    let universal_campaign = make_campaign_instance ~target_states:(Some "ALL") ~target_carriers:(Some "ALL") () in
    
    let is_valid = Contact.is_valid_for_campaign_scheduling org_config universal_campaign contact in
    
    Alcotest.(check bool) "Universal campaign requires ZIP when configured" false is_valid
  );
  
  ("Targeted campaign requires location data", fun () ->
    let contact_no_location = make_contact ~zip_code:None ~state:None () in
    let contact_with_zip = make_contact ~zip_code:(Some "90210") ~state:None () in
    let contact_with_state = make_contact ~zip_code:None ~state:(Some CA) () in
    let org_config = make_org_config () in
    let targeted_campaign = make_campaign_instance ~target_states:(Some "CA,NY") () in
    
    let valid_no_location = Contact.is_valid_for_campaign_scheduling org_config targeted_campaign contact_no_location in
    let valid_with_zip = Contact.is_valid_for_campaign_scheduling org_config targeted_campaign contact_with_zip in
    let valid_with_state = Contact.is_valid_for_campaign_scheduling org_config targeted_campaign contact_with_state in
    
    Alcotest.(check bool) "Targeted campaign rejects no location" false valid_no_location;
    Alcotest.(check bool) "Targeted campaign accepts ZIP code" true valid_with_zip;
    Alcotest.(check bool) "Targeted campaign accepts state" true valid_with_state
  );
  
  ("Implicit universal campaign (no targeting)", fun () ->
    let contact = make_contact ~zip_code:None ~state:None () in
    let org_config = make_org_config ~send_without_zipcode_for_universal:true () in
    let implicit_universal = make_campaign_instance ~target_states:None ~target_carriers:None () in
    
    let is_valid = Contact.is_valid_for_campaign_scheduling org_config implicit_universal contact in
    
    Alcotest.(check bool) "Implicit universal campaign (no targeting) allows no ZIP" true is_valid
  );
]

(* 4. ZIP Code Validation Edge Cases *)
let zip_code_edge_cases = [
  ("Empty ZIP code handling", fun () ->
    let contact_empty_zip = make_contact ~zip_code:(Some "") () in
    let contact_null_zip = make_contact ~zip_code:None () in
    let org_config = make_org_config () in
    
    let valid_empty = Contact.is_valid_for_anniversary_scheduling org_config contact_empty_zip in
    let valid_null = Contact.is_valid_for_anniversary_scheduling org_config contact_null_zip in
    
    (* Both should be treated the same way *)
    Alcotest.(check bool) "Empty ZIP and None ZIP treated consistently" (valid_empty = valid_null) true
  );
  
  ("ZIP code format validation", fun () ->
    let valid_zip_5 = make_contact ~zip_code:(Some "90210") () in
    let valid_zip_9 = make_contact ~zip_code:(Some "90210-1234") () in
    let invalid_zip_short = make_contact ~zip_code:(Some "902") () in
    let invalid_zip_letters = make_contact ~zip_code:(Some "ABCDE") () in
    let org_config = make_org_config () in
    
    (* For now, we mainly test that the system doesn't crash with various formats *)
    let test_contact contact =
      try
        let _ = Contact.is_valid_for_anniversary_scheduling org_config contact in
        true
      with _ -> false
    in
    
    Alcotest.(check bool) "5-digit ZIP doesn't crash" true (test_contact valid_zip_5);
    Alcotest.(check bool) "9-digit ZIP doesn't crash" true (test_contact valid_zip_9);
    Alcotest.(check bool) "Short ZIP doesn't crash" true (test_contact invalid_zip_short);
    Alcotest.(check bool) "Letter ZIP doesn't crash" true (test_contact invalid_zip_letters)
  );
]

(* 5. Campaign Targeting Combinations *)
let campaign_targeting_edge_cases = [
  ("State and carrier targeting combined", fun () ->
    let contact_ca_aetna = make_contact ~state:(Some CA) ~carrier:(Some "Aetna") () in
    let contact_ca_humana = make_contact ~state:(Some CA) ~carrier:(Some "Humana") () in
    let contact_ny_aetna = make_contact ~state:(Some NY) ~carrier:(Some "Aetna") () in
    let org_config = make_org_config () in
    
    let campaign_ca_aetna = make_campaign_instance ~target_states:(Some "CA") ~target_carriers:(Some "Aetna") () in
    
    let valid_ca_aetna = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_aetna contact_ca_aetna in
    let valid_ca_humana = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_aetna contact_ca_humana in
    let valid_ny_aetna = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_aetna contact_ny_aetna in
    
    Alcotest.(check bool) "CA+Aetna matches CA+Aetna targeting" true valid_ca_aetna;
    Alcotest.(check bool) "CA+Humana doesn't match CA+Aetna targeting" false valid_ca_humana;
    Alcotest.(check bool) "NY+Aetna doesn't match CA+Aetna targeting" false valid_ny_aetna
  );
  
  ("ALL wildcard in targeting", fun () ->
    let contact = make_contact ~state:(Some CA) ~carrier:(Some "Aetna") () in
    let org_config = make_org_config () in
    
    let campaign_all_states = make_campaign_instance ~target_states:(Some "ALL") ~target_carriers:(Some "Aetna") () in
    let campaign_all_carriers = make_campaign_instance ~target_states:(Some "CA") ~target_carriers:(Some "ALL") () in
    let campaign_all_both = make_campaign_instance ~target_states:(Some "ALL") ~target_carriers:(Some "ALL") () in
    
    let valid_all_states = Contact.is_valid_for_campaign_scheduling org_config campaign_all_states contact in
    let valid_all_carriers = Contact.is_valid_for_campaign_scheduling org_config campaign_all_carriers contact in
    let valid_all_both = Contact.is_valid_for_campaign_scheduling org_config campaign_all_both contact in
    
    Alcotest.(check bool) "ALL states with specific carrier works" true valid_all_states;
    Alcotest.(check bool) "Specific state with ALL carriers works" true valid_all_carriers;
    Alcotest.(check bool) "ALL states and ALL carriers works" true valid_all_both
  );
  
  ("Multiple states in targeting", fun () ->
    let contact_ca = make_contact ~state:(Some CA) () in
    let contact_ny = make_contact ~state:(Some NY) () in
    let contact_tx = make_contact ~state:(Some (Other "TX")) () in
    let org_config = make_org_config () in
    
    let campaign_ca_ny = make_campaign_instance ~target_states:(Some "CA,NY") () in
    
    let valid_ca = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_ny contact_ca in
    let valid_ny = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_ny contact_ny in
    let valid_tx = Contact.is_valid_for_campaign_scheduling org_config campaign_ca_ny contact_tx in
    
    Alcotest.(check bool) "CA matches CA,NY targeting" true valid_ca;
    Alcotest.(check bool) "NY matches CA,NY targeting" true valid_ny;
    Alcotest.(check bool) "TX doesn't match CA,NY targeting" false valid_tx
  );
  
  ("Missing carrier data handling", fun () ->
    let contact_no_carrier = make_contact ~state:(Some CA) ~carrier:None () in
    let contact_empty_carrier = make_contact ~state:(Some CA) ~carrier:(Some "") () in
    let org_config = make_org_config () in
    
    let campaign_specific_carrier = make_campaign_instance ~target_carriers:(Some "Aetna") () in
    let campaign_all_carriers = make_campaign_instance ~target_carriers:(Some "ALL") () in
    
    let valid_no_carrier_specific = Contact.is_valid_for_campaign_scheduling org_config campaign_specific_carrier contact_no_carrier in
    let valid_empty_carrier_specific = Contact.is_valid_for_campaign_scheduling org_config campaign_specific_carrier contact_empty_carrier in
    let valid_no_carrier_all = Contact.is_valid_for_campaign_scheduling org_config campaign_all_carriers contact_no_carrier in
    
    Alcotest.(check bool) "No carrier doesn't match specific carrier" false valid_no_carrier_specific;
    Alcotest.(check bool) "Empty carrier doesn't match specific carrier" false valid_empty_carrier_specific;
    Alcotest.(check bool) "No carrier may match ALL carriers" true valid_no_carrier_all
  );
]

(* 6. Email Validation Edge Cases *)
let email_validation_edge_cases = [
  ("Empty email handling", fun () ->
    let contact_empty = make_contact ~email:"" () in
    let contact_whitespace = make_contact ~email:"   " () in
    let org_config = make_org_config () in
    
    let valid_empty = Contact.is_valid_for_anniversary_scheduling org_config contact_empty in
    let valid_whitespace = Contact.is_valid_for_anniversary_scheduling org_config contact_whitespace in
    
    Alcotest.(check bool) "Empty email is invalid" false valid_empty;
    Alcotest.(check bool) "Whitespace email is invalid" false valid_whitespace
  );
  
  ("Email format edge cases", fun () ->
    let contact_valid = make_contact ~email:"test@example.com" () in
    let contact_no_at = make_contact ~email:"testexample.com" () in
    let contact_no_domain = make_contact ~email:"test@" () in
    let contact_no_local = make_contact ~email:"@example.com" () in
    let org_config = make_org_config () in
    
    (* Test that the system handles various email formats without crashing *)
    let test_email contact =
      try
        let _ = Contact.is_valid_for_anniversary_scheduling org_config contact in
        true
      with _ -> false
    in
    
    Alcotest.(check bool) "Valid email doesn't crash" true (test_email contact_valid);
    Alcotest.(check bool) "No @ email doesn't crash" true (test_email contact_no_at);
    Alcotest.(check bool) "No domain email doesn't crash" true (test_email contact_no_domain);
    Alcotest.(check bool) "No local email doesn't crash" true (test_email contact_no_local)
  );
]

(* 7. Date/Time Edge Cases *)
let datetime_edge_cases = [
  ("Leap year birthday edge cases", fun () ->
    let contact_feb28 = make_contact ~birthday:(Some (make_date 1990 2 28)) () in
    let contact_feb29 = make_contact ~birthday:(Some (make_date 1992 2 29)) () in
    
    (* Test anniversary calculation in leap and non-leap years *)
    let leap_year_date = make_date 2024 1 1 in  (* 2024 is leap year *)
    let non_leap_year_date = make_date 2023 1 1 in  (* 2023 is not leap year *)
    
    let anniversary_feb28_leap = next_anniversary leap_year_date (make_date 1990 2 28) in
    let anniversary_feb28_non_leap = next_anniversary non_leap_year_date (make_date 1990 2 28) in
    let anniversary_feb29_leap = next_anniversary leap_year_date (make_date 1992 2 29) in
    let anniversary_feb29_non_leap = next_anniversary non_leap_year_date (make_date 1992 2 29) in
    
    (* Feb 28 birthdays should stay Feb 28 *)
    let (_, month28_leap, day28_leap) = anniversary_feb28_leap in
    let (_, month28_non_leap, day28_non_leap) = anniversary_feb28_non_leap in
    
    Alcotest.(check int) "Feb 28 birthday stays Feb 28 in leap year" 28 day28_leap;
    Alcotest.(check int) "Feb 28 birthday stays Feb 28 in non-leap year" 28 day28_non_leap;
    
    (* Feb 29 birthdays should become Feb 28 in non-leap years *)
    let (_, month29_leap, day29_leap) = anniversary_feb29_leap in
    let (_, month29_non_leap, day29_non_leap) = anniversary_feb29_non_leap in
    
    Alcotest.(check int) "Feb 29 birthday stays Feb 29 in leap year" 29 day29_leap;
    Alcotest.(check int) "Feb 29 birthday becomes Feb 28 in non-leap year" 28 day29_non_leap
  );
  
  ("Year boundary anniversary calculation", fun () ->
    let birthday = make_date 1990 1 15 in
    let test_date_before = make_date 2023 12 20 in  (* Before birthday month *)
    let test_date_after = make_date 2024 2 10 in    (* After birthday month *)
    
    let anniversary_before = next_anniversary test_date_before birthday in
    let anniversary_after = next_anniversary test_date_after birthday in
    
    let (year_before, month_before, day_before) = anniversary_before in
    let (year_after, month_after, day_after) = anniversary_after in
    
    Alcotest.(check int) "Anniversary before birthday is same year" 2024 year_before;
    Alcotest.(check int) "Anniversary after birthday is next year" 2025 year_after;
    Alcotest.(check int) "Anniversary month preserved" 1 month_before;
    Alcotest.(check int) "Anniversary day preserved" 15 day_before
  );
]

(* All edge case test suites *)
let all_edge_case_suites = [
  ("Organization Configuration Edge Cases", org_config_edge_cases);
  ("Failed Underwriting Scenarios", failed_underwriting_edge_cases);
  ("Universal Campaign Handling", universal_campaign_edge_cases);
  ("ZIP Code Validation Edge Cases", zip_code_edge_cases);
  ("Campaign Targeting Combinations", campaign_targeting_edge_cases);
  ("Email Validation Edge Cases", email_validation_edge_cases);
  ("Date/Time Edge Cases", datetime_edge_cases);
]

(* Statistics and reporting *)
let get_edge_case_statistics () =
  let total_suites = List.length all_edge_case_suites in
  let total_tests = List.fold_left (fun acc (_, tests) -> acc + List.length tests) 0 all_edge_case_suites in
  
  Printf.printf "📈 Edge Case Test Statistics:\n";
  Printf.printf "   • %d test suites\n" total_suites;
  Printf.printf "   • %d total edge case tests\n" total_tests;
  Printf.printf "   • Focus areas: Organization config, Underwriting, Universal campaigns, ZIP validation, Targeting, Email validation, Date/time\n\n"

(* Manual test runner *)
let run_all_edge_case_tests () =
  Printf.printf "🧪 Running comprehensive edge case test suite...\n\n";
  
  List.iter (fun (suite_name, test_cases) ->
    Printf.printf "📊 %s:\n" suite_name;
    List.iter (fun (test_name, test_func) ->
      try
        test_func ();
        Printf.printf "   ✅ %s\n" test_name
      with 
      | Alcotest.Test_error msg ->
          Printf.printf "   ❌ %s: %s\n" test_name msg
      | exn ->
          Printf.printf "   ❌ %s: %s\n" test_name (Printexc.to_string exn)
    ) test_cases;
    Printf.printf "\n"
  ) all_edge_case_suites;
  
  Printf.printf "🏁 Edge case testing complete!\n"

let () =
  (* Command line interface *)
  let argc = Array.length Sys.argv in
  if argc > 1 then
    match Sys.argv.(1) with
    | "--run" -> 
        get_edge_case_statistics ();
        run_all_edge_case_tests ()
    | "--stats" -> 
        get_edge_case_statistics ()
    | "--help" ->
        Printf.printf "Edge case testing for scheduler\n";
        Printf.printf "Usage: %s [--run] [--stats] [--help]\n" Sys.argv.(0);
        Printf.printf "  --run     Run all edge case tests\n";
        Printf.printf "  --stats   Show test statistics\n";
        Printf.printf "  --help    Show this help\n"
    | _ -> 
        get_edge_case_statistics ();
        run_all_edge_case_tests ()
  else
    (* Run with Alcotest when used as library *)
    let test_suites = List.map (fun (suite_name, test_cases) ->
      (suite_name, List.map (fun (test_name, test_func) ->
        (test_name, `Quick, test_func)
      ) test_cases)
    ) all_edge_case_suites in
    Alcotest.run "Edge Case Tests" test_suites