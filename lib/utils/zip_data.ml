open Types

type zip_info = {
  state: string;
  counties: string list;
  cities: string list option;
}

let zip_table = Hashtbl.create 50000

let load_zip_data () =
  try
    let ic = open_in "zipData.json" in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;
    
    let json = Yojson.Safe.from_string content in
    let open Yojson.Safe.Util in
    
    json |> to_assoc |> List.iter (fun (zip_code, zip_obj) ->
      try
        let state = zip_obj |> member "state" |> to_string in
        let counties = zip_obj |> member "counties" |> to_list |> List.map to_string in
        let cities = 
          try
            Some (zip_obj |> member "cities" |> to_list |> List.map to_string)
          with _ -> None
        in
        let zip_info = { state; counties; cities } in
        Hashtbl.add zip_table zip_code zip_info
      with e ->
        Printf.eprintf "Warning: Failed to parse ZIP code %s: %s\n" zip_code (Printexc.to_string e)
    );
    Printf.printf "Loaded %d ZIP codes\n" (Hashtbl.length zip_table);
    Ok ()
  with e ->
    Error (Printf.sprintf "Failed to load ZIP data: %s" (Printexc.to_string e))

let state_from_zip_code zip_code =
  let clean_zip = 
    if String.length zip_code >= 5 then
      String.sub zip_code 0 5
    else
      zip_code
  in
  
  match Hashtbl.find_opt zip_table clean_zip with
  | Some zip_info -> Some (state_of_string zip_info.state)
  | None -> None

let is_valid_zip_code zip_code =
  let clean_zip = 
    if String.length zip_code >= 5 then
      String.sub zip_code 0 5
    else
      zip_code
  in
  Hashtbl.mem zip_table clean_zip

let get_zip_info zip_code =
  let clean_zip = 
    if String.length zip_code >= 5 then
      String.sub zip_code 0 5
    else
      zip_code
  in
  Hashtbl.find_opt zip_table clean_zip

let ensure_loaded () =
  if Hashtbl.length zip_table = 0 then
    match load_zip_data () with
    | Ok () -> ()
    | Error msg -> failwith msg
  else
    ()