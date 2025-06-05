let debug_contact_validation () =
  Printf.printf "=== Contact Validation Debug ===\n\n";
  
  let _ = Scheduler.Zip_data.load_zip_data () in
  
  (* Test regex directly *)
  Printf.printf "Testing regex patterns:\n";
  
  let simple_email_regex = Str.regexp ".*@.*" in
  let simple_zip_regex = Str.regexp "[0-9][0-9][0-9][0-9][0-9]" in
  let correct_zip_regex = Str.regexp "^[0-9]\\{5\\}$" in
  
  Printf.printf "Simple email regex test 'alice@example.com': %b\n" (Str.string_match simple_email_regex "alice@example.com" 0);
  Printf.printf "Simple ZIP regex test '90210': %b\n" (Str.string_match simple_zip_regex "90210" 0);
  Printf.printf "Correct ZIP regex test '90210': %b\n" (Str.string_match correct_zip_regex "90210" 0);
  
  (* Test the exact patterns from contact.ml *)
  let email_regex = Str.regexp "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]\\{2,\\}$" in
  let zip_regex = Str.regexp "^[0-9]\\{5\\}\\(-[0-9]\\{4\\}\\)?$" in
  
  Printf.printf "Fixed email regex test 'alice@example.com': %b\n" (Str.string_match email_regex "alice@example.com" 0);
  Printf.printf "Fixed ZIP regex test '90210': %b\n" (Str.string_match zip_regex "90210" 0);
  
  Printf.printf "\n";
  
  (* Test ZIP code validation directly *)
  let test_zips = ["90210"; "10001"; "06830"; "89101"; "63101"; "97201"] in
  List.iter (fun zip ->
    Printf.printf "ZIP %s: valid_format=%b, in_db=%b\n" 
      zip 
      (Scheduler.Contact.validate_zip_code zip)
      (Scheduler.Zip_data.is_valid_zip_code zip)
  ) test_zips;
  
  Printf.printf "\n";
  
  (* Test email validation *)
  let test_emails = ["alice@example.com"; "invalid-email"; "bob@test.com"] in
  List.iter (fun email ->
    Printf.printf "Email %s: valid=%b\n" email (Scheduler.Contact.validate_email email)
  ) test_emails

let () = debug_contact_validation ()