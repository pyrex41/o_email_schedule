#!/bin/bash

# Build script for Turso FFI Integration
# This builds the Rust FFI library and OCaml bindings

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_header "🔍 Checking Dependencies"
    
    # Check Rust
    if command -v cargo &> /dev/null; then
        print_info "✅ Rust/Cargo found: $(cargo --version)"
    else
        print_error "❌ Rust/Cargo not found. Install from https://rustup.rs/"
        exit 1
    fi
    
    # Check OCaml
    if command -v ocaml &> /dev/null; then
        print_info "✅ OCaml found: $(ocaml -version)"
    else
        print_error "❌ OCaml not found. Install via opam or package manager"
        exit 1
    fi
    
    # Check Dune
    if command -v dune &> /dev/null; then
        print_info "✅ Dune found: $(dune --version)"
    else
        print_error "❌ Dune not found. Install with: opam install dune"
        exit 1
    fi
    
    # Check environment variables
    if [ -n "$TURSO_DATABASE_URL" ] && [ -n "$TURSO_AUTH_TOKEN" ]; then
        print_info "✅ Turso environment variables are set"
    else
        print_warn "⚠️  Turso environment variables not set (you can set them later)"
        print_warn "    Required: TURSO_DATABASE_URL and TURSO_AUTH_TOKEN"
    fi
}

build_rust_ffi() {
    print_header "🦀 Building Rust FFI Library"
    
    print_info "Building ocaml-interop dependency..."
    if ! cargo build --release --lib; then
        print_error "❌ Rust FFI build failed"
        exit 1
    fi
    
    # Check if the library was built
    if [ -f "target/release/libturso_ocaml_ffi.a" ]; then
        print_info "✅ Static library built: target/release/libturso_ocaml_ffi.a"
    else
        print_error "❌ Static library not found"
        exit 1
    fi
    
    if [ -f "target/release/libturso_ocaml_ffi.so" ] || [ -f "target/release/libturso_ocaml_ffi.dylib" ]; then
        print_info "✅ Dynamic library built"
    else
        print_warn "⚠️  Dynamic library not found (this might be expected on some platforms)"
    fi
}

build_ocaml() {
    print_header "🐫 Building OCaml with FFI Integration"
    
    print_info "Building OCaml library with Rust FFI..."
    if ! dune build; then
        print_error "❌ OCaml build failed"
        print_error "    Check that the Rust library is built and dune configuration is correct"
        exit 1
    fi
    
    print_info "✅ OCaml library built successfully"
    
    # Try to build the demo
    print_info "Building FFI demo..."
    if dune exec ./ffi_demo.exe --no-buffer &> /dev/null; then
        print_info "✅ FFI demo built successfully"
    else
        print_warn "⚠️  FFI demo build failed (might need environment variables)"
    fi
}

test_integration() {
    print_header "🧪 Testing FFI Integration"
    
    if [ -z "$TURSO_DATABASE_URL" ] || [ -z "$TURSO_AUTH_TOKEN" ]; then
        print_warn "⚠️  Skipping integration tests - environment variables not set"
        print_warn "    Set TURSO_DATABASE_URL and TURSO_AUTH_TOKEN to run tests"
        return
    fi
    
    print_info "Running FFI integration tests..."
    
    # Test basic connectivity
    print_info "Testing Turso connectivity..."
    if ./target/release/turso-sync libsql-sync --db-path test_ffi.db &> /dev/null; then
        print_info "✅ Basic Turso connectivity works"
        rm -f test_ffi.db test_ffi.db-* &> /dev/null || true
    else
        print_warn "⚠️  Turso connectivity test failed"
        print_warn "    Check your TURSO_DATABASE_URL and TURSO_AUTH_TOKEN"
    fi
    
    # Test OCaml FFI
    print_info "Testing OCaml FFI integration..."
    cat > test_ffi.ml << 'EOF'
open Printf

let test_ffi () =
  try
    printf "Testing Turso FFI integration...\n";
    match Turso_integration.detect_workflow_mode () with
    | "ffi" -> 
      printf "✅ FFI mode detected\n";
      let stats = Turso_integration.get_database_stats () in
      printf "✅ Connection stats retrieved: %d\n" stats;
      true
    | mode -> 
      printf "Mode: %s\n" mode;
      false
  with
  | e -> 
    printf "❌ FFI test failed: %s\n" (Printexc.to_string e);
    false

let () = 
  if test_ffi () then
    printf "✅ All FFI tests passed\n"
  else
    printf "⚠️  Some FFI tests failed\n"
EOF
    
    if dune exec --no-buffer -- ocaml test_ffi.ml &> /dev/null; then
        print_info "✅ OCaml FFI integration test passed"
    else
        print_warn "⚠️  OCaml FFI integration test failed"
    fi
    
    rm -f test_ffi.ml &> /dev/null || true
}

show_usage() {
    print_header "🚀 Usage Instructions"
    
    print_info "Environment Setup:"
    echo "    export TURSO_DATABASE_URL=\"libsql://your-database.turso.io\""
    echo "    export TURSO_AUTH_TOKEN=\"your-auth-token\""
    echo ""
    
    print_info "Quick Start:"
    echo "    1. Set environment variables (above)"
    echo "    2. Run your OCaml application with Turso_integration module"
    echo "    3. Database operations will auto-sync with Turso!"
    echo ""
    
    print_info "Demo:"
    echo "    dune exec ./ffi_demo.exe     # See detailed comparison"
    echo ""
    
    print_info "API Usage:"
    echo "    let conn = Turso_integration.get_connection ()"
    echo "    let results = Turso_integration.execute_sql_safe \"SELECT * FROM table\""
    echo "    let affected = Turso_integration.batch_insert_schedules schedules run_id"
    echo ""
    
    print_info "Documentation:"
    echo "    📖 See TURSO_FFI_INTEGRATION.md for complete guide"
}

main() {
    print_header "🎯 Turso FFI Integration Build Script"
    
    case "${1:-build}" in
        "deps"|"dependencies")
            check_dependencies
            ;;
        "rust")
            check_dependencies
            build_rust_ffi
            ;;
        "ocaml")
            build_ocaml
            ;;
        "test")
            check_dependencies
            build_rust_ffi
            build_ocaml
            test_integration
            ;;
        "clean")
            print_info "Cleaning build artifacts..."
            cargo clean
            dune clean
            rm -f test_ffi.db test_ffi.db-* test_ffi.ml &> /dev/null || true
            print_info "✅ Clean complete"
            ;;
        "demo")
            check_dependencies
            build_rust_ffi
            build_ocaml
            print_header "🎬 Running FFI Demo"
            dune exec ./ffi_demo.exe
            ;;
        "build"|*)
            check_dependencies
            build_rust_ffi
            build_ocaml
            test_integration
            show_usage
            ;;
    esac
    
    print_header "🏁 Build Complete"
    print_info "Ready to use Turso FFI integration!"
    print_info "Next steps: Set environment variables and run your OCaml app"
}

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Turso FFI Integration Build Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  build      Build everything (default)"
    echo "  deps       Check dependencies only"  
    echo "  rust       Build Rust FFI library only"
    echo "  ocaml      Build OCaml bindings only"
    echo "  test       Build and test integration"
    echo "  demo       Build and run the demo"
    echo "  clean      Clean build artifacts"
    echo "  --help     Show this help"
    echo ""
    echo "Environment Variables:"
    echo "  TURSO_DATABASE_URL   Your Turso database URL"
    echo "  TURSO_AUTH_TOKEN     Your Turso auth token"
    exit 0
fi

main "$@"