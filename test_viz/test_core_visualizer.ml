open Visualizer.Ast_analyzer
open Visualizer.Json_serializer

let () =
  Printf.printf "Testing OCaml Program Flow Visualizer Core Components\n";
  Printf.printf "====================================================\n\n";
  
  (* Test with the visualizer components themselves *)
  let test_files = ["../lib/visualizer/ast_analyzer.ml"; "../lib/visualizer/json_serializer.ml"] in
  
  Printf.printf "1. Testing AST analysis...\n";
  let analysis = analyze_files test_files in
  Printf.printf "   Found %d functions\n" (List.length analysis.functions);
  Printf.printf "   Found %d modules\n" (List.length analysis.modules);
  if List.length analysis.errors > 0 then
    Printf.printf "   Encountered %d errors\n" (List.length analysis.errors);
  
  Printf.printf "\n2. Testing visualization data generation...\n";
  let _ = generate_visualization_data analysis in
  Printf.printf "   Generated visualization data successfully\n";
  
  Printf.printf "\n3. Testing complete visualization export...\n";
  (* Create output directory *)
  if not (Sys.file_exists "test_viz_output") then
    Unix.mkdir "test_viz_output" 0o755;
  
  let result = export_complete_visualization test_files "test_viz_output" in
  Printf.printf "   Exported visualization with %d functions\n" (List.length result.functions);
  
  Printf.printf "\n✅ Core visualizer components working correctly!\n";
  Printf.printf "\nGenerated files:\n";
  let files = Sys.readdir "test_viz_output" in
  Array.iter (fun f -> Printf.printf "  - %s\n" f) files