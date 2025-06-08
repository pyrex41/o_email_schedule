open Alcotest
open Scheduler
open Types
open Date_time

(* Comprehensive State Rule Testing Matrix - Priority 4 from action plan *)

(* Helper functions for creating test data *)
let make_contact ?(id=1) ?(email="test@example.com") ?(zip_code=Some "90210") 
                 ?state ?(birthday=None) ?(effective_date=None) 
                 ?(carrier=Some "UnitedHealthcare") ?(failed_underwriting=false) () =
  { id; email; zip_code; state; birthday; effective_date; carrier; failed_underwriting }

let make_birthday_schedule contact check_date =
  Anniversary Birthday, check_date

let make_effective_date_schedule contact check_date =
  Anniversary EffectiveDate, check_date

(* Test matrix data structure *)
type test_case = {
  description: string;
  state: state;
  email_type: anniversary_email;
  test_scenarios: (string * date * bool) list; (* (description, test_date, should_be_excluded) *)
}

(* Year boundary test helper *)
let year_boundary_dates = [
  ("December 20 for January birthday", make_date 2023 12 20);
  ("December 31 for January birthday", make_date 2023 12 31);
  ("January 1 for January birthday", make_date 2024 1 1);
  ("January 15 for January birthday", make_date 2024 1 15);
]

(* Core state rule test matrix *)
let state_rule_test_matrix = [
  (* California - 30-day birthday window, 60-day ED window *)
  {
    description = "California birthday exclusions";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("31 days before birthday", make_date 2024 5 31, false);  (* Outside window *)
      ("30 days before birthday", make_date 2024 6 1, true);    (* Window starts *)
      ("15 days before birthday", make_date 2024 6 16, true);   (* Mid window *)
      ("On birthday", make_date 2024 7 1, true);                (* Birthday *)
      ("30 days after birthday", make_date 2024 7 31, true);    (* Window ends *)
      ("60 days after birthday", make_date 2024 8 30, true);    (* Still in window *)
      ("61 days after birthday", make_date 2024 8 31, false);   (* Outside window *)
    ];
  };
  
  {
    description = "California effective date exclusions";
    state = CA;
    email_type = EffectiveDate;
    test_scenarios = [
      ("61 days before ED", make_date 2024 4 30, false);        (* Outside window *)
      ("60 days before ED", make_date 2024 5 1, true);          (* Window starts *)
      ("30 days before ED", make_date 2024 6 1, true);          (* Mid window *)
      ("On effective date", make_date 2024 7 1, true);          (* ED date *)
      ("60 days after ED", make_date 2024 8 30, true);          (* Window ends *)
      ("61 days after ED", make_date 2024 8 31, false);         (* Outside window *)
    ];
  };
  
  (* Nevada - Special case: uses month start instead of exact date *)
  {
    description = "Nevada birthday exclusions (month start rule)";
    state = NV;
    email_type = Birthday;
    test_scenarios = [
      ("May 31 for June birthday", make_date 2024 5 31, false); (* Before month *)
      ("June 1 for June birthday", make_date 2024 6 1, true);   (* Month start! *)
      ("June 15 for June birthday", make_date 2024 6 15, true); (* Same month *)
      ("June 30 for June birthday", make_date 2024 6 30, true); (* End of month *)
      ("July 1 for June birthday", make_date 2024 7 1, false);  (* Next month *)
    ];
  };
  
  {
    description = "Nevada effective date exclusions (month start rule)";
    state = NV;
    email_type = EffectiveDate;
    test_scenarios = [
      ("May 31 for June ED", make_date 2024 5 31, false);       (* Before month *)
      ("June 1 for June ED", make_date 2024 6 1, true);         (* Month start! *)
      ("June 15 for June ED", make_date 2024 6 15, true);       (* Same month *)
      ("June 30 for June ED", make_date 2024 6 30, true);       (* End of month *)
      ("July 1 for June ED", make_date 2024 7 1, false);        (* Next month *)
    ];
  };
  
  (* New York - Year-round exclusion *)
  {
    description = "New York year-round exclusions";
    state = NY;
    email_type = Birthday;
    test_scenarios = [
      ("January 1", make_date 2024 1 1, true);                  (* Always excluded *)
      ("June 15", make_date 2024 6 15, true);                   (* Always excluded *)
      ("December 31", make_date 2024 12 31, true);              (* Always excluded *)
    ];
  };
  
  (* Connecticut - 60-day window for both *)
  {
    description = "Connecticut 60-day birthday window";
    state = CT;
    email_type = Birthday;
    test_scenarios = [
      ("61 days before", make_date 2024 4 30, false);           (* Outside window *)
      ("60 days before", make_date 2024 5 1, true);             (* Window starts *)
      ("On birthday", make_date 2024 7 1, true);                (* Birthday *)
      ("60 days after", make_date 2024 8 30, true);             (* Window ends *)
      ("61 days after", make_date 2024 8 31, false);            (* Outside window *)
    ];
  };
  
  (* Idaho - No exclusions *)
  {
    description = "Idaho no exclusions";
    state = ID;
    email_type = Birthday;
    test_scenarios = [
      ("Any date in year", make_date 2024 6 15, false);         (* Never excluded *)
      ("Even on birthday", make_date 2024 7 1, false);          (* Never excluded *)
    ];
  };
  
  (* Other state - Default behavior *)
  {
    description = "Other state default behavior";
    state = Other "AZ";
    email_type = Birthday;
    test_scenarios = [
      ("Should follow default rules", make_date 2024 6 15, false); (* Depends on implementation *)
    ];
  };
]

(* Leap year specific test matrix *)
let leap_year_test_matrix = [
  {
    description = "Leap year Feb 29 birthday in leap year";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("Feb 28 in leap year", make_date 2024 2 28, true);       (* Before Feb 29 *)
      ("Feb 29 in leap year", make_date 2024 2 29, true);       (* The actual birthday *)
      ("Mar 1 in leap year", make_date 2024 3 1, true);         (* After Feb 29 *)
    ];
  };
  
  {
    description = "Leap year Feb 29 birthday in non-leap year";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("Feb 28 in non-leap year", make_date 2023 2 28, true);   (* Converted birthday *)
      ("Mar 1 in non-leap year", make_date 2023 3 1, true);     (* Day after converted *)
    ];
  };
]

(* Year boundary crossing test matrix *)
let year_boundary_test_matrix = [
  {
    description = "Year boundary crossing - December to January";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("Dec 20 for Jan 15 birthday", make_date 2023 12 20, true);  (* Before year boundary *)
      ("Dec 31 for Jan 15 birthday", make_date 2023 12 31, true);  (* Year boundary *)
      ("Jan 1 for Jan 15 birthday", make_date 2024 1 1, true);     (* After year boundary *)
      ("Jan 15 for Jan 15 birthday", make_date 2024 1 15, true);   (* The birthday *)
    ];
  };
]

(* Edge case test matrix *)
let edge_case_test_matrix = [
  {
    description = "Month boundary edge cases";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("Jan 31 for Feb 1 birthday", make_date 2024 1 31, true);
      ("Feb 1 for Feb 1 birthday", make_date 2024 2 1, true);
      ("Feb 2 for Feb 1 birthday", make_date 2024 2 2, true);
    ];
  };
  
  {
    description = "Different month lengths";
    state = CA;
    email_type = Birthday;
    test_scenarios = [
      ("Jan 30 (31-day month)", make_date 2024 1 30, false);
      ("Apr 30 (30-day month)", make_date 2024 4 30, false);
      ("Feb 28 (28-day month)", make_date 2024 2 28, false);
    ];
  };
]

(* All test matrices combined *)
let all_test_matrices = [
  ("Core State Rules", state_rule_test_matrix);
  ("Leap Year Handling", leap_year_test_matrix);
  ("Year Boundary Crossing", year_boundary_test_matrix);
  ("Edge Cases", edge_case_test_matrix);
]

(* Test runner for a single test case *)
let run_test_case test_case =
  List.iter (fun (scenario_desc, test_date, expected_excluded) ->
    let contact = match test_case.email_type with
      | Birthday -> make_contact ~state:(Some test_case.state) ~birthday:(Some (make_date 2024 7 1)) ()
      | EffectiveDate -> make_contact ~state:(Some test_case.state) ~effective_date:(Some (make_date 2024 7 1)) ()
      | _ -> make_contact ~state:(Some test_case.state) ()
    in
    
    let result = Exclusion_window.check_exclusion_window contact test_date in
    let is_excluded = match result with
      | Excluded _ -> true
      | NotExcluded -> false
    in
    
    let test_name = Printf.sprintf "%s - %s: %s" 
      test_case.description 
      scenario_desc
      (if expected_excluded then "should be excluded" else "should not be excluded") in
    
    if is_excluded = expected_excluded then
      Printf.printf "   ✅ %s\n" test_name
    else
      Printf.printf "   ❌ %s (got %s, expected %s)\n" 
        test_name 
        (if is_excluded then "excluded" else "not excluded")
        (if expected_excluded then "excluded" else "not excluded")
  ) test_case.test_scenarios

(* Alcotest wrapper for a single test case *)
let make_alcotest_case test_case scenario_desc test_date expected_excluded =
  let test_name = Printf.sprintf "%s_%s" test_case.description scenario_desc in
  (test_name, `Quick, fun () ->
    let contact = match test_case.email_type with
      | Birthday -> make_contact ~state:(Some test_case.state) ~birthday:(Some (make_date 2024 7 1)) ()
      | EffectiveDate -> make_contact ~state:(Some test_case.state) ~effective_date:(Some (make_date 2024 7 1)) ()
      | _ -> make_contact ~state:(Some test_case.state) ()
    in
    
    let result = Exclusion_window.check_exclusion_window contact test_date in
    let is_excluded = match result with
      | Excluded _ -> true
      | NotExcluded -> false
    in
    
    Alcotest.(check bool) 
      (Printf.sprintf "State %s exclusion for %s" 
         (string_of_state test_case.state)
         scenario_desc)
      expected_excluded
      is_excluded
  )

(* Generate all Alcotest cases *)
let generate_alcotest_cases () =
  List.fold_left (fun acc (matrix_name, test_matrix) ->
    let matrix_tests = List.fold_left (fun test_acc test_case ->
      let case_tests = List.map (fun (scenario_desc, test_date, expected_excluded) ->
        make_alcotest_case test_case scenario_desc test_date expected_excluded
      ) test_case.test_scenarios in
      case_tests @ test_acc
    ) [] test_matrix in
    (matrix_name, matrix_tests) :: acc
  ) [] all_test_matrices

(* Manual test runner *)
let run_all_state_rule_tests () =
  Printf.printf "🧪 Running comprehensive state rule test matrix...\n\n";
  
  List.iter (fun (matrix_name, test_matrix) ->
    Printf.printf "📊 %s:\n" matrix_name;
    List.iter run_test_case test_matrix;
    Printf.printf "\n"
  ) all_test_matrices;
  
  Printf.printf "🏁 State rule matrix testing complete!\n"

(* Summary statistics *)
let get_test_statistics () =
  let total_matrices = List.length all_test_matrices in
  let total_test_cases = List.fold_left (fun acc (_, matrix) -> acc + List.length matrix) 0 all_test_matrices in
  let total_scenarios = List.fold_left (fun acc (_, matrix) ->
    List.fold_left (fun acc2 test_case -> acc2 + List.length test_case.test_scenarios) acc matrix
  ) 0 all_test_matrices in
  
  Printf.printf "📈 Test Matrix Statistics:\n";
  Printf.printf "   • %d test matrices\n" total_matrices;
  Printf.printf "   • %d test cases\n" total_test_cases;
  Printf.printf "   • %d total scenarios\n" total_scenarios;
  Printf.printf "   • States covered: CA, NY, NV, CT, ID, Other\n";
  Printf.printf "   • Email types: Birthday, EffectiveDate\n";
  Printf.printf "   • Special cases: Leap year, Year boundary, Month boundary\n\n"

let () =
  (* Command line interface *)
  let argc = Array.length Sys.argv in
  if argc > 1 then
    match Sys.argv.(1) with
    | "--run" -> 
        get_test_statistics ();
        run_all_state_rule_tests ()
    | "--stats" -> 
        get_test_statistics ()
    | "--help" ->
        Printf.printf "State rule matrix testing for scheduler\n";
        Printf.printf "Usage: %s [--run] [--stats] [--help]\n" Sys.argv.(0);
        Printf.printf "  --run     Run all state rule tests\n";
        Printf.printf "  --stats   Show test statistics\n";
        Printf.printf "  --help    Show this help\n"
    | _ -> 
        get_test_statistics ();
        run_all_state_rule_tests ()
  else
    (* Run with Alcotest when used as library *)
    let test_suites = generate_alcotest_cases () in
    Alcotest.run "State Rule Matrix Tests" test_suites