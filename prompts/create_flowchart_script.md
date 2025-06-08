## Part 3: Flow Chart Generation Script

Create a file `generate_documentation.ml`:

```ocaml
#!/usr/bin/env ocaml

(* Documentation Generation Script for OCaml Email Scheduler *)

#use "topfind"
#require "str"
#require "unix"

(* Extract function signatures and their documentation *)
let extract_documented_functions filename =
  let ic = open_in filename in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic;
  
  (* Regex to match documented functions *)
  let doc_regex = Str.regexp {|\(\*\* *\n\([^*]*\*[^/]\)*[^*]*\*\).*\nlet \([a-zA-Z_][a-zA-Z0-9_']*\)|} in
  
  let rec find_all pos acc =
    try
      let _ = Str.search_forward doc_regex content pos in
      let matched = Str.matched_string content in
      let next_pos = Str.match_end () in
      find_all next_pos (matched :: acc)
    with Not_found -> List.rev acc
  in
  
  find_all 0 []

(* Generate Mermaid diagram from code analysis *)
let generate_mermaid_from_module module_name content =
  let functions = extract_documented_functions content in
  
  (* Analyze function calls and dependencies *)
  let analyze_dependencies fn_content =
    (* Extract function calls - simplified *)
    let call_regex = Str.regexp {|\b\([a-zA-Z_][a-zA-Z0-9_']*\)\s*(|} in
    []  (* Implement actual dependency extraction *)
  in
  
  (* Generate Mermaid syntax *)
  let mermaid = Buffer.create 1000 in
  Buffer.add_string mermaid "```mermaid\n";
  Buffer.add_string mermaid (Printf.sprintf "graph TD\n    %s[%s Module]\n" module_name module_name);
  
  (* Add nodes and connections based on analysis *)
  List.iter (fun fn ->
    (* Process each function *)
    ()
  ) functions;
  
  Buffer.add_string mermaid "```\n";
  Buffer.contents mermaid

(* Main documentation generation *)
let generate_documentation () =
  (* Create output directory *)
  let _ = Unix.system "mkdir -p docs/diagrams" in
  
  (* Process each source file *)
  let process_file filepath =
    Printf.printf "Processing %s...\n" filepath;
    let content = 
      let ic = open_in filepath in
      let s = really_input_string ic (in_channel_length ic) in
      close_in ic;
      s
    in
    
    (* Extract module name *)
    let module_name = Filename.basename filepath |> Filename.chop_extension in
    
    (* Generate diagrams *)
    let mermaid = generate_mermaid_from_module module_name content in
    
    (* Save diagram *)
    let output_path = Printf.sprintf "docs/diagrams/%s.mmd" module_name in
    let oc = open_out output_path in
    output_string oc mermaid;
    close_out oc;
    
    Printf.printf "Generated %s\n" output_path
  in
  
  (* Find all ML files *)
  let ml_files = 
    let rec find_files dir =
      let entries = Sys.readdir dir in
      Array.fold_left (fun acc entry ->
        let path = Filename.concat dir entry in
        if Sys.is_directory path && entry <> "_build" then
          find_files path @ acc
        else if Filename.check_suffix entry ".ml" then
          path :: acc
        else
          acc
      ) [] entries
    in
    find_files "lib" @ find_files "bin"
  in
  
  List.iter process_file ml_files;
  
  (* Generate index *)
  let oc = open_out "docs/diagrams/README.md" in
  Printf.fprintf oc "# Email Scheduler - Business Logic Diagrams\n\n";
  Printf.fprintf oc "## Generated Diagrams\n\n";
  List.iter (fun file ->
    let name = Filename.basename file |> Filename.chop_extension in
    Printf.fprintf oc "- [%s](%s.mmd)\n" name name
  ) ml_files;
  close_out oc;
  
  Printf.printf "\nDocumentation generation complete!\n"

(* Run the generator *)
let () = generate_documentation ()