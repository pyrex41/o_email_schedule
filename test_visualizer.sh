#!/bin/bash

# Test script for the OCaml Program Flow Visualizer
# This script builds the visualizer and demonstrates its functionality

set -e  # Exit on any error

echo "🔗 OCaml Program Flow Visualizer - Test Script"
echo "=============================================="

# Ensure we have the right opam environment
echo "Setting up OCaml environment..."
eval $(opam env)

# Install dependencies if needed
echo "Installing dependencies..."
opam install -y dune ppxlib odoc-parser ocamlgraph yojson re fmt cmdliner 2>/dev/null || echo "Dependencies already installed"

# Build the project
echo "Building the project..."
dune build

# Test if the visualizer executable was built
if [ ! -f "_build/install/default/bin/ocaml-visualizer" ]; then
    echo "❌ Error: ocaml-visualizer executable not found"
    echo "Build may have failed. Checking build status..."
    dune build --verbose
    exit 1
fi

echo "✅ Build successful!"

# Create a test directory structure
echo "Setting up test environment..."
mkdir -p test_output

# Run the visualizer on the lib directory
echo "Running OCaml Program Flow Visualizer on lib/ directory..."
echo "Command: ./_build/install/default/bin/ocaml-visualizer --verbose --output test_output lib/"

./_build/install/default/bin/ocaml-visualizer --verbose --output test_output lib/

# Check if output files were generated
echo "Checking generated files..."
if [ -f "test_output/visualization.json" ]; then
    echo "✅ visualization.json generated"
    echo "📊 File size: $(du -h test_output/visualization.json | cut -f1)"
else
    echo "❌ visualization.json not found"
    exit 1
fi

if [ -f "test_output/source_data.json" ]; then
    echo "✅ source_data.json generated"
    echo "📊 File size: $(du -h test_output/source_data.json | cut -f1)"
else
    echo "❌ source_data.json not found"
    exit 1
fi

if [ -f "test_output/index.html" ]; then
    echo "✅ index.html generated"
else
    echo "❌ index.html not found"
    exit 1
fi

if [ -f "test_output/visualizer.js" ]; then
    echo "✅ visualizer.js generated"
else
    echo "❌ visualizer.js not found"
    exit 1
fi

# Show a preview of the analysis
echo ""
echo "📋 Analysis Preview:"
echo "==================="

if command -v jq >/dev/null 2>&1; then
    # Use jq for pretty printing if available
    echo "Functions found:"
    jq -r '.analysis.functions[] | "\(.name) (complexity: \(.complexity_score))"' test_output/visualization.json | head -10
    
    echo ""
    echo "Metadata:"
    jq '.metadata' test_output/visualization.json
else
    # Fallback to basic grep if jq is not available
    echo "Functions found (first 10):"
    grep -o '"name":"[^"]*"' test_output/visualization.json | head -10 | sed 's/"name":"//g' | sed 's/"//g'
    
    echo ""
    echo "Total functions: $(grep -o '"name":"[^"]*"' test_output/visualization.json | wc -l)"
fi

echo ""
echo "🎉 Test completed successfully!"
echo ""
echo "📁 Generated files in test_output/:"
ls -la test_output/

echo ""
echo "🌐 To view the interactive visualization:"
echo "   cd test_output && python3 -m http.server 8000"
echo "   Then open http://localhost:8000 in your browser"
echo ""
echo "🔧 Alternative usage examples:"
echo "   # Analyze with complexity filter:"
echo "   ./_build/install/default/bin/ocaml-visualizer --max-complexity 10 lib/"
echo ""
echo "   # Start web server immediately:"
echo "   ./_build/install/default/bin/ocaml-visualizer --serve --port 9000 lib/"
echo ""
echo "   # Get detailed help:"
echo "   ./_build/install/default/bin/ocaml-visualizer help"

# Test the help system
echo ""
echo "📖 Testing help system..."
./_build/install/default/bin/ocaml-visualizer help | head -20

echo ""
echo "✨ All tests passed! The OCaml Program Flow Visualizer is ready to use."

echo "=== Testing OCaml Visualizer ==="

# Test basic help
echo ""
echo "=== Testing help command ==="
dune exec ocaml-visualizer -- --help

# Test analysis of core libraries
echo ""
echo "=== Generating full project visualization ==="
dune exec ocaml-visualizer -- --verbose --output test_viz lib/

# Test focused analysis
echo ""
echo "=== Generating focused scheduling visualization ==="
dune exec ocaml-visualizer -- --verbose --max-complexity 5 --output scheduling_viz lib/scheduling/ lib/domain/

# Test single file analysis  
echo ""
echo "=== Analyzing single file ==="
dune exec ocaml-visualizer -- --verbose --output single_viz lib/scheduler.ml

echo ""
echo "=== Visualizer Test Results ==="
echo "✅ Full project visualization: test_viz/"
echo "✅ Focused scheduling visualization: scheduling_viz/"  
echo "✅ Single file visualization: single_viz/"
echo ""
echo "To view any visualization:"
echo "  cd test_viz && python3 -m http.server 8000"
echo "  Then open http://localhost:8000"
echo ""
echo "=== Original performance tests below ==="
echo ""