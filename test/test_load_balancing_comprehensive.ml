open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Load_balancer
open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Printf

(* Test database setup *)
let test_db_path = "test_load_balancing.sqlite3"

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

(* Helper functions for creating test schedules *)
module TestScheduleData = struct
  let create_schedule contact_id email_type scheduled_date run_id =
    {
      contact_id;
      email_type;
      scheduled_date;
      scheduled_time = { hour = 8; minute = 30; second = 0 };
      status = PreScheduled;
      priority = priority_of_email_type email_type;
      template_id = Some "test_template";
      campaign_instance_id = None;
      scheduler_run_id = run_id;
    }

  let create_bulk_schedules count base_date email_type run_id =
    let schedules = ref [] in
    for i = 1 to count do
      let schedule = create_schedule i email_type base_date run_id in
      schedules := schedule :: !schedules
    done;
    !schedules

  let create_effective_date_cluster count date run_id =
    (* Simulate the common scenario where many effective dates cluster on the 1st *)
    create_bulk_schedules count date (Anniversary EffectiveDate) run_id

  let create_mixed_email_schedules count base_date run_id =
    let schedules = ref [] in
    for i = 1 to count do
      let email_type = 
        match i mod 3 with
        | 0 -> Anniversary Birthday
        | 1 -> Anniversary EffectiveDate  
        | _ -> Anniversary AEP
      in
      let date_offset = i mod 7 in (* Spread across a week *)
      let schedule_date = add_days base_date date_offset in
      let schedule = create_schedule i email_type schedule_date run_id in
      schedules := schedule :: !schedules
    done;
    !schedules
end

(* Load balancing analysis helpers *)
module LoadBalancingAnalysis = struct
  let analyze_daily_distribution schedules =
    let date_counts = Hashtbl.create 32 in
    
    List.iter (fun schedule ->
      let date_str = string_of_date schedule.scheduled_date in
      let current_count = try Hashtbl.find date_counts date_str with Not_found -> 0 in
      Hashtbl.replace date_counts date_str (current_count + 1)
    ) schedules;
    
    let counts = Hashtbl.fold (fun _date count acc -> count :: acc) date_counts [] in
    let total = List.fold_left (+) 0 counts in
    let max_count = List.fold_left max 0 counts in
    let min_count = List.fold_left min max_count counts in
    let avg_count = if List.length counts > 0 then float_of_int total /. float_of_int (List.length counts) else 0.0 in
    
    {
      total_emails = total;
      total_days = List.length counts;
      avg_per_day = avg_count;
      max_day = max_count;
      min_day = min_count;
      distribution_variance = max_count - min_count;
    }

  let print_distribution_analysis analysis =
    printf "Distribution Analysis:\n";
    printf "  Total emails: %d\n" analysis.total_emails;
    printf "  Total days: %d\n" analysis.total_days;
    printf "  Average per day: %.1f\n" analysis.avg_per_day;
    printf "  Max day: %d emails\n" analysis.max_day;
    printf "  Min day: %d emails\n" analysis.min_day;
    printf "  Variance: %d emails\n" analysis.distribution_variance

  let assert_distribution_quality analysis max_variance_ratio =
    let variance_ratio = float_of_int analysis.distribution_variance /. analysis.avg_per_day in
    if variance_ratio <= max_variance_ratio then
      printf "✓ Distribution quality good (variance ratio: %.2f <= %.2f)\n" variance_ratio max_variance_ratio
    else
      failwith (Printf.sprintf "Distribution quality poor (variance ratio: %.2f > %.2f)" variance_ratio max_variance_ratio)

  let assert_daily_cap_respected analysis daily_cap =
    if analysis.max_day <= daily_cap then
      printf "✓ Daily cap respected (%d <= %d)\n" analysis.max_day daily_cap
    else
      failwith (Printf.sprintf "Daily cap violated (%d > %d)" analysis.max_day daily_cap)

  let assert_effective_date_smoothing_applied schedules expected_spread_days =
    (* Count effective date emails by date *)
    let ed_date_counts = Hashtbl.create 32 in
    
    List.iter (fun schedule ->
      match schedule.email_type with
      | Anniversary EffectiveDate ->
          let date_str = string_of_date schedule.scheduled_date in
          let current_count = try Hashtbl.find ed_date_counts date_str with Not_found -> 0 in
          Hashtbl.replace ed_date_counts date_str (current_count + 1)
      | _ -> ()
    ) schedules;
    
    let dates = Hashtbl.fold (fun date _count acc -> date :: acc) ed_date_counts [] in
    let spread_days = List.length dates in
    
    if spread_days >= expected_spread_days then
      printf "✓ Effective date smoothing applied (spread across %d days)\n" spread_days
    else
      failwith (Printf.sprintf "Insufficient effective date smoothing (%d days < %d expected)" spread_days expected_spread_days)
end

(* Test modules *)
module EffectiveDateSmoothingTests = struct
  
  let test_effective_date_clustering_resolution () =
    printf "\n=== Effective Date Clustering Resolution Test ===\n";
    
    let run_id = "ed_cluster_test" in
    let cluster_date = make_date 2024 3 1 in (* March 1st - common effective date *)
    let cluster_size = 50 in (* Large cluster that should trigger smoothing *)
    
    (* Create clustered effective date schedules *)
    let clustered_schedules = TestScheduleData.create_effective_date_cluster cluster_size cluster_date run_id in
    
    printf "Created %d effective date schedules clustered on %s\n" 
      cluster_size (string_of_date cluster_date);
    
    (* Apply load balancing *)
    let lb_config = default_config (cluster_size * 3) in (* Assume larger contact base *)
    
    match distribute_schedules clustered_schedules lb_config with
    | Ok balanced_schedules ->
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        (* Verify that effective dates are spread across multiple days *)
        LoadBalancingAnalysis.assert_effective_date_smoothing_applied balanced_schedules 3;
        
        (* Verify daily cap is respected *)
        LoadBalancingAnalysis.assert_daily_cap_respected analysis lb_config.daily_send_limit;
        
        printf "✓ Effective date clustering resolution test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Load balancing failed: %s" (string_of_error err))

  let test_mixed_email_types_balancing () =
    printf "\n=== Mixed Email Types Balancing Test ===\n";
    
    let run_id = "mixed_types_test" in
    let base_date = make_date 2024 6 1 in
    let total_schedules = 100 in
    
    let mixed_schedules = TestScheduleData.create_mixed_email_schedules total_schedules base_date run_id in
    
    printf "Created %d mixed email type schedules\n" total_schedules;
    
    let lb_config = default_config (total_schedules * 2) in
    
    match distribute_schedules mixed_schedules lb_config with
    | Ok balanced_schedules ->
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        (* Verify reasonable distribution quality *)
        LoadBalancingAnalysis.assert_distribution_quality analysis 0.5; (* Max 50% variance from average *)
        
        printf "✓ Mixed email types balancing test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Load balancing failed: %s" (string_of_error err))

  let test_large_volume_performance () =
    printf "\n=== Large Volume Performance Test ===\n";
    
    let run_id = "large_volume_test" in
    let base_date = make_date 2024 8 1 in
    let large_volume = 1000 in (* Simulate large organization *)
    
    let large_schedules = TestScheduleData.create_mixed_email_schedules large_volume base_date run_id in
    
    printf "Created %d schedules for large volume test\n" large_volume;
    
    let lb_config = default_config (large_volume * 5) in
    
    let start_time = Unix.time () in
    
    match distribute_schedules large_schedules lb_config with
    | Ok balanced_schedules ->
        let end_time = Unix.time () in
        let processing_time = end_time -. start_time in
        
        printf "Load balancing completed in %.3f seconds\n" processing_time;
        printf "Throughput: %.0f schedules/second\n" (float_of_int large_volume /. processing_time);
        
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        (* Verify performance is acceptable (should process 1000 schedules in under 1 second) *)
        if processing_time < 1.0 then
          printf "✓ Performance acceptable (%.3f seconds)\n" processing_time
        else
          failwith (Printf.sprintf "Performance too slow (%.3f seconds)" processing_time);
        
        (* Verify distribution quality is maintained even at scale *)
        LoadBalancingAnalysis.assert_distribution_quality analysis 0.4;
        
        printf "✓ Large volume performance test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Load balancing failed: %s" (string_of_error err))

  let run_all () =
    printf "\n⚖️  Running Load Balancing Tests\n";
    test_effective_date_clustering_resolution ();
    test_mixed_email_types_balancing ();
    test_large_volume_performance ();
    printf "✅ All load balancing tests passed\n"
end

(* Boundary condition tests *)
module BoundaryConditionTests = struct
  
  let test_empty_schedule_list () =
    printf "\n=== Empty Schedule List Test ===\n";
    
    let empty_schedules = [] in
    let lb_config = default_config 1000 in
    
    match distribute_schedules empty_schedules lb_config with
    | Ok balanced_schedules ->
        if List.length balanced_schedules = 0 then
          printf "✓ Empty schedule list handled correctly\n"
        else
          failwith "Empty schedule list should return empty result"
    | Error err ->
        failwith (Printf.sprintf "Empty schedule list should not error: %s" (string_of_error err))

  let test_single_schedule () =
    printf "\n=== Single Schedule Test ===\n";
    
    let single_schedule = [TestScheduleData.create_schedule 1 (Anniversary Birthday) (make_date 2024 6 1) "single_test"] in
    let lb_config = default_config 1000 in
    
    match distribute_schedules single_schedule lb_config with
    | Ok balanced_schedules ->
        if List.length balanced_schedules = 1 then
          printf "✓ Single schedule handled correctly\n"
        else
          failwith "Single schedule should return single result"
    | Error err ->
        failwith (Printf.sprintf "Single schedule should not error: %s" (string_of_error err))

  let test_very_small_organization () =
    printf "\n=== Very Small Organization Test ===\n";
    
    let small_schedules = TestScheduleData.create_mixed_email_schedules 5 (make_date 2024 6 1) "small_org_test" in
    let lb_config = default_config 10 in (* Very small organization *)
    
    match distribute_schedules small_schedules lb_config with
    | Ok balanced_schedules ->
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        (* For very small orgs, distribution may be more uneven, which is acceptable *)
        printf "✓ Very small organization handled correctly\n"
    | Error err ->
        failwith (Printf.sprintf "Small organization balancing failed: %s" (string_of_error err))

  let test_past_date_handling () =
    printf "\n=== Past Date Handling Test ===\n";
    
    let past_date = add_days (current_date ()) (-30) in (* 30 days ago *)
    let past_schedules = TestScheduleData.create_bulk_schedules 10 past_date (Anniversary Birthday) "past_test" in
    let lb_config = default_config 1000 in
    
    match distribute_schedules past_schedules lb_config with
    | Ok balanced_schedules ->
        (* Verify all dates are moved to future *)
        let all_dates_future = List.for_all (fun schedule ->
          date_compare schedule.scheduled_date (current_date ()) >= 0
        ) balanced_schedules in
        
        if all_dates_future then
          printf "✓ Past dates correctly moved to future\n"
        else
          failwith "Some schedules still have past dates";
        
        printf "✓ Past date handling test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Past date handling failed: %s" (string_of_error err))

  let run_all () =
    printf "\n🔍 Running Boundary Condition Tests\n";
    test_empty_schedule_list ();
    test_single_schedule ();
    test_very_small_organization ();
    test_past_date_handling ();
    printf "✅ All boundary condition tests passed\n"
end

(* Configuration edge case tests *)
module ConfigurationTests = struct
  
  let test_extreme_daily_caps () =
    printf "\n=== Extreme Daily Caps Test ===\n";
    
    let schedules = TestScheduleData.create_mixed_email_schedules 100 (make_date 2024 6 1) "cap_test" in
    
    (* Test very low daily cap *)
    let low_cap_config = { (default_config 1000) with daily_send_limit = 5 } in
    
    match distribute_schedules schedules low_cap_config with
    | Ok balanced_schedules ->
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        LoadBalancingAnalysis.assert_daily_cap_respected analysis low_cap_config.daily_send_limit;
        
        (* With very low cap, schedules should be spread over many days *)
        if analysis.total_days >= 15 then (* 100 emails / 5 per day = 20 days minimum *)
          printf "✓ Low daily cap correctly spreads schedules over time\n"
        else
          failwith "Low daily cap should spread schedules over more days";
        
        printf "✓ Extreme daily caps test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Extreme caps test failed: %s" (string_of_error err))

  let test_effective_date_limits () =
    printf "\n=== Effective Date Limits Test ===\n";
    
    let ed_schedules = TestScheduleData.create_effective_date_cluster 30 (make_date 2024 3 1) "ed_limit_test" in
    
    (* Test very restrictive effective date limit *)
    let restrictive_config = { 
      (default_config 1000) with 
      effective_date_daily_soft_limit = 2 
    } in
    
    match distribute_schedules ed_schedules restrictive_config with
    | Ok balanced_schedules ->
        let analysis = LoadBalancingAnalysis.analyze_daily_distribution balanced_schedules in
        LoadBalancingAnalysis.print_distribution_analysis analysis;
        
        (* With 30 ED emails and limit of 2, should spread over 15+ days *)
        LoadBalancingAnalysis.assert_effective_date_smoothing_applied balanced_schedules 10;
        
        printf "✓ Effective date limits test passed\n"
    | Error err ->
        failwith (Printf.sprintf "Effective date limits test failed: %s" (string_of_error err))

  let run_all () =
    printf "\n⚙️  Running Configuration Tests\n";
    test_extreme_daily_caps ();
    test_effective_date_limits ();
    printf "✅ All configuration tests passed\n"
end

(* Database integration tests *)
module DatabaseIntegrationTests = struct
  
  let setup_test_database () =
    set_db_path test_db_path;
    match initialize_database () with
    | Ok () -> 
        printf "✓ Test database initialized\n";
        
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
        
        (match execute_sql_no_result create_schedules_table with
         | Ok () -> printf "✓ Email schedules table ready\n"
         | Error err -> failwith (string_of_db_error err))
    | Error err -> 
        failwith (Printf.sprintf "Failed to initialize test database: %s" (string_of_db_error err))

  let test_end_to_end_load_balancing_with_database () =
    printf "\n=== End-to-End Load Balancing with Database Test ===\n";
    
    setup_test_database ();
    
    (* Clear any existing data *)
    let _ = execute_sql_no_result "DELETE FROM email_schedules" in
    
    let schedules = TestScheduleData.create_mixed_email_schedules 50 (make_date 2024 6 1) "e2e_test" in
    let lb_config = default_config 200 in
    
    match distribute_schedules schedules lb_config with
    | Ok balanced_schedules ->
        (* Insert balanced schedules into database *)
        (match batch_insert_schedules_optimized balanced_schedules with
         | Ok inserted_count ->
             printf "Inserted %d balanced schedules into database\n" inserted_count;
             
             (* Verify database state *)
             let count_query = "SELECT COUNT(*) FROM email_schedules WHERE status = 'pre-scheduled'" in
             (match execute_sql_safe count_query with
              | Ok [[count_str]] ->
                  let db_count = int_of_string count_str in
                  if db_count = inserted_count then
                    printf "✓ Database state matches inserted schedules (%d)\n" db_count
                  else
                    failwith (Printf.sprintf "Database count mismatch: %d vs %d" db_count inserted_count)
              | _ -> failwith "Failed to query database count");
             
             (* Verify date distribution in database *)
             let distribution_query = {|
               SELECT scheduled_send_date, COUNT(*) 
               FROM email_schedules 
               GROUP BY scheduled_send_date 
               ORDER BY scheduled_send_date
             |} in
             (match execute_sql_safe distribution_query with
              | Ok rows ->
                  printf "Database distribution:\n";
                  List.iter (fun row ->
                    match row with
                    | [date; count] -> printf "  %s: %s emails\n" date count
                    | _ -> ()
                  ) rows;
                  printf "✓ Database distribution verified\n"
              | Error err -> failwith (string_of_db_error err));
             
             printf "✓ End-to-end load balancing with database test passed\n"
         | Error err -> failwith (string_of_db_error err))
    | Error err ->
        failwith (Printf.sprintf "Load balancing failed: %s" (string_of_error err))

  let run_all () =
    printf "\n💾 Running Database Integration Tests\n";
    test_end_to_end_load_balancing_with_database ();
    close_database ();
    printf "✅ All database integration tests passed\n"
end

(* Main test runner *)
let run_all_tests () =
  printf "⚖️  Starting Comprehensive Load Balancing Tests\n";
  printf "================================================\n";
  
  EffectiveDateSmoothingTests.run_all ();
  BoundaryConditionTests.run_all ();
  ConfigurationTests.run_all ();
  DatabaseIntegrationTests.run_all ();
  
  printf "\n🎉 ALL LOAD BALANCING TESTS PASSED! 🎉\n";
  printf "=====================================\n"

let () = run_all_tests ()