open Scheduler.Email_scheduler
open Scheduler.Db.Database
open Scheduler.Types
open Scheduler.Date_time

(* Debug version that loads ALL contacts and shows campaign processing details *)

let run_debug_campaign_scheduler db_path =
  Printf.printf "=== DEBUG Campaign Scheduler ===\n\n";
  
  (* Set database path *)
  set_db_path db_path;
  
  (* Initialize database *)
  match initialize_database () with
  | Error err -> 
      Printf.printf "❌ Database initialization failed: %s\n" (string_of_db_error err);
      exit 1
  | Ok () ->
      Printf.printf "✅ Database connected successfully\n";
      
      (* Load ZIP data *)
      let _ = Scheduler.Zip_data.ensure_loaded () in
      Printf.printf "✅ ZIP data loaded\n";
      
      (* Debug: Show active campaign instances *)
      Printf.printf "\n🔍 DEBUG: Checking active campaign instances...\n";
      (match get_active_campaign_instances () with
       | Error err ->
           Printf.printf "❌ Failed to get active campaigns: %s\n" (string_of_db_error err);
       | Ok campaigns ->
           Printf.printf "   Found %d active campaign instances:\n" (List.length campaigns);
           List.iter (fun campaign ->
             Printf.printf "     📅 %s (%s): %s to %s\n" 
               campaign.instance_name 
               campaign.campaign_type
               (match campaign.active_start_date with Some d -> string_of_date d | None -> "N/A")
               (match campaign.active_end_date with Some d -> string_of_date d | None -> "N/A")
           ) campaigns);
      
      (* Try to load contacts with both approaches *)
      Printf.printf "\n🔍 DEBUG: Trying different contact loading approaches...\n";
      
      (* Approach 1: Scheduling window *)
      Printf.printf "📊 Approach 1: Scheduling window (365 days ahead, 30 back)...\n";
      (match get_contacts_in_scheduling_window 365 30 with
       | Error err ->
           Printf.printf "   ❌ Scheduling window failed: %s\n" (string_of_db_error err);
       | Ok contacts ->
           Printf.printf "   ✅ Scheduling window found %d contacts\n" (List.length contacts));
      
      (* Approach 2: All contacts *)
      Printf.printf "📊 Approach 2: All contacts...\n";
      (match get_all_contacts () with
       | Error err ->
           Printf.printf "   ❌ All contacts failed: %s\n" (string_of_db_error err);
       | Ok contacts ->
           Printf.printf "   ✅ All contacts found %d contacts\n" (List.length contacts);
           
           if List.length contacts > 0 then (
             Printf.printf "\n⚡ Running comprehensive scheduler with ALL %d contacts...\n" (List.length contacts);
             
             let config = Scheduler.Config.default in
             
             match schedule_emails_streaming ~contacts ~config ~_total_contacts:(List.length contacts) with
             | Ok result ->
                 Printf.printf "✅ Scheduling completed!\n";
                 Printf.printf "   Schedules generated: %d\n" (List.length result.schedules);
                 Printf.printf "   Errors: %d\n" (List.length result.errors);
                 
                 (* Show email types *)
                 let type_counts = Hashtbl.create 10 in
                 List.iter (fun schedule ->
                   let type_str = string_of_email_type schedule.email_type in
                   let current_count = match Hashtbl.find_opt type_counts type_str with
                     | Some count -> count
                     | None -> 0
                   in
                   Hashtbl.replace type_counts type_str (current_count + 1)
                 ) result.schedules;
                 
                 Printf.printf "\n📈 Email Types Generated:\n";
                 Hashtbl.iter (fun email_type count ->
                   Printf.printf "  %s: %d emails\n" email_type count
                 ) type_counts;
                 
                 if result.errors <> [] then (
                   Printf.printf "\n⚠️ Errors:\n";
                   List.iter (fun error ->
                     Printf.printf "  - %s\n" (string_of_error error)
                   ) result.errors
                 );
                 
             | Error error ->
                 Printf.printf "❌ Scheduling failed: %s\n" (string_of_error error)
           ))

let main () =
  let argc = Array.length Sys.argv in
  if argc < 2 then (
    Printf.printf "Usage: %s <database_path>\n" Sys.argv.(0);
    exit 1
  );
  
  let db_path = Sys.argv.(1) in
  run_debug_campaign_scheduler db_path

let () = main ()