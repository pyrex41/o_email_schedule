# Hybrid Configuration System Visualizer Makefile

.PHONY: build elm-compile hybrid-vis clean install-deps serve help

# Default target
all: build

# Build the OCaml components
build:
	@echo "🔧 Building OCaml components..."
	eval $$(opam env) && dune build

# Install Elm dependencies and compile the Elm application
elm-compile:
	@echo "🌳 Installing Elm and compiling Elm application..."
	@if ! command -v elm >/dev/null 2>&1; then \
		echo "Installing Elm..."; \
		npm install -g elm; \
	fi
	@if [ -f elm.json ]; then \
		elm make src/Main.elm --output=elm.js; \
	else \
		echo "❌ elm.json not found. Run 'make hybrid-vis' first to generate the Elm project."; \
	fi

# Generate hybrid configuration visualization
hybrid-vis: build
	@echo "🔄 Generating hybrid configuration visualization..."
	eval $$(opam env) && dune exec standalone_visualizer/visualizer_cli.exe -- --hybrid lib/ -o hybrid_visualizer_output

# Generate and compile in one step
hybrid-complete: hybrid-vis elm-compile

# Install dependencies
install-deps:
	@echo "📦 Installing dependencies..."
	@echo "Installing OCaml dependencies..."
	opam install . --deps-only
	@echo "Installing Node.js dependencies..."
	@if ! command -v npm >/dev/null 2>&1; then \
		echo "❌ npm is required but not installed. Please install Node.js first."; \
		exit 1; \
	fi
	npm install -g elm

# Serve the visualization
serve: hybrid-complete
	@echo "🚀 Starting development server..."
	@cd hybrid_visualizer_output && python3 -m http.server 8000

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	dune clean
	rm -rf hybrid_visualizer_output
	rm -f elm.js

# Quick development workflow
dev: clean hybrid-complete serve

# Test the visualizer with current lib files
test-lib:
	@echo "🧪 Testing visualizer with lib/ directory..."
	eval $$(opam env) && dune exec standalone_visualizer/visualizer_cli.exe -- --hybrid --serve lib/

# Help target
help:
	@echo "🔄 Hybrid Configuration System Visualizer"
	@echo ""
	@echo "Available targets:"
	@echo "  build           - Build OCaml components"
	@echo "  elm-compile     - Compile Elm application"
	@echo "  hybrid-vis      - Generate hybrid config visualization data"
	@echo "  hybrid-complete - Generate and compile everything"
	@echo "  install-deps    - Install all dependencies"
	@echo "  serve           - Build and serve the visualization"
	@echo "  clean           - Clean build artifacts"
	@echo "  dev             - Full clean + build + serve workflow"
	@echo "  test-lib        - Test with lib/ directory and auto-serve"
	@echo "  help            - Show this help message"
	@echo ""
	@echo "Quick start:"
	@echo "  make install-deps  # Install dependencies"
	@echo "  make dev           # Build and serve the visualization"
	@echo ""
	@echo "Then visit http://localhost:8000 to explore the hybrid configuration system!"

# CI/CD target for automated builds
ci: install-deps build hybrid-vis
	@echo "✅ CI build completed successfully"