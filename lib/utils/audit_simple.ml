open Types

let calculate_checksum data =
  let hash = Hashtbl.hash data in
  Printf.sprintf "%08x" hash

let calculate_contacts_checksum contacts =
  Printf.sprintf "checksum_%d" (List.length contacts)

let log_scheduling_event ~run_id ~event ~details =
  Printf.printf "[%s] %s - %s\n" run_id event details

let log_error ~run_id ~error =
  let error_message = string_of_error error in
  log_scheduling_event ~run_id ~event:"ERROR" ~details:error_message