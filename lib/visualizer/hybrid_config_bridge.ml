open Visualizer.Ast_analyzer
open Visualizer.Json_serializer
open Yojson.Safe

(** Bridge module to connect existing AST analyzer with Hybrid Configuration Visualizer *)

(** Convert AST analysis results to Elm-compatible format *)
let analysis_to_elm_format analysis =
  let functions_json = 
    analysis.functions
    |> List.map (fun func ->
        `Assoc [
          ("name", `String func.name);
          ("module", `String (String.concat "." func.module_path));
          ("parameters", `List (List.map (fun (name, type_opt) ->
            match type_opt with
            | Some typ -> `Assoc [("name", `String name); ("type", `String typ)]
            | None -> `Assoc [("name", `String name); ("type", `Null)]
          ) func.parameters));
          ("returnType", 
            match func.return_type with
            | Some typ -> `String typ
            | None -> `Null);
          ("complexityScore", `Int func.complexity_score);
          ("calls", `List (List.map (fun c -> `String c) func.calls));
          ("isRecursive", `Bool func.is_recursive);
          ("documentation", 
            match func.doc_comment with
            | Some doc -> `String doc
            | None -> `Null);
          ("sourceLocation", `Assoc [
            ("file", `String func.file);
            ("startLine", `Int func.start_line);
            ("endLine", `Int func.end_line)
          ]);
        ]
      )
  in
  `List functions_json

(** Extract hybrid configuration related functions *)
let extract_hybrid_config_functions analysis =
  let config_related_modules = [
    "Config"; "Size_profiles"; "Database"; "Email_scheduler";
    "Load_balancer"; "Exclusion_window"; "Types"; "System_constants"
  ] in
  
  let is_config_related func =
    let module_path = String.concat "." func.module_path in
    List.exists (fun module_name -> 
      String.contains module_path module_name || String.contains func.file module_name
    ) config_related_modules
  in
  
  let config_functions = List.filter is_config_related analysis.functions in
  { analysis with functions = config_functions }

(** Generate data flow mapping from function analysis *)
let generate_data_flow_mapping analysis =
  let function_to_dataflow_mapping = [
    ("load_organization_config", "Organization Config Loader");
    ("get_total_contact_count", "Contact Counter");
    ("auto_detect_profile", "Size Profile Calculator");
    ("load_balancing_for_profile", "Load Balancing Computer");
    ("apply_config_overrides", "Config Override Applier");
    ("calculate_anniversary_emails", "Email Scheduler");
    ("check_exclusion_window", "Exclusion Window Checker");
    ("priority_of_email_type", "Priority Calculator");
    ("redistribute_overflow", "Load Balancer");
  ] in
  
  let dataflow_functions = 
    analysis.functions
    |> List.filter (fun func ->
        List.exists (fun (fn_name, _) -> String.contains func.name fn_name) function_to_dataflow_mapping
      )
    |> List.map (fun func ->
        let dataflow_node = 
          List.find_map (fun (fn_name, node_name) ->
            if String.contains func.name fn_name then Some node_name else None
          ) function_to_dataflow_mapping
          |> Option.value ~default:"Unknown"
        in
        `Assoc [
          ("functionName", `String func.name);
          ("dataflowNode", `String dataflow_node);
          ("complexity", `Int func.complexity_score);
          ("module", `String (String.concat "." func.module_path));
          ("calls", `List (List.map (fun c -> `String c) func.calls));
        ]
      )
  in
  `List dataflow_functions

(** Create example organization configurations *)
let create_example_organizations () =
  `List [
    `Assoc [
      ("id", `Int 1);
      ("name", `String "Small Insurance Agency");
      ("sizeProfile", `String "small");
      ("totalContacts", `Int 5000);
      ("dailyCapPercentage", `Float 0.20);
      ("batchSize", `Int 1000);
      ("edSoftLimit", `Int 50);
      ("configOverrides", `Null);
    ];
    `Assoc [
      ("id", `Int 2);
      ("name", `String "Regional Insurance Company");
      ("sizeProfile", `String "medium");
      ("totalContacts", `Int 50000);
      ("dailyCapPercentage", `Float 0.10);
      ("batchSize", `Int 5000);
      ("edSoftLimit", `Int 200);
      ("configOverrides", `Null);
    ];
    `Assoc [
      ("id", `Int 3);
      ("name", `String "State-Wide Insurance Network");
      ("sizeProfile", `String "large");
      ("totalContacts", `Int 250000);
      ("dailyCapPercentage", `Float 0.07);
      ("batchSize", `Int 10000);
      ("edSoftLimit", `Int 500);
      ("configOverrides", `Assoc [("daily_send_percentage_cap", `Float 0.05)]);
    ];
    `Assoc [
      ("id", `Int 4);
      ("name", `String "National Insurance Corporation");
      ("sizeProfile", `String "enterprise");
      ("totalContacts", `Int 1000000);
      ("dailyCapPercentage", `Float 0.05);
      ("batchSize", `Int 25000);
      ("edSoftLimit", `Int 1000);
      ("configOverrides", `Assoc [
        ("daily_send_percentage_cap", `Float 0.03);
        ("batch_size", `Int 50000);
        ("ed_daily_soft_limit", `Int 2000);
      ]);
    ];
  ]

(** Generate system constants information *)
let generate_system_constants () =
  `Assoc [
    ("edPercentageOfDailyCap", `Float 0.3);
    ("overageThreshold", `Float 1.2);
    ("catchUpSpreadDays", `Int 7);
    ("followupLookbackDays", `Int 35);
    ("postWindowDelayDays", `Int 1);
    ("priorities", `Assoc [
      ("birthday", `Int 10);
      ("effectiveDate", `Int 20);
      ("postWindow", `Int 40);
      ("followup", `Int 50);
      ("defaultCampaign", `Int 30);
    ]);
    ("databaseSettings", `Assoc [
      ("sqliteCacheSize", `Int 500000);
      ("sqlitePageSize", `Int 8192);
      ("defaultBatchInsertSize", `Int 1000);
    ]);
    ("thresholds", `Assoc [
      ("largeDatasetThreshold", `Int 100000);
      ("hugeDatasetThreshold", `Int 500000);
    ]);
  ]

(** Create decision tree structure *)
let create_decision_tree_structure () =
  `Assoc [
    ("node", `String "LoadOrgConfig");
    ("condition", `String "org_id provided");
    ("complexity", `Int 5);
    ("module", `String "Database.load_organization_config");
    ("details", `List [
      `String "Connect to central Turso database";
      `String "Query organizations table for org configuration";
      `String "Parse business rules, preferences, and size profile";
      `String "Handle missing organization with fallback defaults";
    ]);
    ("children", `List [
      `Assoc [
        ("node", `String "CheckContactCount");
        ("condition", `String "switch to org database");
        ("complexity", `Int 3);
        ("module", `String "Database.get_total_contact_count");
        ("details", `List [
          `String "Set database path to org-specific SQLite file";
          `String "Execute SELECT COUNT(*) FROM contacts";
          `String "Use count for load balancing calculations";
          `String "Fall back to profile estimates if query fails";
        ]);
        ("children", `List [
          `Assoc [
            ("node", `String "DetermineProfile");
            ("condition", `String "contact count available");
            ("complexity", `Int 2);
            ("module", `String "Size_profiles.auto_detect_profile");
            ("details", `List [
              `String "< 10k contacts → Small profile";
              `String "10k-100k contacts → Medium profile";
              `String "100k-500k contacts → Large profile";
              `String "500k+ contacts → Enterprise profile";
              `String "Use org.size_profile if manually set";
            ]);
            ("children", `List []);
          ];
        ]);
      ];
    ]);
  ]

(** Generate complete visualization data for Elm app *)
let generate_hybrid_config_visualization filenames output_dir =
  (* Analyze the codebase *)
  let analysis = analyze_files filenames in
  let config_analysis = extract_hybrid_config_functions analysis in
  
  (* Create comprehensive visualization data *)
  let visualization_data = `Assoc [
    ("functions", analysis_to_elm_format config_analysis);
    ("dataFlowMapping", generate_data_flow_mapping config_analysis);
    ("exampleOrganizations", create_example_organizations ());
    ("systemConstants", generate_system_constants ());
    ("decisionTree", create_decision_tree_structure ());
    ("metadata", `Assoc [
      ("totalFunctions", `Int (List.length config_analysis.functions));
      ("hybridConfigFunctions", `Int (List.length config_analysis.functions));
      ("analysisTimestamp", `String (Printf.sprintf "%.0f" (Unix.time ())));
      ("sourceFiles", `List (List.map (fun f -> `String f) filenames));
    ]);
  ] in
  
  (* Ensure output directory exists *)
  (try Unix.mkdir output_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  
  (* Write the main visualization data *)
  let viz_file = Filename.concat output_dir "hybrid_config_data.json" in
  let oc = open_out viz_file in
  output_string oc (pretty_to_string visualization_data);
  close_out oc;
  
  (* Generate individual data files for different views *)
  
  (* Functions data for function call graph *)
  let functions_file = Filename.concat output_dir "functions.json" in
  let oc = open_out functions_file in
  output_string oc (pretty_to_string (analysis_to_elm_format config_analysis));
  close_out oc;
  
  (* Data flow mapping *)
  let dataflow_file = Filename.concat output_dir "dataflow.json" in
  let oc = open_out dataflow_file in
  output_string oc (pretty_to_string (generate_data_flow_mapping config_analysis));
  close_out oc;
  
  (* System constants *)
  let constants_file = Filename.concat output_dir "constants.json" in
  let oc = open_out constants_file in
  output_string oc (pretty_to_string (generate_system_constants ()));
  close_out oc;
  
  Printf.printf "Hybrid Configuration visualization data generated in %s/\n" output_dir;
  Printf.printf "Generated files:\n";
  Printf.printf "  - hybrid_config_data.json (main data)\n";
  Printf.printf "  - functions.json (function call graph data)\n";
  Printf.printf "  - dataflow.json (data flow mapping)\n";
  Printf.printf "  - constants.json (system constants)\n";
  
  config_analysis

(** Create API endpoints for serving data to Elm app *)
let create_api_server port data_dir =
  let serve_file filename content_type =
    let file_path = Filename.concat data_dir filename in
    if Sys.file_exists file_path then
      let ic = open_in file_path in
      let content = really_input_string ic (in_channel_length ic) in
      close_in ic;
      Printf.sprintf "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nAccess-Control-Allow-Origin: *\r\n\r\n%s" content_type content
    else
      "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nFile not found"
  in
  
  let handle_request request =
    if String.contains request "GET /api/functions" then
      serve_file "functions.json" "application/json"
    else if String.contains request "GET /api/dataflow" then
      serve_file "dataflow.json" "application/json"
    else if String.contains request "GET /api/constants" then
      serve_file "constants.json" "application/json"
    else if String.contains request "GET /api/hybrid-config" then
      serve_file "hybrid_config_data.json" "application/json"
    else
      "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\r\nEndpoint not found"
  in
  
  Printf.printf "Starting API server on port %d...\n" port;
  Printf.printf "Available endpoints:\n";
  Printf.printf "  GET /api/functions - Function call graph data\n";
  Printf.printf "  GET /api/dataflow - Data flow mapping\n";
  Printf.printf "  GET /api/constants - System constants\n";
  Printf.printf "  GET /api/hybrid-config - Complete hybrid config data\n";
  
  (* Simple HTTP server implementation would go here *)
  Printf.printf "API server configured (implementation depends on HTTP library)\n"

(** CLI command to generate hybrid config visualization *)
let generate_hybrid_visualization_cli filenames output_dir port serve =
  Printf.printf "🔄 Generating Hybrid Configuration System Visualization...\n";
  Printf.printf "Input files: %s\n" (String.concat ", " filenames);
  Printf.printf "Output directory: %s\n" output_dir;
  
  let analysis = generate_hybrid_config_visualization filenames output_dir in
  
  (* Copy Elm application files *)
  let copy_elm_files () =
    let elm_files = [
      ("index.html", "index.html");
      ("src/Main.elm", "elm/Main.elm");
      ("src/HybridConfig/Types.elm", "elm/HybridConfig/Types.elm");
      ("src/HybridConfig/DataFlow.elm", "elm/HybridConfig/DataFlow.elm");
      ("src/HybridConfig/MermaidDiagrams.elm", "elm/HybridConfig/MermaidDiagrams.elm");
    ] in
    
    List.iter (fun (src, dst) ->
      let dst_path = Filename.concat output_dir dst in
      let dst_dir = Filename.dirname dst_path in
      (try Unix.mkdir dst_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
      
      if Sys.file_exists src then
        let ic = open_in src in
        let content = really_input_string ic (in_channel_length ic) in
        close_in ic;
        let oc = open_out dst_path in
        output_string oc content;
        close_out oc;
        Printf.printf "Copied %s -> %s\n" src dst_path
      else
        Printf.printf "Warning: Source file %s not found\n" src
    ) elm_files
  in
  
  copy_elm_files ();
  
  if serve then
    create_api_server port output_dir
  else begin
    Printf.printf "\nTo view the visualization:\n";
    Printf.printf "1. Compile the Elm app:\n";
    Printf.printf "   cd %s && elm make elm/Main.elm --output=elm.js\n" output_dir;
    Printf.printf "2. Start a web server:\n";
    Printf.printf "   cd %s && python3 -m http.server %d\n" output_dir port;
    Printf.printf "3. Visit http://localhost:%d\n" port;
  end;
  
  analysis

(** Export functions for use in other modules *)
let export_for_standalone_visualizer filenames output_dir =
  generate_hybrid_config_visualization filenames output_dir