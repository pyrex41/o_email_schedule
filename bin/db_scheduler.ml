open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Email_scheduler
open Scheduler.Db.Simple_db

let rec list_take n = function
  | [] -> []
  | _ when n <= 0 -> []
  | x :: xs -> x :: list_take (n - 1) xs

let run_database_scheduler () =
  Printf.printf "=== Database Email Scheduler ===\n\n";
  
  (* Load ZIP data *)
  let _ = Scheduler.Zip_data.ensure_loaded () in
  
  (* Clear existing pre-scheduled emails *)
  Printf.printf "🧹 Clearing pre-scheduled emails...\n";
  clear_pre_scheduled_emails ();
  
  (* Get contacts from database *)
  Printf.printf "📊 Loading contacts from database...\n";
  let contacts = get_contacts_from_db () in
  let contact_count = List.length contacts in
  Printf.printf "   Found %d contacts\n\n" contact_count;
  
  if contact_count = 0 then (
    Printf.printf "❌ No contacts found in database!\n";
    exit 1
  );
  
  (* Update contacts with state information from ZIP codes *)
  Printf.printf "🗺️  Updating contact states from ZIP codes...\n";
  let updated_contacts = List.map (fun contact ->
    match contact.zip_code with
    | Some zip ->
        (match Scheduler.Zip_data.state_from_zip_code zip with
         | Some state -> { contact with state = Some state }
         | None -> contact)
    | None -> contact
  ) contacts in
  
  (* Show a sample of updated contacts *)
  Printf.printf "📋 Sample contacts:\n";
  let sample_contacts = list_take (min 5 contact_count) updated_contacts in
  List.iter (fun contact ->
    let state_str = match contact.state with
      | Some state -> string_of_state state
      | None -> "Unknown"
    in
    let birthday_str = match contact.birthday with
      | Some date -> string_of_date date
      | None -> "None"
    in
    let ed_str = match contact.effective_date with
      | Some date -> string_of_date date
      | None -> "None"
    in
    Printf.printf "  Contact %d: %s (%s) - Birthday: %s, ED: %s\n"
      contact.id contact.email state_str birthday_str ed_str
  ) sample_contacts;
  Printf.printf "\n";
  
  (* Run scheduler *)
  Printf.printf "⚙️  Running email scheduler...\n";
  let config = Scheduler.Config.default in
  match schedule_emails_streaming ~contacts:updated_contacts ~config ~total_contacts:contact_count with
  | Ok result ->
      Printf.printf "✅ Scheduling completed successfully!\n\n";
      
      Printf.printf "%s\n\n" (get_scheduling_summary result);
      
      (* Save schedules to database *)
      Printf.printf "💾 Saving %d schedules to database...\n" (List.length result.schedules);
      insert_email_schedules result.schedules;
      Printf.printf "   Schedules saved!\n\n";
      
      (* Show scheduling breakdown *)
      let schedule_counts = Hashtbl.create 10 in
      List.iter (fun schedule ->
        let date_str = string_of_date schedule.scheduled_date in
        let current_count = match Hashtbl.find_opt schedule_counts date_str with
          | Some count -> count
          | None -> 0
        in
        Hashtbl.replace schedule_counts date_str (current_count + 1)
      ) result.schedules;
      
      Printf.printf "📅 Scheduled Email Summary by Date:\n";
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
      
      Printf.printf "\n🎉 Database scheduler completed successfully!\n"
      
  | Error error ->
      Printf.printf "❌ Scheduling failed: %s\n" (string_of_error error);
      exit 1

let () = run_database_scheduler ()