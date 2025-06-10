open Ppxlib

(** Type representing a function definition with metadata *)
type function_info = {
  name : string;
  location : Location.t;
  start_line : int;
  end_line : int;
  source_code : string;
  parameters : (string * string option) list; (* (name, type_annotation) *)
  doc_comment : string option;
  complexity_score : int;
  calls : string list;
  is_recursive : bool;
  module_path : string list;
  return_type : string option;
  file : string; (* Add file tracking *)
}

(** Type representing the complete analysis result *)
type analysis_result = {
  functions : function_info list;
  call_graph : (string * string) list;
  modules : string list;
  errors : string list;
}

(** Extract documentation from attributes and preceding comments *)
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

(** Extract source code from location and file content *)
let extract_source_code content location =
  let lines = String.split_on_char '\n' content in
  let start_line = location.loc_start.pos_lnum in
  let end_line = location.loc_end.pos_lnum in
  let start_char = location.loc_start.pos_cnum - location.loc_start.pos_bol in
  let end_char = location.loc_end.pos_cnum - location.loc_end.pos_bol in
  
  if start_line = end_line then
    (* Single line *)
    let line = List.nth lines (start_line - 1) in
    String.sub line start_char (end_char - start_char)
  else
    (* Multiple lines *)
    let selected_lines = 
      List.mapi (fun i line ->
        let line_num = i + 1 in
        if line_num < start_line || line_num > end_line then
          None
        else if line_num = start_line then
          Some (String.sub line start_char (String.length line - start_char))
        else if line_num = end_line then
          Some (String.sub line 0 end_char)
        else
          Some line
      ) lines
      |> List.filter_map (fun x -> x)
    in
    String.concat "\n" selected_lines

(** Calculate cyclomatic complexity *)
let calculate_complexity expr =
  let complexity = ref 1 in
  let rec traverse expr =
    match expr.pexp_desc with
    | Pexp_ifthenelse (cond, then_expr, else_opt) ->
        incr complexity;
        traverse cond;
        traverse then_expr;
        Option.iter traverse else_opt
    | Pexp_match (expr, cases) ->
        complexity := !complexity + List.length cases - 1;
        traverse expr;
        List.iter (fun case -> traverse case.pc_rhs) cases
    | Pexp_try (expr, cases) ->
        complexity := !complexity + List.length cases;
        traverse expr;
        List.iter (fun case -> traverse case.pc_rhs) cases
    | Pexp_while (cond, body) ->
        incr complexity;
        traverse cond;
        traverse body
    | Pexp_for (_, start, stop, _, body) ->
        incr complexity;
        traverse start;
        traverse stop;
        traverse body
    | Pexp_function cases ->
        complexity := !complexity + List.length cases - 1;
        List.iter (fun case -> traverse case.pc_rhs) cases
    | Pexp_let (_, bindings, expr) ->
        List.iter (fun vb -> traverse vb.pvb_expr) bindings;
        traverse expr
    | Pexp_sequence (e1, e2) ->
        traverse e1;
        traverse e2
    | Pexp_apply (func, args) ->
        traverse func;
        List.iter (fun (_, arg) -> traverse arg) args
    | _ -> ()
  in
  traverse expr;
  !complexity

(** Extract function calls *)
let extract_calls expr =
  let calls = ref [] in
  let rec extract_from_expr expr =
    match expr.pexp_desc with
    | Pexp_apply ({pexp_desc = Pexp_ident {txt = Lident name; _}; _}, args) ->
        (* This is a function application - filter out operators *)
        let is_operator = String.length name <= 2 && String.for_all (fun c -> 
          c = '+' || c = '-' || c = '*' || c = '/' || c = '=' || c = '<' || c = '>' || 
          c = '!' || c = '&' || c = '|' || c = '^' || c = '%' || c = '@'
        ) name in
        if not is_operator then
          calls := name :: !calls;
        List.iter (fun (_, arg) -> extract_from_expr arg) args
    | Pexp_apply ({pexp_desc = Pexp_ident {txt = Ldot (_, name); _}; _}, args) ->
        (* Module.function application *)
        calls := name :: !calls;
        List.iter (fun (_, arg) -> extract_from_expr arg) args
    | Pexp_apply (func, args) ->
        extract_from_expr func;
        List.iter (fun (_, arg) -> extract_from_expr arg) args
    | Pexp_let (_, bindings, expr) ->
        List.iter (fun vb -> extract_from_expr vb.pvb_expr) bindings;
        extract_from_expr expr
    | Pexp_match (expr, cases) ->
        extract_from_expr expr;
        List.iter (fun case -> extract_from_expr case.pc_rhs) cases
    | Pexp_ifthenelse (cond, then_expr, else_opt) ->
        extract_from_expr cond;
        extract_from_expr then_expr;
        Option.iter extract_from_expr else_opt
    | Pexp_sequence (e1, e2) ->
        extract_from_expr e1;
        extract_from_expr e2
    | Pexp_try (expr, cases) ->
        extract_from_expr expr;
        List.iter (fun case -> extract_from_expr case.pc_rhs) cases
    | _ -> ()
  in
  extract_from_expr expr;
  List.rev !calls |> List.sort_uniq String.compare

(** Enhanced parameter extraction with type information *)
let extract_parameters pattern =
  let rec extract_pattern_names pattern =
    match pattern.ppat_desc with
    | Ppat_var {txt; _} -> [(txt, None)]
    | Ppat_constraint (inner_pattern, core_type) ->
        let names = extract_pattern_names inner_pattern in
        List.map (fun (name, _) -> (name, Some (string_of_core_type core_type))) names
    | Ppat_tuple patterns ->
        List.concat_map extract_pattern_names patterns
    | Ppat_record (fields, _) ->
        List.concat_map (fun (_, pattern) -> extract_pattern_names pattern) fields
    | _ -> []
  and string_of_core_type core_type =
    (* Simple type to string conversion - can be enhanced *)
    match core_type.ptyp_desc with
    | Ptyp_constr ({txt = Lident name; _}, []) -> name
    | Ptyp_constr ({txt = Ldot (_, name); _}, []) -> name
    | Ptyp_arrow (_, _, _) -> "function"
    | _ -> "unknown"
  in
  extract_pattern_names pattern

(** Process a value binding *)
let process_value_binding filename content module_path binding =
  match binding.pvb_pat.ppat_desc with
  | Ppat_var {txt = name; _} ->
      let doc = extract_doc_attribute binding.pvb_attributes in
      (* Extract the actual function body for analysis *)
      let rec get_function_body expr =
        match expr.pexp_desc with
        | Pexp_fun (_, _, _, body) -> get_function_body body
        | _ -> expr
      in
      let body_expr = get_function_body binding.pvb_expr in
      let calls = extract_calls body_expr in
      let complexity = calculate_complexity body_expr in
      let source_code = extract_source_code content binding.pvb_loc in
      let start_line = binding.pvb_loc.loc_start.pos_lnum in
      let end_line = binding.pvb_loc.loc_end.pos_lnum in
      let parameters = 
        let rec extract_fun_params = function
          | {pexp_desc = Pexp_fun (_, _, pattern, body); _} ->
              extract_parameters pattern @ extract_fun_params body
          | _ -> []
        in
        extract_fun_params binding.pvb_expr
      in
      let return_type = 
        let string_of_core_type core_type =
          match core_type.ptyp_desc with
          | Ptyp_constr ({txt = Lident name; _}, []) -> name
          | Ptyp_constr ({txt = Ldot (_, name); _}, []) -> name
          | Ptyp_arrow (_, _, return_type) -> string_of_core_type return_type
          | _ -> "unknown"
        in
        match binding.pvb_expr.pexp_desc with
        | Pexp_constraint (_, core_type) -> Some (string_of_core_type core_type)
        | _ -> None
      in
      Some {
        name;
        location = binding.pvb_loc;
        start_line;
        end_line;
        source_code;
        parameters;
        doc_comment = doc;
        complexity_score = complexity;
        calls;
        is_recursive = false;
        module_path;
        return_type;
        file = filename;
      }
  | _ -> None

(** Analyze a structure item *)
let rec analyze_structure_item filename content module_path item =
  match item.pstr_desc with
  | Pstr_value (rec_flag, bindings) ->
      let functions = List.filter_map (process_value_binding filename content module_path) bindings in
      let is_recursive = match rec_flag with Recursive -> true | Nonrecursive -> false in
      List.map (fun f -> {f with is_recursive}) functions
  | Pstr_module {pmb_name = {txt; _}; pmb_expr; _} ->
      (* Handle module definitions *)
      let module_name = Option.value txt ~default:"_" in
      let new_module_path = module_path @ [module_name] in
      analyze_module_expr filename content new_module_path pmb_expr
  | _ -> []

and analyze_module_expr filename content module_path mexpr =
  match mexpr.pmod_desc with
  | Pmod_structure structure ->
      List.concat_map (analyze_structure_item filename content module_path) structure
  | _ -> []

(** Main analysis function *)
let analyze_file filename =
  try
    let ic = open_in filename in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;
    let lexbuf = Lexing.from_string content in
    let ast = Ppxlib.Parse.implementation lexbuf in
    let functions = List.concat_map (analyze_structure_item filename content []) ast in
    let call_graph = 
      List.concat_map (fun f -> 
        List.map (fun callee -> (f.name, callee)) f.calls
      ) functions 
    in
    let modules = [Filename.basename filename] in
    {functions; call_graph; modules; errors = []}
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