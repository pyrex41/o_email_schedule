open Types

let validate_email email =
  let email_regex = Str.regexp "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z][a-zA-Z]+$" in
  Str.string_match email_regex email 0

let validate_zip_code zip =
  let zip_regex = Str.regexp "^[0-9][0-9][0-9][0-9][0-9]\\(-[0-9][0-9][0-9][0-9]\\)?$" in
  Str.string_match zip_regex zip 0

let state_from_zip_code zip_code =
  Zip_data.ensure_loaded ();
  Zip_data.state_from_zip_code zip_code

let validate_contact contact =
  let errors = ref [] in
  
  if not (validate_email contact.email) then
    errors := "Invalid email format" :: !errors;
  
  begin match contact.zip_code with
  | Some zip when not (validate_zip_code zip) ->
      errors := "Invalid ZIP code format" :: !errors
  | Some zip when contact.state = None ->
      begin match state_from_zip_code zip with
      | None -> errors := "Cannot determine state from ZIP code" :: !errors
      | _ -> ()
      end
  | None -> errors := "Missing ZIP code" :: !errors
  | _ -> ()
  end;
  
  match !errors with
  | [] -> Ok contact
  | errs -> Error (String.concat "; " errs)

let update_contact_state contact =
  match contact.zip_code with
  | Some zip -> { contact with state = state_from_zip_code zip }
  | None -> contact

let is_valid_for_scheduling contact =
  match validate_contact contact with
  | Ok c -> c.state <> None
  | Error _ -> false

let is_zip_code_valid zip =
  Zip_data.ensure_loaded ();
  Zip_data.is_valid_zip_code zip