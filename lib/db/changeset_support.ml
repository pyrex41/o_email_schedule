(* SQLite Changeset Support using Sessions Extension *)

open Database_native

(* External C functions for changeset operations *)
external apply_changeset_c : string -> string -> int = "apply_changeset_stub"
external create_changeset_c : string -> string -> string -> int = "create_changeset_stub"

type changeset_error = 
  | ChangesetNotFound of string
  | ChangesetCorrupted of string
  | ApplicationFailed of string

let string_of_changeset_error = function
  | ChangesetNotFound path -> "Changeset file not found: " ^ path
  | ChangesetCorrupted msg -> "Changeset corrupted: " ^ msg
  | ApplicationFailed msg -> "Changeset application failed: " ^ msg

(* Apply a binary changeset file to the database *)
let apply_changeset_file changeset_path =
  match get_db_connection () with
  | Error err -> Error (ApplicationFailed (string_of_db_error err))
  | Ok _db ->
      if not (Sys.file_exists changeset_path) then
        Error (ChangesetNotFound changeset_path)
      else
        let db_path = !db_path in
        match apply_changeset_c db_path changeset_path with
        | 0 -> Ok ()
        | 1 -> Error (ChangesetNotFound changeset_path)
        | 2 -> Error (ChangesetCorrupted "Invalid changeset format")
        | _ -> Error (ApplicationFailed "Unknown error during application")

(* Create a changeset between two database states *)
let create_changeset_between old_db new_db output_path =
  match create_changeset_c old_db new_db output_path with
  | 0 -> Ok ()
  | 1 -> Error (ChangesetNotFound "Source database not found")
  | 2 -> Error (ApplicationFailed "Failed to create changeset")
  | _ -> Error (ApplicationFailed "Unknown error during creation")

(* Apply changeset with conflict resolution *)
let apply_changeset_with_resolution changeset_path ~on_conflict =
  match apply_changeset_file changeset_path with
  | Ok () -> Ok ()
  | Error (ApplicationFailed _) when on_conflict = `Ignore -> 
      Printf.printf "Warning: Changeset conflicts ignored\n%!";
      Ok ()
  | Error err -> Error err

(* Check if changeset is valid *)
let validate_changeset changeset_path =
  if not (Sys.file_exists changeset_path) then
    Error (ChangesetNotFound changeset_path)
  else
    (* Simple validation - try to read header *)
    try
      let ic = open_in_bin changeset_path in
      let header = really_input_string ic 8 in
      close_in ic;
      if String.length header = 8 then Ok ()
      else Error (ChangesetCorrupted "Invalid header")
    with
    | _ -> Error (ChangesetCorrupted "Cannot read changeset file") 