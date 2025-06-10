open Scheduler.Types
open Scheduler.Size_profiles

let test_profile_selection () =
  assert (auto_detect_profile 5_000 = Small);
  assert (auto_detect_profile 50_000 = Medium);
  assert (auto_detect_profile 250_000 = Large);
  assert (auto_detect_profile 1_000_000 = Enterprise);
  print_endline "✓ Profile selection tests passed"

let test_load_balancing_configs () =
  let small_config = load_balancing_for_profile Small 5_000 in
  assert (small_config.daily_send_percentage_cap = 0.20);
  assert (small_config.batch_size = 1000);
  assert (small_config.total_contacts = 5_000);
  
  let enterprise_config = load_balancing_for_profile Enterprise 1_000_000 in
  assert (enterprise_config.daily_send_percentage_cap = 0.05);
  assert (enterprise_config.batch_size = 25000);
  assert (enterprise_config.total_contacts = 1_000_000);
  
  print_endline "✓ Load balancing config tests passed"

let test_override_application () =
  let base_config = load_balancing_for_profile Medium 50_000 in
  let overrides = Some [("batch_size", `Int 20_000); ("daily_send_percentage_cap", `Float 0.15)] in
  let result = apply_config_overrides base_config overrides in
  
  assert (result.batch_size = 20_000);
  assert (result.daily_send_percentage_cap = 0.15);
  assert (result.ed_daily_soft_limit = base_config.ed_daily_soft_limit); (* unchanged *)
  
  print_endline "✓ Override application tests passed"

let test_threshold_boundaries () =
  (* Test boundary conditions *)
  assert (auto_detect_profile 9_999 = Small);
  assert (auto_detect_profile 10_000 = Medium);
  assert (auto_detect_profile 99_999 = Medium);
  assert (auto_detect_profile 100_000 = Large);
  assert (auto_detect_profile 499_999 = Large);
  assert (auto_detect_profile 500_000 = Enterprise);
  
  print_endline "✓ Threshold boundary tests passed"

let run_tests () =
  print_endline "Running Size Profiles Tests...";
  test_profile_selection ();
  test_load_balancing_configs ();
  test_override_application ();
  test_threshold_boundaries ();
  print_endline "All Size Profiles tests passed! ✅"

let () = run_tests ()