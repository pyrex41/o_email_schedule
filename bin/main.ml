open Scheduler.Types
open Scheduler.Simple_date
open Scheduler.Contact
open Scheduler.Exclusion_window

let create_sample_contact id email zip birthday_year birthday_month birthday_day =
  let birthday = if birthday_year > 0 then Some (make_date birthday_year birthday_month birthday_day) else None in
  let contact = {
    id;
    email;
    zip_code = Some zip;
    state = None;
    birthday;
    effective_date = None;
  } in
  update_contact_state contact

let demo_exclusion_checking () =
  Printf.printf "=== Email Scheduler Demo ===\n\n";
  
  let _ = Scheduler.Zip_data.load_zip_data () in
  
  let contacts = [
    create_sample_contact 1 "alice@example.com" "90210" 1990 6 15; 
    create_sample_contact 2 "bob@example.com" "10001" 1985 12 25;   
    create_sample_contact 3 "charlie@example.com" "06830" 1992 2 29; 
    create_sample_contact 4 "diana@example.com" "89101" 1988 3 10;   
  ] in
  
  let today = current_date () in
  Printf.printf "Today's date: %s\n\n" (string_of_date today);
  
  List.iteri (fun i contact ->
    Printf.printf "Contact %d: %s from %s\n" (i+1) contact.email 
      (match contact.state with Some s -> string_of_state s | None -> "Unknown");
    
    Printf.printf "  Valid for scheduling: %b\n" (is_valid_for_scheduling contact);
    
    match contact.birthday with
    | Some bd ->
        Printf.printf "  Birthday: %s\n" (string_of_date bd);
        let exclusion_result = check_exclusion_window contact today in
        begin match exclusion_result with
        | NotExcluded -> Printf.printf "  ✅ No exclusions - can send email\n"
        | Excluded { reason; window_end } -> 
            Printf.printf "  ❌ %s\n" reason;
            match window_end with
            | Some end_date -> Printf.printf "  Window ends: %s\n" (string_of_date end_date)
            | None -> Printf.printf "  Year-round exclusion\n"
        end
    | None -> Printf.printf "  No birthday on file\n";
    
    Printf.printf "\n"
  ) contacts;
  
  Printf.printf "Demo completed successfully! 🎉\n"

let () = demo_exclusion_checking ()
