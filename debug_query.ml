open Scheduler.Db.Database

let test_query () =
  set_db_path "test_aep_campaign.db";
  match get_contacts_in_scheduling_window 60 14 with
  | Error err -> Printf.printf "Error: %s\n" (string_of_db_error err)
  | Ok contacts -> Printf.printf "Success: %d contacts\n" (List.length contacts)

let () = test_query ()