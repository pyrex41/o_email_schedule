open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Load_balancer

let test_load_balancing_config () =
  let config = default_config 1000 in
  assert (config.total_contacts = 1000);
  assert (config.daily_send_percentage_cap = 0.07);
  
  let daily_cap = calculate_daily_cap config in
  assert (daily_cap = 70); (* 7% of 1000 *)
  
  Printf.printf "✓ Load balancing config tests passed\n"

let test_distribution_analysis () =
  let schedules = [
    {
      contact_id = 1;
      email_type = Anniversary Birthday;
      scheduled_date = make_date 2024 6 15;
      scheduled_time = { hour = 8; minute = 30; second = 0 };
      status = PreScheduled;
      priority = 10;
      template_id = Some "birthday";
      campaign_instance_id = None;
      scheduler_run_id = "test_run";
    };
    {
      contact_id = 2;
      email_type = Anniversary EffectiveDate;
      scheduled_date = make_date 2024 6 15;
      scheduled_time = { hour = 8; minute = 30; second = 0 };
      status = PreScheduled;
      priority = 20;
      template_id = Some "ed";
      campaign_instance_id = None;
      scheduler_run_id = "test_run";
    };
  ] in
  
  let analysis = analyze_distribution schedules in
  assert (analysis.total_emails = 2);
  assert (analysis.total_days = 1);
  assert (analysis.max_day = 2);
  
  Printf.printf "✓ Distribution analysis tests passed\n"

let test_config_validation () =
  let good_config = default_config 1000 in
  assert (validate_config good_config = Ok ());
  
  let bad_config = { good_config with daily_send_percentage_cap = 1.5 } in
  assert (match validate_config bad_config with Error _ -> true | Ok _ -> false);
  
  Printf.printf "✓ Config validation tests passed\n"

let test_priority_ordering () =
  let birthday_priority = priority_of_email_type (Anniversary Birthday) in
  let ed_priority = priority_of_email_type (Anniversary EffectiveDate) in
  let followup_priority = priority_of_email_type (Followup Cold) in
  
  assert (birthday_priority < ed_priority);
  assert (ed_priority < followup_priority);
  
  Printf.printf "✓ Priority ordering tests passed\n"

let test_error_handling () =
  let error = InvalidContactData { contact_id = 123; reason = "test error" } in
  let error_str = string_of_error error in
  assert (String.contains error_str '1');
  assert (String.contains error_str '2');
  assert (String.contains error_str '3');
  
  Printf.printf "✓ Error handling tests passed\n"

let run_all_tests () =
  Printf.printf "Running advanced feature tests...\n";
  test_load_balancing_config ();
  test_distribution_analysis ();
  test_config_validation ();
  test_priority_ordering ();
  test_error_handling ();
  Printf.printf "All advanced tests passed! ✅\n"

let () = run_all_tests ()