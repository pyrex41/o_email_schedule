open Scheduler.Types
open Scheduler.Zip_data

let test_zip_functionality () =
  Printf.printf "=== ZIP Code Integration Test ===\n\n";
  
  match load_zip_data () with
  | Ok () ->
      Printf.printf "✅ ZIP data loaded successfully!\n\n";
      
      let test_zips = [
        ("90210", "CA");
        ("10001", "NY");
        ("06830", "CT");
        ("89101", "NV");
        ("63101", "MO");
        ("97201", "OR");
      ] in
      
      Printf.printf "🔍 Testing specific ZIP codes:\n";
      List.iter (fun (zip, expected_state) ->
        match state_from_zip_code zip with
        | Some state ->
            let state_str = string_of_state state in
            let status = if state_str = expected_state then "✅" else "❌" in
            Printf.printf "  %s → %s (expected %s) %s\n" zip state_str expected_state status
        | None ->
            Printf.printf "  %s → Not found ❌\n" zip
      ) test_zips;
      
      Printf.printf "\n📊 ZIP code validation:\n";
      let valid_zips = ["90210"; "10001-1234"; "12345"] in
      let invalid_zips = ["9021"; "abcde"; "123456"] in
      
      List.iter (fun zip ->
        let is_valid = is_valid_zip_code zip in
        Printf.printf "  %s: %s\n" zip (if is_valid then "✅ Valid" else "❌ Invalid")
      ) (valid_zips @ invalid_zips);
      
  | Error msg ->
      Printf.printf "❌ Failed to load ZIP data: %s\n" msg;
      
  Printf.printf "\n🎉 ZIP code test completed!\n"

let () = test_zip_functionality ()