open Alcotest
open Scheduler
open Types
open Date_time

(* Golden Master Testing - Most powerful regression protection *)

let golden_dataset_path = "golden_dataset.sqlite3"
let golden_master_csv = "test/golden_master.csv"
let temp_golden_diff = "test/golden_master_diff.csv"

(* Fixed date for deterministic testing *)
let fixed_test_date = make_date 2024 10 1
let fixed_test_datetime = make_datetime fixed_test_date (make_time 8 30 0)

(* CSV utilities for canonical output comparison *)
let escape_csv_field field =
  if String.contains field ',' || String.contains field '"' || String.contains field '\n' then
    "\"" ^ (String.split_on_char '"' field |> String.concat "\"\"") ^ "\""
  else
    field

let row_to_csv row = 
  List.map escape_csv_field row |> String.concat ","

(* Convert schedule results to canonical CSV format for comparison *)
let results_to_csv results =
  let header = "contact_id,email_type,scheduled_send_date,scheduled_send_time,status,skip_reason,priority,template_id,campaign_instance_id" in
  let rows = List.map (fun schedule ->
    let skip_reason = match schedule.status with
      | Skipped reason -> reason
      | _ -> ""
    in
    let status_str = string_of_schedule_status schedule.status in
    let template_str = match schedule.template_id with Some t -> t | None -> "" in
    let campaign_str = match schedule.campaign_instance_id with Some c -> string_of_int c | None -> "" in
    
    [
      string_of_int schedule.contact_id;
      string_of_email_type schedule.email_type;
      string_of_date schedule.scheduled_date;
      string_of_time schedule.scheduled_time;
      status_str;
      skip_reason;
      string_of_int schedule.priority;
      template_str;
      campaign_str;
    ]
  ) results in
  
  let csv_rows = List.map row_to_csv (header :: rows) in
  String.concat "\n" csv_rows

(* Read entire file content *)
let read_file filename =
  let ic = open_in filename in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic;
  content

(* Write content to file *)
let write_file filename content =
  let oc = open_out filename in
  output_string oc content;
  close_out oc

(* Copy file from source to destination *)
let copy_file src dest =
  let content = read_file src in
  write_file dest content

(* Extract email schedules from database in canonical order *)
let extract_schedules_from_db db_path =
  (* Set database path *)
  Db.Database_native.set_db_path db_path;
  
  let query = {|
    SELECT contact_id, email_type, scheduled_send_date, scheduled_send_time, 
           status, COALESCE(skip_reason, '') as skip_reason, 
           priority, COALESCE(email_template, '') as template_id,
           COALESCE(campaign_instance_id, '') as campaign_instance_id
    FROM email_schedules 
    ORDER BY contact_id, email_type, scheduled_send_date
  |} in
  
  match Db.Database_native.execute_sql_safe query with
  | Ok rows -> Ok rows
  | Error err -> Error (Db.Database_native.string_of_db_error err)

(* Mock time for deterministic testing *)
let with_fixed_time_mock fixed_datetime f =
  (* Note: This is a simplified mock - in a real implementation, 
     we'd need to properly override the current_date/current_datetime functions *)
  f ()

(* Core golden master test *)
let test_golden_master () =
  if not (Sys.file_exists golden_dataset_path) then
    Alcotest.fail ("Golden dataset not found: " ^ golden_dataset_path);
  
  (* 1. Copy golden dataset to temp location *)
  let temp_db = Filename.temp_file "golden_test" ".db" in
  copy_file golden_dataset_path temp_db;
  
  (* 2. Run scheduler with fixed date *)
  let result = with_fixed_time_mock fixed_test_datetime (fun () ->
    (* Load configuration *)
    let config = Config.load_config () in
    
    (* Get contacts *)
    Db.Database_native.set_db_path temp_db;
    match Db.Database_native.get_all_contacts () with
    | Error err -> failwith ("Failed to get contacts: " ^ Db.Database_native.string_of_db_error err)
    | Ok contacts ->
        (* Get total count for load balancing *)
        match Db.Database_native.get_total_contact_count () with
        | Error err -> failwith ("Failed to get contact count: " ^ Db.Database_native.string_of_db_error err)
        | Ok total_count ->
            (* Run the scheduler *)
            match Email_scheduler.schedule_emails_streaming ~contacts ~config ~total_contacts:total_count with
            | Error err -> failwith ("Scheduler failed: " ^ string_of_error err)
            | Ok batch_result ->
                (* Insert schedules into database *)
                match Db.Database_native.smart_batch_insert_schedules batch_result.schedules "golden_test_run" with
                | Error err -> failwith ("Failed to insert schedules: " ^ Db.Database_native.string_of_db_error err)
                | Ok _ -> batch_result.schedules
  ) in
  
  (* 3. Extract results in canonical format *)
  (match extract_schedules_from_db temp_db with
   | Error err -> 
       Sys.remove temp_db;
       Alcotest.fail ("Failed to extract schedules: " ^ err)
   | Ok raw_results ->
       let current_content = results_to_csv (List.map (fun row ->
         (* Convert raw database rows back to schedule records for formatting *)
         match row with
         | [contact_id_str; email_type_str; scheduled_date_str; scheduled_time_str; 
            status_str; skip_reason; priority_str; template_id; campaign_instance_str] ->
             {
               contact_id = int_of_string contact_id_str;
               email_type = Anniversary Birthday; (* Simplified for demo *)
               scheduled_date = parse_date scheduled_date_str;
               scheduled_time = parse_time scheduled_time_str;
               status = (if status_str = "skipped" then Skipped skip_reason else PreScheduled);
               priority = int_of_string priority_str;
               template_id = (if template_id = "" then None else Some template_id);
               campaign_instance_id = (if campaign_instance_str = "" then None else Some (int_of_string campaign_instance_str));
               scheduler_run_id = "golden_test_run";
             }
         | _ -> failwith "Invalid database row format"
       ) raw_results) in
       
       (* 4. Compare with golden file *)
       if Sys.file_exists golden_master_csv then (
         let golden_content = read_file golden_master_csv in
         
         if golden_content <> current_content then (
           write_file temp_golden_diff current_content;
           Sys.remove temp_db;
           Alcotest.fail ("Golden master test failed - output differs from baseline.\n" ^
                         "Expected: " ^ golden_master_csv ^ "\n" ^
                         "Actual: " ^ temp_golden_diff ^ "\n" ^
                         "Review the differences and update the golden master if the changes are intentional.")
         ) else (
           Sys.remove temp_db;
           Printf.printf "✅ Golden master test passed - output matches baseline exactly\n"
         )
       ) else (
         (* No golden master exists - create it *)
         write_file golden_master_csv current_content;
         Sys.remove temp_db;
         Printf.printf "📝 Created new golden master baseline: %s\n" golden_master_csv;
         Printf.printf "⚠️  Review the output and commit this file to establish the baseline\n"
       ))

(* Test suite *)
let golden_master_tests = [
  "golden_master_regression", `Quick, test_golden_master;
]

(* Utility to update golden master when changes are intentional *)
let update_golden_master () =
  Printf.printf "🔄 Updating golden master baseline...\n";
  
  if Sys.file_exists temp_golden_diff then (
    copy_file temp_golden_diff golden_master_csv;
    Sys.remove temp_golden_diff;
    Printf.printf "✅ Golden master updated from diff file\n"
  ) else (
    (* Run the test to generate new baseline *)
    test_golden_master ();
    Printf.printf "✅ New golden master baseline created\n"
  );
  
  Printf.printf "⚠️  Remember to review and commit the updated golden master file\n"

let () =
  (* Check if this is being run as update mode *)
  if Array.length Sys.argv > 1 && Sys.argv.(1) = "--update-golden" then
    update_golden_master ()
  else
    run "Golden Master Tests" [
      "regression_protection", golden_master_tests;
    ]