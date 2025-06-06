#!/bin/bash

# OCaml Email Scheduler Performance Testing Suite
# This script runs comprehensive performance tests on various dataset sizes

set -e  # Exit on any error

echo "🚀 OCaml Email Scheduler Performance Testing Suite"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if opam environment is set up
check_opam() {
    if ! command -v opam &> /dev/null; then
        print_error "opam not found. Please install opam first."
        exit 1
    fi
    
    print_status "Setting up opam environment..."
    eval $(opam env)
}

# Build the project
build_project() {
    print_status "Building OCaml email scheduler..."
    
    if ! dune build; then
        print_error "Build failed. Please fix compilation errors first."
        exit 1
    fi
    
    print_success "Build completed successfully"
}

# Analyze golden dataset
analyze_golden_dataset() {
    print_status "Analyzing golden dataset patterns..."
    
    if [[ -f "golden_dataset.sqlite3" ]]; then
        dune exec bin/generate_test_data.exe -- analyze
        print_success "Golden dataset analysis completed"
    else
        print_warning "golden_dataset.sqlite3 not found, skipping analysis"
    fi
}

# Generate test datasets
generate_test_datasets() {
    print_status "Generating test datasets..."
    
    # Generate a 25k contact dataset to match golden dataset size
    print_status "Generating 25k contact test dataset..."
    if dune exec bin/generate_test_data.exe -- generate large_test_dataset.sqlite3 25000 1000; then
        print_success "Generated large_test_dataset.sqlite3 (25k contacts)"
    else
        print_error "Failed to generate large test dataset"
        return 1
    fi
    
    # Optionally generate a huge dataset for stress testing
    if [[ "$1" == "--include-huge" ]]; then
        print_status "Generating 100k contact stress test dataset..."
        if dune exec bin/generate_test_data.exe -- generate huge_test_dataset.sqlite3 100000 2000; then
            print_success "Generated huge_test_dataset.sqlite3 (100k contacts)"
        else
            print_warning "Failed to generate huge test dataset, continuing..."
        fi
    fi
}

# Run performance tests
run_performance_tests() {
    print_status "Running comprehensive performance tests..."
    
    # Create results directory
    mkdir -p performance_results
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local results_file="performance_results/test_results_$timestamp.txt"
    
    print_status "Results will be saved to: $results_file"
    
    {
        echo "OCaml Email Scheduler Performance Test Results"
        echo "=============================================="
        echo "Timestamp: $(date)"
        echo "System: $(uname -a)"
        echo ""
        
        # Run the performance test suite
        dune exec bin/performance_tests.exe -- suite
        
    } | tee "$results_file"
    
    print_success "Performance tests completed. Results saved to $results_file"
}

# Run scalability tests
run_scalability_tests() {
    print_status "Running scalability stress tests..."
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local scalability_file="performance_results/scalability_$timestamp.txt"
    
    {
        echo "OCaml Email Scheduler Scalability Test Results"
        echo "=============================================="
        echo "Timestamp: $(date)"
        echo ""
        
        # Test scalability with different databases
        for db in org-206.sqlite3 golden_dataset.sqlite3 large_test_dataset.sqlite3 massive_test_dataset.sqlite3; do
            if [[ -f "$db" ]]; then
                echo ""
                echo "=== Scalability Test: $db ==="
                dune exec bin/performance_tests.exe -- scalability "$db"
            fi
        done
        
    } | tee "$scalability_file"
    
    print_success "Scalability tests completed. Results saved to $scalability_file"
}

# Individual database tests
test_individual_databases() {
    print_status "Running individual database performance tests..."
    
    # Test org-206.sqlite3 (small dataset)
    if [[ -f "org-206.sqlite3" ]]; then
        print_status "Testing org-206.sqlite3..."
        dune exec bin/performance_tests.exe -- single org-206.sqlite3
    fi
    
    # Test golden dataset
    if [[ -f "golden_dataset.sqlite3" ]]; then
        print_status "Testing golden_dataset.sqlite3..."
        dune exec bin/performance_tests.exe -- single golden_dataset.sqlite3
    fi
    
    # Test generated large dataset
    if [[ -f "large_test_dataset.sqlite3" ]]; then
        print_status "Testing large_test_dataset.sqlite3..."
        dune exec bin/performance_tests.exe -- single large_test_dataset.sqlite3
    fi
    
    # Test massive dataset (500k contacts)
    if [[ -f "massive_test_dataset.sqlite3" ]]; then
        print_status "Testing massive_test_dataset.sqlite3 with parallel optimization..."
        print_status "(This provides detailed logging and optimized performance)"
        dune exec bin/performance_tests_parallel.exe -- massive massive_test_dataset.sqlite3
    fi
}

# Run memory profiling
run_memory_profiling() {
    print_status "Running memory profiling tests..."
    
    if command -v valgrind &> /dev/null; then
        print_status "Running Valgrind memory analysis..."
        
        if [[ -f "golden_dataset.sqlite3" ]]; then
            valgrind --tool=massif --pages-as-heap=yes \
                dune exec bin/performance_tests.exe -- single golden_dataset.sqlite3 \
                > performance_results/memory_profile_$(date +"%Y%m%d_%H%M%S").txt 2>&1
            print_success "Memory profiling completed"
        else
            print_warning "No suitable database for memory profiling"
        fi
    else
        print_warning "Valgrind not available, skipping memory profiling"
    fi
}

# Generate performance report
generate_report() {
    print_status "Generating performance test report..."
    
    local report_file="PERFORMANCE_REPORT.md"
    
    {
        echo "# OCaml Email Scheduler Performance Test Report"
        echo ""
        echo "**Generated:** $(date)"
        echo "**System:** $(uname -s) $(uname -r)"
        echo "**OCaml Version:** $(ocaml -version)"
        echo ""
        
        echo "## Test Databases"
        echo ""
        for db in org-206.sqlite3 golden_dataset.sqlite3 large_test_dataset.sqlite3; do
            if [[ -f "$db" ]]; then
                local size=$(ls -lh "$db" | awk '{print $5}')
                local contacts=$(sqlite3 "$db" "SELECT COUNT(*) FROM contacts;" 2>/dev/null || echo "N/A")
                echo "- **$db**: $size ($contacts contacts)"
            fi
        done
        
        echo ""
        echo "## Recent Test Results"
        echo ""
        echo "The most recent performance test results can be found in:"
        echo ""
        
        # List recent result files
        if [[ -d "performance_results" ]]; then
            ls -lt performance_results/*.txt | head -5 | while read line; do
                local file=$(echo "$line" | awk '{print $9}')
                local date=$(echo "$line" | awk '{print $6, $7, $8}')
                echo "- \`$file\` ($date)"
            done
        fi
        
        echo ""
        echo "## Performance Benchmarks"
        echo ""
        echo "Target performance metrics:"
        echo ""
        echo "- **Small Dataset (< 1k contacts)**: < 1 second total processing time"
        echo "- **Medium Dataset (1k-10k contacts)**: < 10 seconds total processing time"  
        echo "- **Large Dataset (10k+ contacts)**: < 60 seconds total processing time"
        echo "- **Memory Usage**: < 100MB for 25k contacts"
        echo "- **Throughput**: > 1000 contacts/second for scheduling"
        echo ""
        
        echo "## Next Steps"
        echo ""
        echo "1. Run \`./run_performance_tests.sh --full\` for comprehensive testing"
        echo "2. Check individual test results in \`performance_results/\` directory"
        echo "3. Compare results with previous runs to track performance trends"
        
    } > "$report_file"
    
    print_success "Performance report generated: $report_file"
}

# Main execution
main() {
    local run_full=false
    local include_huge=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --full)
                run_full=true
                shift
                ;;
            --include-huge)
                include_huge=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --full           Run comprehensive test suite"
                echo "  --include-huge   Generate and test 100k contact dataset"
                echo "  --help           Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                    # Run basic tests"
                echo "  $0 --full            # Run comprehensive tests" 
                echo "  $0 --include-huge    # Include stress testing"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_status "Starting performance testing suite..."
    
    # Core setup
    check_opam
    build_project
    
    # Create results directory
    mkdir -p performance_results
    
    if [[ "$run_full" == true ]]; then
        print_status "Running FULL performance test suite..."
        
        analyze_golden_dataset
        generate_test_datasets $([ "$include_huge" == true ] && echo "--include-huge")
        run_performance_tests
        run_scalability_tests
        test_individual_databases
        run_memory_profiling
        generate_report
        
    else
        print_status "Running BASIC performance tests..."
        
        # Just run tests on existing databases
        run_performance_tests
        generate_report
    fi
    
    print_success "Performance testing complete!"
    echo ""
    echo "📊 Results Summary:"
    echo "   • Test results: performance_results/"
    echo "   • Performance report: PERFORMANCE_REPORT.md"
    echo "   • Run with --full for comprehensive testing"
    echo ""
}

# Run main function with all arguments
main "$@" 