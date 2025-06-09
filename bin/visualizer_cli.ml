open Cmdliner
open Visualizer.Ast_analyzer
open Visualizer.Json_serializer

(** Take first n elements from a list *)
let rec take n = function
  | [] -> []
  | _ when n <= 0 -> []
  | x :: xs -> x :: take (n - 1) xs

(** Configuration for the visualizer *)
type config = {
  input_files : string list;
  output_dir : string;
  web_port : int option;
  serve : bool;
  verbose : bool;
  max_complexity : int option;
}

(** Default configuration *)
let default_config = {
  input_files = [];
  output_dir = "visualizer_output";
  web_port = None;
  serve = false;
  verbose = false;
  max_complexity = None;
}

(** Find OCaml files recursively in a directory *)
let rec find_ocaml_files dir =
  let open Unix in
  if Sys.is_directory dir then
    let files = Sys.readdir dir in
    Array.fold_left (fun acc file ->
      let full_path = Filename.concat dir file in
      if Sys.is_directory full_path then
        (find_ocaml_files full_path) @ acc
      else if Filename.check_suffix file ".ml" || Filename.check_suffix file ".mli" then
        full_path :: acc
      else
        acc
    ) [] files
  else
    [dir]

(** Collect all input files *)
let collect_input_files paths =
  List.concat_map (fun path ->
    if Sys.file_exists path then
      if Sys.is_directory path then
        find_ocaml_files path
      else
        [path]
    else begin
      Printf.eprintf "Warning: File or directory '%s' does not exist\n" path;
      []
    end
  ) paths

(** Copy web assets to output directory *)
let copy_web_assets output_dir =
  let web_files = [
    ("web/index.html", "index.html");
    ("web/visualizer.js", "visualizer.js");
  ] in
  
  List.iter (fun (src, dst) ->
    let dst_path = Filename.concat output_dir dst in
    if Sys.file_exists src then
      let content = 
        let ic = open_in src in
        let content = really_input_string ic (in_channel_length ic) in
        close_in ic;
        content
      in
      let oc = open_out dst_path in
      output_string oc content;
      close_out oc;
      Printf.printf "Copied %s -> %s\n" src dst_path
    else
      Printf.eprintf "Warning: Web asset '%s' not found\n" src
  ) web_files

(** Start a simple HTTP server *)
let start_server output_dir port =
  let open Unix in
  Printf.printf "Starting web server on port %d...\n" port;
  Printf.printf "Visit http://localhost:%d to view the visualization\n" port;
  
  (* Create a simple Python HTTP server command *)
  let server_cmd = Printf.sprintf "cd %s && python3 -m http.server %d" output_dir port in
  let exit_code = Sys.command server_cmd in
  if exit_code <> 0 then
    Printf.eprintf "Failed to start web server (exit code: %d)\n" exit_code

(** Print analysis summary *)
let print_summary analysis config =
  Printf.printf "\n=== OCaml Program Flow Analysis Summary ===\n";
  Printf.printf "Files analyzed: %d\n" (List.length config.input_files);
  Printf.printf "Functions found: %d\n" (List.length analysis.functions);
  Printf.printf "Modules found: %d\n" (List.length analysis.modules);
  
  if List.length analysis.errors > 0 then begin
    Printf.printf "\nErrors encountered:\n";
    List.iter (Printf.printf "  - %s\n") analysis.errors
  end;
  
  (* Print complexity statistics *)
  let complexities = List.map (fun f -> f.complexity_score) analysis.functions in
  if List.length complexities > 0 then begin
    let min_complexity = List.fold_left min (List.hd complexities) complexities in
    let max_complexity = List.fold_left max (List.hd complexities) complexities in
    let avg_complexity = 
      float_of_int (List.fold_left (+) 0 complexities) /. float_of_int (List.length complexities)
    in
    Printf.printf "\nComplexity Statistics:\n";
    Printf.printf "  Min: %d, Max: %d, Average: %.1f\n" min_complexity max_complexity avg_complexity;
  end;
  
  (* Print top-level functions by complexity *)
  let sorted_functions = 
    analysis.functions 
    |> List.sort (fun a b -> compare b.complexity_score a.complexity_score)
    |> (fun l -> if List.length l > 10 then take 10 l else l)
  in
  if List.length sorted_functions > 0 then begin
    Printf.printf "\nMost Complex Functions:\n";
    List.iter (fun f ->
      Printf.printf "  %s (complexity: %d, calls: %d)\n" 
        f.name f.complexity_score (List.length f.calls)
    ) sorted_functions
  end;
  
  Printf.printf "\nVisualization generated in: %s/\n" config.output_dir

(** Main analysis and generation function *)
let run_analysis config =
  if config.verbose then
    Printf.printf "Analyzing %d OCaml files...\n" (List.length config.input_files);
  
  (* Ensure opam environment is loaded *)
  let _ = Sys.command "eval $(opam env) 2>/dev/null" in
  
  (* Run the analysis *)
  let analysis = analyze_files config.input_files in
  
  if config.verbose then begin
    Printf.printf "Analysis complete. Found %d functions.\n" (List.length analysis.functions);
    if List.length analysis.errors > 0 then
      Printf.printf "Encountered %d errors during analysis.\n" (List.length analysis.errors)
  end;
  
  (* Generate visualization data *)
  let result = export_complete_visualization config.input_files config.output_dir in
  
  (* Copy web assets *)
  copy_web_assets config.output_dir;
  
  (* Print summary *)
  print_summary result config;
  
  (* Start web server if requested *)
  if config.serve then begin
    let port = Option.value config.web_port ~default:8000 in
    start_server config.output_dir port
  end else begin
    let port = Option.value config.web_port ~default:8000 in
    Printf.printf "To view the visualization, run:\n";
    Printf.printf "  cd %s && python3 -m http.server %d\n" config.output_dir port;
    Printf.printf "Then visit http://localhost:%d\n" port
  end

(** Command line argument definitions *)
let input_files =
  let doc = "OCaml source files or directories to analyze" in
  Arg.(non_empty & pos_all string [] & info [] ~docv:"FILES" ~doc)

let output_dir =
  let doc = "Output directory for visualization files" in
  Arg.(value & opt string default_config.output_dir & info ["o"; "output"] ~docv:"DIR" ~doc)

let web_port =
  let doc = "Port for the web server (default: 8000)" in
  Arg.(value & opt (some int) None & info ["p"; "port"] ~docv:"PORT" ~doc)

let serve =
  let doc = "Start a web server after generating the visualization" in
  Arg.(value & flag & info ["s"; "serve"] ~doc)

let verbose =
  let doc = "Enable verbose output" in
  Arg.(value & flag & info ["v"; "verbose"] ~doc)

let max_complexity =
  let doc = "Filter functions by maximum complexity" in
  Arg.(value & opt (some int) None & info ["c"; "max-complexity"] ~docv:"N" ~doc)

(** Build configuration from command line arguments *)
let build_config input_files output_dir web_port serve verbose max_complexity =
  let collected_files = collect_input_files input_files in
  if List.length collected_files = 0 then begin
    Printf.eprintf "Error: No OCaml files found to analyze\n";
    exit 1
  end;
  {
    input_files = collected_files;
    output_dir;
    web_port;
    serve;
    verbose;
    max_complexity;
  }

(** Main command definition *)
let main_cmd =
  let doc = "Generate interactive visualizations for OCaml program flow" in
  let man = [
    `S Manpage.s_description;
    `P "The OCaml Program Flow Visualizer analyzes OCaml source code to extract function definitions, call relationships, and documentation. It generates an interactive web-based visualization that allows users to explore the code structure dynamically.";
    `S Manpage.s_examples;
    `P "Analyze a single file:";
    `Pre "  $(tname) src/main.ml";
    `P "Analyze all files in a directory:";
    `Pre "  $(tname) src/";
    `P "Generate visualization and start web server:";
    `Pre "  $(tname) --serve --port 9000 src/";
    `P "Filter by complexity:";
    `Pre "  $(tname) --max-complexity 10 src/";
    `S Manpage.s_see_also;
    `P "For more information, see the project documentation.";
  ] in
  Term.(const run_analysis $ const build_config $ input_files $ output_dir $ web_port $ serve $ verbose $ max_complexity),
  Cmd.info "ocaml-visualizer" ~version:"1.0.0" ~doc ~man

(** Version command *)
let version_cmd =
  let doc = "Show version information" in
  Term.(const (fun () -> Printf.printf "OCaml Program Flow Visualizer v1.0.0\n") $ const ()),
  Cmd.info "version" ~doc

(** Help command with examples *)
let help_cmd =
  let doc = "Show detailed help and examples" in
  let help_text = {|
OCaml Program Flow Visualizer - Detailed Help

DESCRIPTION:
  This tool analyzes OCaml source code to create interactive visualizations
  of function call flows and program structure. It uses advanced AST parsing
  and static analysis to extract function definitions, call relationships,
  and documentation comments.

FEATURES:
  • Interactive flow diagrams with Mermaid.js
  • Function complexity analysis
  • Documentation extraction from OCaml comments
  • Module hierarchy visualization
  • Click-to-explore navigation
  • Source code viewing with syntax highlighting
  • Export capabilities for diagrams

USAGE EXAMPLES:

  1. Basic analysis of a single file:
     ocaml-visualizer src/scheduler.ml

  2. Analyze entire project directory:
     ocaml-visualizer lib/ bin/

  3. Generate and serve immediately:
     ocaml-visualizer --serve --port 8080 .

  4. Filter complex functions only:
     ocaml-visualizer --max-complexity 15 src/

  5. Verbose analysis with custom output:
     ocaml-visualizer --verbose --output docs/ lib/

OUTPUT STRUCTURE:
  visualizer_output/
  ├── index.html              # Main web interface
  ├── visualizer.js           # Interactive functionality
  ├── visualization.json      # Analysis data
  └── source_data.json        # Source code content

TIPS:
  • Use --verbose to see detailed analysis progress
  • Start with --max-complexity filter for large codebases
  • The web interface works best in modern browsers
  • Export diagrams as SVG for documentation

For bug reports and feature requests, please visit the project repository.
|} in
  Term.(const (fun () -> Printf.printf "%s\n" help_text) $ const ()),
  Cmd.info "help" ~doc

(** Main entry point *)
let () =
  let cmds = [version_cmd; help_cmd] in
  exit (Cmd.eval (Cmd.group main_cmd cmds))