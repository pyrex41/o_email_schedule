open Yojson.Safe
open Ast_analyzer
open Call_graph
open Doc_extractor

(** Convert Location.t to JSON *)
let location_to_json _loc =
  `Assoc [
    ("file", `String "unknown");
    ("start_line", `Int 1);
    ("start_col", `Int 0);
    ("end_line", `Int 1);
    ("end_col", `Int 0);
  ]

(** Convert parsed documentation to JSON *)
let doc_to_json doc =
  let option_to_json f = function
    | Some v -> f v
    | None -> `Null
  in
  let string_pairs_to_json pairs =
    `List (List.map (fun (k, v) -> `Assoc [("name", `String k); ("description", `String v)]) pairs)
  in
  `Assoc [
    ("summary", option_to_json (fun s -> `String s) doc.summary);
    ("description", option_to_json (fun s -> `String s) doc.description);
    ("parameters", string_pairs_to_json doc.parameters);
    ("returns", option_to_json (fun s -> `String s) doc.returns);
    ("examples", `List (List.map (fun s -> `String s) doc.examples));
    ("see_also", `List (List.map (fun s -> `String s) doc.see_also));
    ("since", option_to_json (fun s -> `String s) doc.since);
    ("deprecated", option_to_json (fun s -> `String s) doc.deprecated);
    ("raises", string_pairs_to_json doc.raises);
    ("tags", string_pairs_to_json doc.tags);
  ]

(** Convert function info to JSON *)
let function_to_json func docs_map =
  let doc = match List.assoc_opt func.name docs_map with
    | Some d -> d
    | None -> empty_doc
  in
  `Assoc [
    ("name", `String func.name);
    ("location", location_to_json func.location);
    ("parameters", `List (List.map (fun p -> `String p) func.parameters));
    ("complexity_score", `Int func.complexity_score);
    ("calls", `List (List.map (fun c -> `String c) func.calls));
    ("is_recursive", `Bool func.is_recursive);
    ("module_path", `List (List.map (fun m -> `String m) func.module_path));
    ("documentation", doc_to_json doc);
    ("file", `String "unknown");
  ]

(** Convert enhanced call graph to JSON with metrics *)
let enhanced_call_graph_to_json enhanced_graph docs_map =
  let functions_json = 
    enhanced_graph.graph.vertices
    |> List.map (fun func -> function_to_json func docs_map)
  in
  
  let edges_json = 
    enhanced_graph.graph.edges
    |> List.map (fun (source, target) ->
        `Assoc [
          ("source", `String source);
          ("target", `String target);
        ])
  in
  
  let entry_points_json = 
    `List (List.map (fun f -> `String f.name) enhanced_graph.entry_points)
  in
  
  let cycles_json = 
    `List (List.map (fun cycle ->
      `List (List.map (fun f -> `String f.name) cycle)
    ) enhanced_graph.cycles)
  in
  
  let (min_complexity, max_complexity, avg_complexity) = enhanced_graph.complexity_stats in
  let complexity_stats_json = 
    `Assoc [
      ("min", `Int min_complexity);
      ("max", `Int max_complexity);
      ("average", `Float avg_complexity);
    ]
  in
  
  `Assoc [
    ("functions", `List functions_json);
    ("edges", `List edges_json);
    ("entry_points", entry_points_json);
    ("cycles", cycles_json);
    ("complexity_stats", complexity_stats_json);
  ]

(** Generate Mermaid diagram syntax *)
let generate_mermaid_diagram enhanced_graph ?(max_complexity = None) ?(show_modules = true) () =
  let buffer = Buffer.create 4096 in
  
  Buffer.add_string buffer "%%{init: {\"flowchart\": {\"defaultRenderer\": \"elk\"}} }%%\n";
  Buffer.add_string buffer "flowchart TD\n";
  
  let functions = enhanced_graph.graph.vertices in
  List.iter (fun func ->
    let should_include = match max_complexity with
      | Some threshold -> func.complexity_score <= threshold
      | None -> true
    in
    if should_include then begin
      let node_id = func.name in
      let module_prefix = if show_modules && List.length func.module_path > 0 then
        String.concat "." func.module_path ^ "."
      else ""
      in
      let display_name = module_prefix ^ func.name in
      
      let complexity_class = match func.complexity_score with
        | score when score > 10 -> "high-complexity"
        | score when score > 5 -> "medium-complexity"
        | _ -> "low-complexity"
      in
      
      let recursive_indicator = if func.is_recursive then " 🔄" else "" in
      
      Buffer.add_string buffer (Printf.sprintf "    %s[\"%s%s\"]:::%s\n" 
        node_id display_name recursive_indicator complexity_class);
    end
  ) functions;
  
  List.iter (fun (source, target) ->
    let src_func = List.find_opt (fun f -> f.name = source) functions in
    let dst_func = List.find_opt (fun f -> f.name = target) functions in
    let src_include = match max_complexity, src_func with
      | Some threshold, Some f -> f.complexity_score <= threshold
      | None, Some _ -> true
      | _ -> false
    in
    let dst_include = match max_complexity, dst_func with
      | Some threshold, Some f -> f.complexity_score <= threshold
      | None, Some _ -> true
      | _ -> false
    in
    if src_include && dst_include then
      Buffer.add_string buffer (Printf.sprintf "    %s --> %s\n" source target)
  ) enhanced_graph.graph.edges;
  
  List.iter (fun func ->
    let should_include = match max_complexity with
      | Some threshold -> func.complexity_score <= threshold
      | None -> true
    in
    if should_include then
      Buffer.add_string buffer (Printf.sprintf "    click %s callback \"Show details for %s\"\n" 
        func.name func.name)
  ) functions;
  
  Buffer.add_string buffer "\n";
  Buffer.add_string buffer "    classDef low-complexity fill:#d4edda,stroke:#28a745,stroke-width:2px\n";
  Buffer.add_string buffer "    classDef medium-complexity fill:#fff3cd,stroke:#ffc107,stroke-width:2px\n";
  Buffer.add_string buffer "    classDef high-complexity fill:#f8d7da,stroke:#dc3545,stroke-width:2px\n";
  
  Buffer.contents buffer

(** Generate complete visualization data package *)
let generate_visualization_data analysis =
  let docs_map = extract_all_docs analysis in
  let enhanced_graph = create_enhanced_call_graph analysis in
  
  let main_diagram = generate_mermaid_diagram enhanced_graph () in
  
  `Assoc [
    ("analysis", enhanced_call_graph_to_json enhanced_graph docs_map);
    ("diagrams", `Assoc [
      ("main", `String main_diagram);
    ]);
    ("metadata", `Assoc [
      ("total_functions", `Int (List.length analysis.functions));
      ("total_modules", `Int (List.length analysis.modules));
      ("entry_point_count", `Int (List.length enhanced_graph.entry_points));
      ("cycle_count", `Int (List.length enhanced_graph.cycles));
      ("generated_at", `String (Printf.sprintf "%.0f" (Unix.time ())));
    ]);
  ]

(** Save visualization data to file *)
let save_visualization_data analysis output_file =
  let data = generate_visualization_data analysis in
  let json_string = pretty_to_string data in
  let oc = open_out output_file in
  output_string oc json_string;
  close_out oc;
  Printf.printf "Visualization data saved to %s\n" output_file

(** Generate source code data for viewer *)
let generate_source_data filenames =
  let source_map = List.fold_left (fun acc filename ->
    try
      let content = 
        let ic = open_in filename in
        let content = really_input_string ic (in_channel_length ic) in
        close_in ic;
        content
      in
      (filename, content) :: acc
    with
    | _ -> acc
  ) [] filenames in
  
  `Assoc [
    ("files", `Assoc (List.map (fun (filename, content) -> 
      (filename, `String content)
    ) source_map));
  ]

(** Complete export function *)
let export_complete_visualization filenames output_dir =
  let analysis = analyze_files filenames in
  
  (try Unix.mkdir output_dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  
  let viz_file = Filename.concat output_dir "visualization.json" in
  save_visualization_data analysis viz_file;
  
  let source_data = generate_source_data filenames in
  let source_file = Filename.concat output_dir "source_data.json" in
  let oc = open_out source_file in
  output_string oc (pretty_to_string source_data);
  close_out oc;
  
  Printf.printf "Complete visualization data exported to %s/\n" output_dir;
  
  analysis