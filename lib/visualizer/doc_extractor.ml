open Ast_analyzer

(** Type representing parsed documentation *)
type parsed_doc = {
  summary : string option;
  description : string option;
  parameters : (string * string) list; (* (param_name, description) *)
  returns : string option;
  examples : string list;
  see_also : string list;
  since : string option;
  deprecated : string option;
  raises : (string * string) list; (* (exception, description) *)
  tags : (string * string) list; (* Custom tags *)
}

(** Empty documentation *)
let empty_doc = {
  summary = None;
  description = None;
  parameters = [];
  returns = None;
  examples = [];
  see_also = [];
  since = None;
  deprecated = None;
  raises = [];
  tags = [];
}

(** Simple documentation comment parser *)
let parse_simple_doc_comment comment_text =
  let lines = String.split_on_char '\n' comment_text in
  let first_line = match lines with
    | [] -> ""
    | hd :: _ -> String.trim hd
  in
  let summary = if String.length first_line > 0 then Some first_line else None in
  let description = if List.length lines > 1 then Some (String.concat "\n" (List.tl lines)) else None in
  {
    summary;
    description;
    parameters = [];
    returns = None;
    examples = [];
    see_also = [];
    since = None;
    deprecated = None;
    raises = [];
    tags = [];
  }

(** Parse a single documentation comment *)
let parse_doc_comment comment_text =
  try
    Some (parse_simple_doc_comment comment_text)
  with
  | _ -> None

(** Extract documentation for a function *)
let extract_function_doc func =
  match func.doc_comment with
  | Some comment -> parse_doc_comment comment
  | None -> Some empty_doc

(** Extract all documentation from analysis result *)
let extract_all_docs analysis =
  List.fold_left (fun acc func ->
    match extract_function_doc func with
    | Some doc -> (func.name, doc) :: acc
    | None -> (func.name, empty_doc) :: acc
  ) [] analysis.functions

(** HTML escape utility *)
module Html = struct
  let escape s =
    let buffer = Buffer.create (String.length s * 2) in
    String.iter (function
      | '<' -> Buffer.add_string buffer "&lt;"
      | '>' -> Buffer.add_string buffer "&gt;"
      | '&' -> Buffer.add_string buffer "&amp;"
      | '"' -> Buffer.add_string buffer "&quot;"
      | '\'' -> Buffer.add_string buffer "&#x27;"
      | c -> Buffer.add_char buffer c
    ) s;
    Buffer.contents buffer
end

(** Format documentation as HTML *)
let format_doc_as_html doc =
  let buffer = Buffer.create 1024 in
  
  (* Summary *)
  (match doc.summary with
   | Some summary -> 
       Buffer.add_string buffer "<div class=\"doc-summary\">";
       Buffer.add_string buffer (Html.escape summary);
       Buffer.add_string buffer "</div>\n"
   | None -> ());
  
  (* Description *)
  (match doc.description with
   | Some desc -> 
       Buffer.add_string buffer "<div class=\"doc-description\">";
       Buffer.add_string buffer (Html.escape desc);
       Buffer.add_string buffer "</div>\n"
   | None -> ());
  
  (* Parameters *)
  if List.length doc.parameters > 0 then begin
    Buffer.add_string buffer "<div class=\"doc-parameters\">\n";
    Buffer.add_string buffer "<h4>Parameters:</h4>\n<ul>\n";
    List.iter (fun (param, desc) ->
      Buffer.add_string buffer "<li><code>";
      Buffer.add_string buffer (Html.escape param);
      Buffer.add_string buffer "</code> - ";
      Buffer.add_string buffer (Html.escape desc);
      Buffer.add_string buffer "</li>\n"
    ) doc.parameters;
    Buffer.add_string buffer "</ul>\n</div>\n"
  end;
  
  (* Returns *)
  (match doc.returns with
   | Some ret -> 
       Buffer.add_string buffer "<div class=\"doc-returns\">\n";
       Buffer.add_string buffer "<h4>Returns:</h4>\n<p>";
       Buffer.add_string buffer (Html.escape ret);
       Buffer.add_string buffer "</p>\n</div>\n"
   | None -> ());
  
  (* Examples *)
  if List.length doc.examples > 0 then begin
    Buffer.add_string buffer "<div class=\"doc-examples\">\n";
    Buffer.add_string buffer "<h4>Examples:</h4>\n";
    List.iter (fun example ->
      Buffer.add_string buffer "<pre><code>";
      Buffer.add_string buffer (Html.escape example);
      Buffer.add_string buffer "</code></pre>\n"
    ) doc.examples
  end;
  
  (* Raises *)
  if List.length doc.raises > 0 then begin
    Buffer.add_string buffer "<div class=\"doc-raises\">\n";
    Buffer.add_string buffer "<h4>Raises:</h4>\n<ul>\n";
    List.iter (fun (exc, desc) ->
      Buffer.add_string buffer "<li><code>";
      Buffer.add_string buffer (Html.escape exc);
      Buffer.add_string buffer "</code> - ";
      Buffer.add_string buffer (Html.escape desc);
      Buffer.add_string buffer "</li>\n"
    ) doc.raises;
    Buffer.add_string buffer "</ul>\n</div>\n"
  end;
  
  (* Since/Deprecated *)
  (match doc.since with
   | Some since -> 
       Buffer.add_string buffer "<div class=\"doc-since\">Since: ";
       Buffer.add_string buffer (Html.escape since);
       Buffer.add_string buffer "</div>\n"
   | None -> ());
  
  (match doc.deprecated with
   | Some deprecated -> 
       Buffer.add_string buffer "<div class=\"doc-deprecated\">⚠️ Deprecated: ";
       Buffer.add_string buffer (Html.escape deprecated);
       Buffer.add_string buffer "</div>\n"
   | None -> ());
  
  Buffer.contents buffer

(** Convert documentation to markdown *)
let format_doc_as_markdown doc =
  let buffer = Buffer.create 1024 in
  
  (* Summary *)
  (match doc.summary with
   | Some summary -> 
       Buffer.add_string buffer summary;
       Buffer.add_string buffer "\n\n"
   | None -> ());
  
  (* Description *)
  (match doc.description with
   | Some desc -> 
       Buffer.add_string buffer desc;
       Buffer.add_string buffer "\n\n"
   | None -> ());
  
  (* Parameters *)
  if List.length doc.parameters > 0 then begin
    Buffer.add_string buffer "## Parameters\n\n";
    List.iter (fun (param, desc) ->
      Buffer.add_string buffer "- `";
      Buffer.add_string buffer param;
      Buffer.add_string buffer "` - ";
      Buffer.add_string buffer desc;
      Buffer.add_string buffer "\n"
    ) doc.parameters;
    Buffer.add_string buffer "\n"
  end;
  
  (* Returns *)
  (match doc.returns with
   | Some ret -> 
       Buffer.add_string buffer "## Returns\n\n";
       Buffer.add_string buffer ret;
       Buffer.add_string buffer "\n\n"
   | None -> ());
  
  (* Examples *)
  if List.length doc.examples > 0 then begin
    Buffer.add_string buffer "## Examples\n\n";
    List.iter (fun example ->
      Buffer.add_string buffer "```ocaml\n";
      Buffer.add_string buffer example;
      Buffer.add_string buffer "\n```\n\n"
    ) doc.examples
  end;
  
  Buffer.contents buffer