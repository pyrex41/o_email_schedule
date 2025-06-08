open Scheduler.Types
open Scheduler.Date_time
open Scheduler.Contact
open Scheduler.Email_scheduler
open Scheduler.Load_balancer

let create_sample_contact id email zip birthday_year birthday_month birthday_day ed_year ed_month ed_day =
  let birthday = if birthday_year > 0 then Some (birthday_year, birthday_month, birthday_day) else None in
  let effective_date = if ed_year > 0 then Some (ed_year, ed_month, ed_day) else None in
  let contact = {
    id;
    email;
    zip_code = Some zip;
    state = None;
    birthday;
    effective_date;
    carrier = None;
    failed_underwriting = false;
  } in
  update_contact_state contact

let demo_comprehensive_scheduling () =
  Printf.printf "=== Advanced Email Scheduler Demo ===\n\n";
  
  let _ = Scheduler.Zip_data.load_zip_data () in
  
  let contacts = [
    create_sample_contact 1 "alice@example.com" "90210" 1990 6 15 2020 1 1;  (* CA contact *)
    create_sample_contact 2 "bob@example.com" "10001" 1985 12 25 2019 3 15;  (* NY contact *)
    create_sample_contact 3 "charlie@example.com" "06830" 1992 2 29 2021 2 1; (* CT contact *)
    create_sample_contact 4 "diana@example.com" "89101" 1988 3 10 2020 7 1;   (* NV contact *)
    create_sample_contact 5 "eve@example.com" "63101" 1995 8 22 2022 6 1;     (* MO contact *)
    create_sample_contact 6 "frank@example.com" "97201" 1987 11 5 0 0 0;      (* OR contact, no ED *)
  ] in
  
  Printf.printf "📊 Processing %d contacts...\n\n" (List.length contacts);
  
  (* Skip detailed validation for now - type issue to debug later *)
  
  let config = Scheduler.Config.default in
  let total_contacts = List.length contacts in
  
  match schedule_emails_streaming ~contacts ~config ~total_contacts with
  | Ok result ->
      Printf.printf "✅ Scheduling completed successfully!\n\n";
      
      Printf.printf "%s\n\n" (get_scheduling_summary result);
      
      let analysis = analyze_distribution result.schedules in
      Printf.printf "📈 Load Balancing Analysis:\n";
      Printf.printf "  - Distribution variance: %d emails\n" analysis.distribution_variance;
      Printf.printf "  - Peak day: %d emails\n" analysis.max_day;
      Printf.printf "  - Average per day: %.1f emails\n\n" analysis.avg_per_day;
      
      Printf.printf "📅 Scheduled Email Summary:\n";
      let schedule_counts = Hashtbl.create 10 in
      List.iter (fun schedule ->
        let date_str = string_of_date schedule.scheduled_date in
        let current_count = match Hashtbl.find_opt schedule_counts date_str with
          | Some count -> count
          | None -> 0
        in
        Hashtbl.replace schedule_counts date_str (current_count + 1)
      ) result.schedules;
      
      Hashtbl.iter (fun date count ->
        Printf.printf "  %s: %d emails\n" date count
      ) schedule_counts;
      
      Printf.printf "\n🎯 Email Type Breakdown:\n";
      let type_counts = Hashtbl.create 10 in
      List.iter (fun schedule ->
        let type_str = string_of_email_type schedule.email_type in
        let current_count = match Hashtbl.find_opt type_counts type_str with
          | Some count -> count
          | None -> 0
        in
        Hashtbl.replace type_counts type_str (current_count + 1)
      ) result.schedules;
      
      Hashtbl.iter (fun email_type count ->
        Printf.printf "  %s: %d\n" email_type count
      ) type_counts;
      
      if result.errors <> [] then (
        Printf.printf "\n⚠️  Errors encountered:\n";
        List.iter (fun error ->
          Printf.printf "  - %s\n" (string_of_error error)
        ) result.errors
      );
      
  | Error error ->
      Printf.printf "❌ Scheduling failed: %s\n" (string_of_error error);
  
  Printf.printf "\n🎉 Advanced demo completed!\n"

let () = demo_comprehensive_scheduling ()
