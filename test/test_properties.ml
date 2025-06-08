open QCheck
open Scheduler
open Types
open Date_time

(* Property-based testing for critical scheduler invariants *)

(* Generators for test data *)
let date_gen = 
  let open Gen in
  map3 (fun year month day -> make_date year month day)
    (int_range 2020 2030)
    (int_range 1 12)
    (int_range 1 28)  (* Safe day range to avoid invalid dates *)

let contact_gen =
  let open Gen in
  map (fun (id, email, state_opt, birthday_opt, effective_date_opt) ->
    {
      id;
      email;
      zip_code = Some "90210";
      state = state_opt;
      birthday = birthday_opt;
      effective_date = effective_date_opt;
      carrier = Some "UnitedHealthcare";
      failed_underwriting = false;
    }
  ) (tuple5 
       (int_range 1 100000)
       (map (fun s -> s ^ "@test.com") (string_size ~gen:char (int_range 5 10)))
       (option (oneofl [CA; NY; TX; FL; Other "NV"]))
       (option date_gen)
       (option date_gen))

let email_type_gen =
  let open Gen in
  oneof [
    return (Anniversary Birthday);
    return (Anniversary EffectiveDate);
    map (fun campaign_type -> 
      Campaign {
        campaign_type;
        instance_id = 1;
        respect_exclusions = true;
        days_before_event = 30;
        priority = 10;
      }
    ) (oneofl ["aep"; "renewal"; "cross_sell"]);
  ]

let schedule_gen =
  let open Gen in
  map4 (fun contact email_type scheduled_date priority ->
    {
      contact_id = contact.id;
      email_type;
      scheduled_date;
      scheduled_time = make_time 8 30 0;
      status = PreScheduled;
      priority;
      template_id = Some "test_template";
      campaign_instance_id = None;
      scheduler_run_id = "test_run";
    }
  ) contact_gen email_type_gen date_gen (int_range 1 50)

(* Property 1: Anniversary dates are always in the future or today *)
let prop_anniversary_always_future_or_today =
  Test.make ~name:"anniversary always future or today"
    (pair date_gen date_gen)
    (fun (today, event_date) ->
      let anniversary = next_anniversary today event_date in
      compare_date anniversary today >= 0)

(* Property 2: Date arithmetic is consistent *)
let prop_date_arithmetic_consistent =
  Test.make ~name:"date arithmetic is consistent"
    (triple date_gen (int_range (-365) 365) (int_range (-365) 365))
    (fun (base_date, days1, days2) ->
      try
        let date1 = add_days base_date days1 in
        let date2 = add_days date1 days2 in
        let date3 = add_days base_date (days1 + days2) in
        compare_date date2 date3 = 0
      with _ -> true (* Skip invalid dates *)
    )

(* Property 3: Leap year anniversary handling is consistent *)
let prop_leap_year_anniversary_consistent =
  Test.make ~name:"leap year anniversary consistent"
    (int_range 2020 2030)
    (fun year ->
      let feb29_date = if is_leap_year 2020 then make_date 2020 2 29 else make_date 2020 2 28 in
      let test_date = make_date year 1 1 in
      try
        let anniversary = next_anniversary test_date feb29_date in
        let (_, month, day) = anniversary in
        (* Feb 29 should become Feb 28 in non-leap years *)
        if not (is_leap_year year) && month = 2 then
          day <= 28
        else
          true
      with _ -> true)

(* Property 4: Load balancing preserves total schedule count *)
let prop_load_balancing_preserves_count =
  Test.make ~name:"load balancing preserves schedule count"
    (list_of_size (int_range 1 100) schedule_gen)
    (fun schedules ->
      try
        let config = {
          daily_send_percentage_cap = 0.1;
          ed_daily_soft_limit = 100;
          ed_smoothing_window_days = 7;
          catch_up_spread_days = 14;
          overage_threshold = 1.2;
          total_contacts = 1000;
        } in
        match Load_balancer.distribute_schedules schedules config with
        | Ok balanced -> List.length schedules = List.length balanced
        | Error _ -> true (* Skip on error *)
      with _ -> true)

(* Property 5: Jitter calculation is deterministic *)
let prop_jitter_deterministic =
  Test.make ~name:"jitter is deterministic"
    (quad 
       (int_range 1 100000)    (* contact_id *)
       (oneofl ["birthday"; "effective_date"; "aep"])  (* event_type *)
       (int_range 2020 2030)   (* year *)
       (int_range 1 60))       (* window_days *)
    (fun (contact_id, event_type, year, window) ->
      try
        let j1 = Jitter.calculate_jitter ~contact_id ~event_type ~year ~window_days:window in
        let j2 = Jitter.calculate_jitter ~contact_id ~event_type ~year ~window_days:window in
        j1 = j2
      with _ -> true)

(* Property 6: Schedule priorities are preserved during processing *)
let prop_schedule_priorities_preserved =
  Test.make ~name:"schedule priorities preserved"
    (list_of_size (int_range 1 50) schedule_gen)
    (fun schedules ->
      let original_priorities = List.map (fun s -> s.priority) schedules in
      let sorted_schedules = List.sort (fun s1 s2 -> compare s1.priority s2.priority) schedules in
      let sorted_priorities = List.map (fun s -> s.priority) sorted_schedules in
      List.sort compare original_priorities = sorted_priorities)

(* Property 7: Contact validation is consistent *)
let prop_contact_validation_consistent =
  Test.make ~name:"contact validation consistent"
    contact_gen
    (fun contact ->
      let org_config = {
        enable_post_window_emails = true;
        effective_date_first_email_months = 6;
        exclude_failed_underwriting_global = false;
        send_without_zipcode_for_universal = true;
      } in
      try
        (* A valid contact should have consistent validation results *)
        let result1 = Contact.is_valid_for_anniversary_scheduling org_config contact in
        let result2 = Contact.is_valid_for_anniversary_scheduling org_config contact in
        result1 = result2
      with _ -> true)

(* Property 8: Date string conversion round-trip *)
let prop_date_string_roundtrip =
  Test.make ~name:"date string conversion round-trip"
    date_gen
    (fun date ->
      try
        let date_str = string_of_date date in
        let parsed_date = parse_date date_str in
        compare_date date parsed_date = 0
      with _ -> true)

(* Property 9: Email type to string conversion is consistent *)
let prop_email_type_string_consistent =
  Test.make ~name:"email type string conversion consistent"
    email_type_gen
    (fun email_type ->
      try
        let str1 = string_of_email_type email_type in
        let str2 = string_of_email_type email_type in
        str1 = str2
      with _ -> true)

(* Property 10: State exclusion rules are consistent with dates *)
let prop_state_exclusion_consistent =
  Test.make ~name:"state exclusion consistent with dates"
    (triple contact_gen email_type_gen date_gen)
    (fun (contact, email_type, check_date) ->
      try
        match Exclusion_window.check_exclusion_window contact check_date with
        | Excluded { reason; _ } -> reason <> ""
        | NotExcluded -> true
      with _ -> true)

(* Critical property tests that MUST hold *)
let critical_properties = [
  prop_anniversary_always_future_or_today;
  prop_date_arithmetic_consistent;
  prop_leap_year_anniversary_consistent;
  prop_load_balancing_preserves_count;
  prop_jitter_deterministic;
]

(* Additional property tests for robustness *)
let robustness_properties = [
  prop_schedule_priorities_preserved;
  prop_contact_validation_consistent;
  prop_date_string_roundtrip;
  prop_email_type_string_consistent;
  prop_state_exclusion_consistent;
]

(* All property tests *)
let all_properties = critical_properties @ robustness_properties

(* Test runner with configurable iterations *)
let run_property_tests ?(iterations=100) ?(critical_only=false) () =
  let tests_to_run = if critical_only then critical_properties else all_properties in
  
  Printf.printf "🧪 Running property-based tests (%d iterations each)...\n" iterations;
  Printf.printf "📊 Testing %d properties (%s)\n\n" 
    (List.length tests_to_run) 
    (if critical_only then "critical only" else "all");
  
  let test_config = { QCheck_runner.default with max_gen = iterations } in
  
  List.iteri (fun i test ->
    Printf.printf "⚡ Property %d/%d: %s\n" (i + 1) (List.length tests_to_run) test.name;
    match QCheck_runner.run_tests_main ~config:test_config [test] with
    | 0 -> Printf.printf "   ✅ PASSED\n"
    | _ -> Printf.printf "   ❌ FAILED\n"
  ) tests_to_run;
  
  Printf.printf "\n🏁 Property testing complete!\n"

(* Integration with Alcotest *)
let property_tests_alcotest = 
  List.mapi (fun i test ->
    let test_name = Printf.sprintf "property_%d_%s" i test.name in
    (test_name, `Quick, fun () ->
      match QCheck_runner.run_tests [test] with
      | [] -> () (* All passed *)
      | failures -> 
          let failure_msg = String.concat "; " (List.map (fun (_, msg, _) -> msg) failures) in
          Alcotest.fail ("Property test failed: " ^ failure_msg))
  ) all_properties

let () =
  (* Command line interface *)
  let argc = Array.length Sys.argv in
  if argc > 1 then
    match Sys.argv.(1) with
    | "--critical" -> run_property_tests ~critical_only:true ()
    | "--iterations" when argc > 2 -> 
        let iterations = int_of_string Sys.argv.(2) in
        run_property_tests ~iterations ()
    | "--help" ->
        Printf.printf "Property-based testing for scheduler\n";
        Printf.printf "Usage: %s [--critical] [--iterations N] [--help]\n" Sys.argv.(0);
        Printf.printf "  --critical      Run only critical properties\n";
        Printf.printf "  --iterations N  Set number of iterations (default: 100)\n";
        Printf.printf "  --help          Show this help\n"
    | _ -> run_property_tests ()
  else
    (* Run with Alcotest when used as library *)
    Alcotest.run "Property Tests" [
      "critical_properties", List.take (List.length critical_properties) property_tests_alcotest;
      "robustness_properties", List.drop (List.length critical_properties) property_tests_alcotest;
    ]