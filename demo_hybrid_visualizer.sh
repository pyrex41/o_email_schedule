#!/bin/bash

# 🔄 Hybrid Configuration System Visualizer Demo
# This script demonstrates the capabilities of the interactive visualization tool

set -e

echo "🔄 Hybrid Configuration System Visualizer Demo"
echo "============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}📋 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
print_step "Checking prerequisites..."

if ! command -v opam &> /dev/null; then
    print_error "opam is required but not installed. Please install OCaml and opam first."
    exit 1
fi

if ! command -v npm &> /dev/null; then
    print_error "npm is required but not installed. Please install Node.js first."
    exit 1
fi

if ! command -v python3 &> /dev/null; then
    print_error "python3 is required for the development server."
    exit 1
fi

print_success "All prerequisites are available"

# Set up opam environment
print_step "Setting up OCaml environment..."
eval $(opam env)
print_success "OCaml environment configured"

# Build the project
print_step "Building OCaml components..."
if dune build; then
    print_success "OCaml build completed"
else
    print_error "OCaml build failed"
    exit 1
fi

# Generate hybrid configuration visualization
print_step "Generating hybrid configuration visualization..."
echo "Analyzing lib/ directory for configuration-related functions..."

OUTPUT_DIR="demo_hybrid_output"
rm -rf "$OUTPUT_DIR"

if dune exec standalone_visualizer/visualizer_cli.exe -- --hybrid lib/ -o "$OUTPUT_DIR"; then
    print_success "Hybrid configuration data generated in $OUTPUT_DIR/"
else
    print_error "Failed to generate visualization data"
    exit 1
fi

# Install Elm if not available
if ! command -v elm &> /dev/null; then
    print_step "Installing Elm..."
    npm install -g elm
    print_success "Elm installed"
fi

# Compile Elm application
print_step "Compiling Elm application..."
cd "$OUTPUT_DIR"

if [ ! -f "elm.json" ]; then
    print_warning "elm.json not found. Creating minimal Elm project configuration..."
    # The hybrid visualizer should have created this, but let's ensure it exists
    cd ..
    print_error "Elm project not properly generated. Please check the hybrid visualizer output."
    exit 1
fi

if elm make src/Main.elm --output=elm.js; then
    print_success "Elm application compiled successfully"
else
    print_error "Elm compilation failed"
    exit 1
fi

cd ..

# Display what was generated
print_step "Generated files:"
echo "📁 $OUTPUT_DIR/"
echo "   ├── 📄 index.html (Main HTML file)"
echo "   ├── 📄 elm.js (Compiled Elm application)"
echo "   ├── 📄 elm.json (Elm project configuration)"
echo "   ├── 📁 src/ (Elm source files)"
echo "   │   ├── 📄 Main.elm"
echo "   │   └── 📁 HybridConfig/"
echo "   │       ├── 📄 Types.elm"
echo "   │       ├── 📄 DataFlow.elm"
echo "   │       └── 📄 MermaidDiagrams.elm"
echo "   └── 📁 JSON data files"
echo "       ├── 📄 hybrid_config_data.json"
echo "       ├── 📄 functions.json"
echo "       ├── 📄 dataflow.json"
echo "       └── 📄 constants.json"

# Show visualization features
echo ""
print_step "🌟 Visualization Features:"
echo "   🔄 Data Flow Architecture"
echo "      └── Shows configuration flow from Turso DB to email scheduling"
echo "   🌳 Decision Tree Process"
echo "      └── Interactive tree with expandable nodes and complexity scoring"
echo "   📞 Function Call Graph"
echo "      └── Integration with AST analyzer showing actual function relationships"
echo "   ⚙️  Configuration Flow"
echo "      └── Organization-specific config with size profile analysis"
echo ""
echo "   🏢 Organization Examples:"
echo "      ├── Small Agency (5k contacts): 20% daily cap, aggressive scheduling"
echo "      ├── Regional Company (50k contacts): 10% daily cap, balanced approach"
echo "      ├── State Network (250k contacts): 7% daily cap, conservative with overrides"
echo "      └── National Corp (1M+ contacts): 5% daily cap, enterprise-grade"

# Ask user if they want to start the server
echo ""
read -p "🚀 Would you like to start the development server now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Starting development server on port 8000..."
    print_success "Server starting! Visit http://localhost:8000 to explore the visualization"
    echo ""
    echo "🎯 Try these features:"
    echo "   • Click on any node to see detailed information"
    echo "   • Switch between different visualization views"
    echo "   • Expand decision tree nodes to see sub-processes"
    echo "   • Select different organization examples to see how config changes"
    echo "   • Use filters to focus on specific complexity levels"
    echo ""
    echo "📊 The visualization shows:"
    echo "   • How size profiles (Small/Medium/Large/Enterprise) affect load balancing"
    echo "   • Decision tree for the complete configuration process"
    echo "   • Data flow from central Turso DB to org-specific SQLite DBs"
    echo "   • Configuration overrides and their effects"
    echo "   • System constants and their explanations"
    echo ""
    echo "Press Ctrl+C to stop the server"
    echo ""
    
    cd "$OUTPUT_DIR" && python3 -m http.server 8000
else
    echo ""
    print_step "To start the server manually:"
    echo "   cd $OUTPUT_DIR"
    echo "   python3 -m http.server 8000"
    echo "   # Then visit http://localhost:8000"
    echo ""
    print_step "Using the Makefile (alternative):"
    echo "   make dev      # Clean build and serve"
    echo "   make serve    # Build and serve"
    echo "   make help     # Show all options"
fi

echo ""
print_success "Demo completed! 🎉"
echo ""
echo "📚 For more information, see HYBRID_VISUALIZER_README.md"
echo "🛠️  To extend the visualizer, explore the src/ directory in the output"
echo "🔧 To add new visualization types, modify the Elm modules"