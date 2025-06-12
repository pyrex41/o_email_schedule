open Ast_analyzer

(** Simple graph representation using adjacency lists *)
type simple_graph = {
  vertices : function_info list;
  edges : (string * string) list; (* (source, target) *)
}

(** Function metrics type *)
type function_metrics = {
  in_degree : int;
  out_degree : int;
  dependency_count : int;
  reverse_dependency_count : int;
}

(** Enhanced call graph with metadata *)
type enhanced_call_graph = {
  graph : simple_graph;
  function_map : (string, function_info) Hashtbl.t;
  entry_points : function_info list;
  cycles : function_info list list;
  complexity_stats : (int * int * float);
}

(** Build call graph from analysis result *)
let build_call_graph analysis =
  let function_map = Hashtbl.create (List.length analysis.functions) in
  
  List.iter (fun func ->
    Hashtbl.add function_map func.name func
  ) analysis.functions;
  
  let graph = {
    vertices = analysis.functions;
    edges = analysis.call_graph;
  } in
  
  graph, function_map

(** Calculate in-degree for a function *)
let in_degree graph function_name =
  List.fold_left (fun acc (_, target) ->
    if target = function_name then acc + 1 else acc
  ) 0 graph.edges

(** Calculate out-degree for a function *)
let out_degree graph function_name =
  List.fold_left (fun acc (source, _) ->
    if source = function_name then acc + 1 else acc
  ) 0 graph.edges

(** Find entry points *)
let find_entry_points graph function_map =
  Hashtbl.fold (fun _ func acc ->
    if in_degree graph func.name = 0 then func :: acc else acc
  ) function_map []

(** Calculate complexity statistics *)
let calculate_complexity_stats functions =
  let complexities = List.map (fun f -> f.complexity_score) functions in
  match complexities with
  | [] -> (0, 0, 0.0)
  | _ ->
      let min_complexity = List.fold_left min (List.hd complexities) complexities in
      let max_complexity = List.fold_left max (List.hd complexities) complexities in
      let avg_complexity = 
        float_of_int (List.fold_left (+) 0 complexities) /. float_of_int (List.length complexities)
      in
      (min_complexity, max_complexity, avg_complexity)

(** Create enhanced call graph *)
let create_enhanced_call_graph analysis =
  let graph, function_map = build_call_graph analysis in
  let entry_points = find_entry_points graph function_map in
  let cycles = [] in
  let complexity_stats = calculate_complexity_stats analysis.functions in
  {
    graph;
    function_map;
    entry_points;
    cycles;
    complexity_stats;
  }

(** Get function dependencies *)
let get_dependencies enhanced_graph function_name =
  let rec get_callees visited name =
    if List.mem name visited then []
    else
      let new_visited = name :: visited in
      let direct_callees = 
        List.fold_left (fun acc (source, target) ->
          if source = name then target :: acc else acc
        ) [] enhanced_graph.graph.edges
      in
      let transitive_callees = 
        List.concat_map (get_callees new_visited) direct_callees
      in
      direct_callees @ transitive_callees
  in
  let callees = get_callees [] function_name in
  List.filter_map (fun name ->
    Hashtbl.find_opt enhanced_graph.function_map name
  ) (List.sort_uniq String.compare callees)

(** Get reverse dependencies *)
let get_reverse_dependencies enhanced_graph function_name =
  let rec get_callers visited name =
    if List.mem name visited then []
    else
      let new_visited = name :: visited in
      let direct_callers = 
        List.fold_left (fun acc (source, target) ->
          if target = name then source :: acc else acc
        ) [] enhanced_graph.graph.edges
      in
      let transitive_callers = 
        List.concat_map (get_callers new_visited) direct_callers
      in
      direct_callers @ transitive_callers
  in
  let callers = get_callers [] function_name in
  List.filter_map (fun name ->
    Hashtbl.find_opt enhanced_graph.function_map name
  ) (List.sort_uniq String.compare callers)

(** Get function metrics *)
let get_function_metrics enhanced_graph function_name =
  match Hashtbl.find_opt enhanced_graph.function_map function_name with
  | Some func ->
      let in_deg = in_degree enhanced_graph.graph func.name in
      let out_deg = out_degree enhanced_graph.graph func.name in
      let dependencies = get_dependencies enhanced_graph function_name in
      let reverse_deps = get_reverse_dependencies enhanced_graph function_name in
      let metrics = {
        in_degree = in_deg;
        out_degree = out_deg;
        dependency_count = List.length dependencies;
        reverse_dependency_count = List.length reverse_deps;
      } in
      (Some func, metrics)
  | None -> 
      let empty_metrics = {
        in_degree = 0; 
        out_degree = 0; 
        dependency_count = 0; 
        reverse_dependency_count = 0;
      } in
      (None, empty_metrics)