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

(* Enhanced validation for anniversary emails that considers organization config *)
let is_valid_for_anniversary_scheduling (org_config : Types.enhanced_organization_config) contact =
  (* Basic email validation *)
  if not (validate_email contact.email) then
    false
  else
    (* For anniversary emails, we need location data unless org allows universal sending *)
    match contact.zip_code, contact.state with
    | None, None -> org_config.send_without_zipcode_for_universal
    | Some zip, None -> 
        (* Try to get state from zip *)
        (match state_from_zip_code zip with
         | Some _ -> true
         | None -> org_config.send_without_zipcode_for_universal)
    | _, Some _ -> true (* Has state, so valid *)

(* Enhanced validation for campaigns that considers targeting and organization config *)
let is_valid_for_campaign_scheduling (org_config : Types.enhanced_organization_config) campaign_instance contact =
  (* Basic email validation *)
  if not (validate_email contact.email) then
    false
  else
    (* Check if we need location data for this campaign *)
    let requires_location = match (campaign_instance.target_states, campaign_instance.target_carriers) with
      | (None, None) -> false (* Universal campaign *)
      | (Some states, _) when states = "ALL" -> false (* Explicitly universal *)
      | (_, Some carriers) when carriers = "ALL" -> false (* Explicitly universal *)
      | _ -> true (* Has targeting constraints *)
    in
    
    if requires_location then
      (* Campaign has targeting - need valid location data *)
      contact.zip_code <> None || contact.state <> None
    else
      (* Universal campaign - send even without zip code if org allows *)
      org_config.send_without_zipcode_for_universal

let is_zip_code_valid zip =
  Zip_data.ensure_loaded ();
  Zip_data.is_valid_zip_code zip