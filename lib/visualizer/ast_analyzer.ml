open Ppxlib

(** Type representing a function definition with metadata *)
type function_info = {
  name : string;
  location : Location.t;
  parameters : string list;
  doc_comment : string option;
  complexity_score : int;
  calls : string list;
  is_recursive : bool;
  module_path : string list;
}

(** Type representing the complete analysis result *)
type analysis_result = {
  functions : function_info list;
  call_graph : (string * string) list;
  modules : string list;
  errors : string list;
}

(** Extract documentation from attributes *)
let extract_doc_attribute attrs =
  let find_doc_attr attr =
    match attr.attr_name.txt with
    | "ocaml.doc" -> 
        (match attr.attr_payload with
         | PStr [{pstr_desc = Pstr_eval ({pexp_desc = Pexp_constant (Pconst_string (doc, _, _)); _}, _); _}] ->
             Some doc
         | _ -> None)
    | _ -> None
  in
  List.find_map find_doc_attr attrs

(** Simple complexity calculation *)
let calculate_complexity expr =
  let count_nodes = function
    | {pexp_desc = Pexp_match (_, cases); _} -> 1 + List.length cases
    | {pexp_desc = Pexp_ifthenelse (_, _, Some _); _} -> 2
    | {pexp_desc = Pexp_ifthenelse (_, _, None); _} -> 1
    | {pexp_desc = Pexp_apply (_, args); _} -> List.length args
    | _ -> 1
  in
  count_nodes expr

(** Extract function calls *)
let extract_calls expr =
  let calls = ref [] in
  let rec extract_from_expr = function
    | {pexp_desc = Pexp_ident {txt = Lident name; _}; _} ->
        calls := name :: !calls
    | {pexp_desc = Pexp_ident {txt = Ldot (_, name); _}; _} ->
        calls := name :: !calls
    | {pexp_desc = Pexp_apply (func, args); _} ->
        extract_from_expr func;
        List.iter (fun (_, arg) -> extract_from_expr arg) args
    | _ -> ()
  in
  extract_from_expr expr;
  List.rev !calls

(** Simple parameter extraction *)
let extract_parameters pattern =
  let extract acc pattern =
    match pattern.ppat_desc with
    | Ppat_var {txt; _} -> txt :: acc
    | _ -> acc
  in
  extract [] pattern

(** Process a value binding *)
let process_value_binding module_path binding =
  match binding.pvb_pat.ppat_desc with
  | Ppat_var {txt = name; _} ->
      let doc = extract_doc_attribute binding.pvb_attributes in
      let calls = extract_calls binding.pvb_expr in
      let complexity = calculate_complexity binding.pvb_expr in
      let parameters = 
        let rec extract_fun_params = function
          | {pexp_desc = Pexp_fun (_, _, pattern, body); _} ->
              extract_parameters pattern @ extract_fun_params body
          | _ -> []
        in
        extract_fun_params binding.pvb_expr
      in
      Some {
        name;
        location = binding.pvb_loc;
        parameters;
        doc_comment = doc;
        complexity_score = complexity;
        calls;
        is_recursive = false;
        module_path;
      }
  | _ -> None

(** Analyze a structure item *)
let analyze_structure_item module_path item =
  match item.pstr_desc with
  | Pstr_value (rec_flag, bindings) ->
      let functions = List.filter_map (process_value_binding module_path) bindings in
      let is_recursive = match rec_flag with Recursive -> true | Nonrecursive -> false in
      List.map (fun f -> {f with is_recursive}) functions
  | _ -> []

(** Main analysis function *)
let analyze_file filename =
  try
    let ic = open_in filename in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string content in
    let ast = Ppxlib.Parse.implementation lexbuf in
    let functions = List.concat_map (analyze_structure_item []) ast in
    let call_graph = 
      List.concat_map (fun f -> 
        List.map (fun callee -> (f.name, callee)) f.calls
      ) functions 
    in
    {functions; call_graph; modules = []; errors = []}
  with
  | exn -> 
      {functions = []; call_graph = []; modules = []; errors = [Printexc.to_string exn]}

(** Analyze multiple files *)
let analyze_files filenames =
  let results = List.map analyze_file filenames in
  let all_functions = List.concat_map (fun r -> r.functions) results in
  let all_call_graph = List.concat_map (fun r -> r.call_graph) results in
  let all_errors = List.concat_map (fun r -> r.errors) results in
  {functions = all_functions; call_graph = all_call_graph; modules = []; errors = all_errors}

(** Find functions that call a specific function *)
let find_callers target_function analysis =
  analysis.call_graph
  |> List.filter (fun (_, callee) -> callee = target_function)
  |> List.map fst
  |> List.sort_uniq String.compare

(** Find functions called by a specific function *)
let find_callees source_function analysis =
  analysis.call_graph
  |> List.filter (fun (caller, _) -> caller = source_function)
  |> List.map snd
  |> List.sort_uniq String.compare

(** Get function information by name *)
let get_function_info name analysis =
  List.find_opt (fun f -> f.name = name) analysis.functions