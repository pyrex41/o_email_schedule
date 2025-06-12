open Scheduler.Email_scheduler
open Scheduler.Db.Database

let debug_schedule_generation db_path =
  Printf.printf "=== Debugging Schedule Generation ===\n";
  
  (* Set database path *)
  set_db_path db_path;
  
  (* Initialize database *)
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      exit 1
  | Ok () ->
      Printf.printf "✅ Database connected\n";
      
      (* Load contacts *)
      match get_all_contacts () with
      | Error err ->
          Printf.printf "❌ Failed to load contacts: %s\n" (string_of_db_error err);
          exit 1
      | Ok contacts ->
          Printf.printf "📊 Loaded %d contacts\n" (List.length contacts);
          
          let config = Scheduler.Config.default in
          
          (* Generate schedules *)
          match schedule_emails_streaming ~contacts ~config ~_total_contacts:(List.length contacts) with
          | Error err ->
              Printf.printf "❌ Scheduling failed: %s\n" (Scheduler.Types.string_of_error err);
              exit 1
          | Ok result ->
              Printf.printf "📋 Generated %d schedules\n" (List.length result.schedules);
              
              (* Print each schedule for debugging *)
              List.iteri (fun i (email_schedule : Scheduler.Types.email_schedule) ->
                Printf.printf "%d. Contact %d: %s on %s (status: %s)\n"
                  (i + 1)
                  email_schedule.contact_id
                  (Scheduler.Types.string_of_email_type email_schedule.email_type)
                  (Scheduler.Date_time.string_of_date email_schedule.scheduled_date)
                  (match email_schedule.status with 
                   | PreScheduled -> "pre-scheduled"
                   | Skipped reason -> "skipped: " ^ reason
                   | _ -> "other")
              ) result.schedules;
              
              (* Check for duplicates *)
              let schedule_keys = List.map (fun (email_schedule : Scheduler.Types.email_schedule) ->
                (email_schedule.contact_id, Scheduler.Types.string_of_email_type email_schedule.email_type, Scheduler.Date_time.string_of_date email_schedule.scheduled_date)
              ) result.schedules in
              
              let unique_keys = List.sort_uniq compare schedule_keys in
              
              if List.length schedule_keys <> List.length unique_keys then (
                Printf.printf "\n❌ FOUND DUPLICATE SCHEDULES!\n";
                Printf.printf "Total schedules: %d, Unique: %d\n" (List.length schedule_keys) (List.length unique_keys);
                
                (* Find and show duplicates *)
                let rec find_dups all unique_so_far =
                  match all with
                  | [] -> []
                  | key :: rest ->
                      if List.mem key unique_so_far then
                        key :: find_dups rest unique_so_far
                      else
                        find_dups rest (key :: unique_so_far)
                in
                let duplicates = find_dups schedule_keys [] in
                List.iter (fun (contact_id, email_type, date) ->
                  Printf.printf "Duplicate: Contact %d, Type %s, Date %s\n" contact_id email_type date
                ) duplicates
              ) else (
                Printf.printf "\n✅ No duplicate schedules found\n"
              )

let () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  debug_schedule_generation db_path