open Scheduler.Email_scheduler
open Scheduler.Db.Database

let run_scheduler db_path =
  Printf.printf "[%s] 🚀 Starting email scheduler...\n%!" 
    (Unix.time () |> Unix.localtime |> fun tm -> 
     Printf.sprintf "%02d:%02d:%02d" tm.tm_hour tm.tm_min tm.tm_sec);
  
  set_db_path db_path;
  
  match initialize_database () with
  | Error err -> 
      Printf.printf "[ERROR] Database initialization failed: %s\n%!" (string_of_db_error err);
      exit 1
  | Ok () ->
      (* Load contacts in scheduling window *)
      Printf.printf "[INFO] Loading contacts in scheduling window...\n%!";
      match get_contacts_in_scheduling_window 60 14 with
      | Error err ->
          Printf.printf "[ERROR] Failed to load contacts: %s\n%!" (string_of_db_error err);
          exit 1
      | Ok contacts ->
          let contact_count = List.length contacts in
          Printf.printf "[INFO] Loaded %d contacts for scheduling\n%!" contact_count;
          
          if contact_count = 0 then (
            Printf.printf "[INFO] No contacts need scheduling. Exiting.\n%!";
            exit 0
          );
          
          (* Generate scheduler run ID *)
          let run_id = Printf.sprintf "scheduler_run_%f" (Unix.time ()) in
          Printf.printf "[INFO] Starting scheduler run: %s\n%!" run_id;
          
          (* Create context and process schedules *)
          let config = Scheduler.Config.default in
          let context = create_context config contact_count in
          let context_with_run_id = { context with run_id } in
          
          let total_schedules = ref 0 in
          let processed_contacts = ref 0 in
          
          List.iter (fun contact ->
            match calculate_schedules_for_contact context_with_run_id contact with
            | Ok schedules ->
                incr processed_contacts;
                let count = List.length schedules in
                total_schedules := !total_schedules + count;
                
                (* Insert schedules immediately *)
                (match batch_insert_schedules_optimized schedules with
                 | Ok inserted -> 
                     if inserted <> count then
                       Printf.printf "[WARN] Contact %d: Generated %d schedules, inserted %d\n%!" 
                         contact.id count inserted
                 | Error err ->
                     Printf.printf "[ERROR] Failed to insert schedules for contact %d: %s\n%!" 
                       contact.id (string_of_db_error err))
            | Error err ->
                Printf.printf "[WARN] Failed to calculate schedules for contact %d: %s\n%!" 
                  contact.id (Scheduler.Types.string_of_error err)
          ) contacts;
          
          Printf.printf "[SUCCESS] Scheduler completed:\n%!";
          Printf.printf "  • Processed contacts: %d/%d\n%!" !processed_contacts contact_count;
          Printf.printf "  • Total schedules created: %d\n%!" !total_schedules;
          Printf.printf "  • Run ID: %s\n%!" run_id;
          
          exit 0

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    Printf.printf "Example: %s /app/data/contacts.sqlite3\n" Sys.argv.(0);
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  run_scheduler db_path

let () = main () 