#!/bin/bash

# Master Testing Framework for Email Scheduler
# Unified interface for all testing modes: comprehensive, simulation, performance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}🎯 Master Email Scheduler Testing Framework${NC}"
echo "=============================================="

# Configuration
SELECTED_TESTS=()
PARALLEL_EXECUTION=false
RESULTS_DIR="master_test_results_$(date +%Y%m%d_%H%M%S)"
CLEANUP_AFTER=false
VERBOSE=false

# Function to show help
show_help() {
    cat << EOF
Email Scheduler Master Testing Framework

Usage: $0 [OPTIONS] [TESTS...]

AVAILABLE TESTS:
  comprehensive    Full comprehensive testing suite (scenarios + validation)
  simulation       Daily scheduling simulation with time-based progression
  performance      Massive performance test with 750,000 contacts
  quick           Quick comprehensive test (birthday + campaign only)
  all             Run all test types

OPTIONS:
  --parallel           Run tests in parallel (where possible)
  --cleanup           Clean up test files after completion
  --verbose           Enable verbose output
  --results-dir DIR   Custom results directory
  --help              Show this help

EXAMPLES:
  $0 comprehensive                    # Run comprehensive testing
  $0 simulation --contacts 500        # Run simulation with 500 contacts
  $0 performance --contacts 1000000   # Run 1M contact performance test
  $0 comprehensive simulation         # Run both comprehensive and simulation
  $0 all --parallel --cleanup         # Run everything in parallel with cleanup
  $0 quick simulation                 # Quick test + simulation

INDIVIDUAL TEST OPTIONS:
  Comprehensive Testing:
    --quick                Run quick mode only
    --detailed            Enable detailed logging
    --performance-only    Performance tests only

  Daily Simulation:
    --contacts N          Number of contacts (default: 1000)
    --start-date DATE     Start simulation date
    --end-date DATE       End simulation date
    --outage-rate PROB    Random outage probability

  Massive Performance:
    --contacts N          Number of contacts (default: 750000)
    --batch-size N        Batch size for generation
    --no-memory-monitoring Disable memory monitoring

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help)
            show_help
            exit 0
            ;;
        --parallel)
            PARALLEL_EXECUTION=true
            shift
            ;;
        --cleanup)
            CLEANUP_AFTER=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --results-dir)
            RESULTS_DIR="$2"
            shift 2
            ;;
        comprehensive|simulation|performance|quick|all)
            SELECTED_TESTS+=("$1")
            shift
            ;;
        *)
            # Pass through other arguments to individual test scripts
            break
            ;;
    esac
done

# If no tests specified, show help
if [ ${#SELECTED_TESTS[@]} -eq 0 ]; then
    echo -e "${YELLOW}No tests specified. Use --help to see available options.${NC}"
    show_help
    exit 1
fi

# Create results directory
mkdir -p "$RESULTS_DIR"

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "$message"
    echo "[$timestamp] [$level] $message" >> "$RESULTS_DIR/master_test.log"
}

# Function to run individual test with error handling
run_test() {
    local test_name="$1"
    local test_command="$2"
    local test_args="$3"
    local test_dir="$RESULTS_DIR/${test_name}_$(date +%H%M%S)"
    
    log "INFO" "${CYAN}🚀 Starting $test_name...${NC}"
    
    local start_time=$(date +%s)
    local success=true
    
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Capture both stdout and stderr
    if [ "$VERBOSE" = true ]; then
        if ! eval "$test_command $test_args" 2>&1 | tee "$test_dir/output.log"; then
            success=false
        fi
    else
        if ! eval "$test_command $test_args" > "$test_dir/output.log" 2>&1; then
            success=false
        fi
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    cd - > /dev/null
    
    # Record test results
    if [ "$success" = true ]; then
        log "INFO" "${GREEN}✅ $test_name completed successfully in ${duration}s${NC}"
        echo "$test_name|SUCCESS|$duration|$test_dir" >> "$RESULTS_DIR/test_results.txt"
        return 0
    else
        log "ERROR" "${RED}❌ $test_name failed after ${duration}s${NC}"
        echo "$test_name|FAILED|$duration|$test_dir" >> "$RESULTS_DIR/test_results.txt"
        return 1
    fi
}

# Function to run tests in parallel
run_tests_parallel() {
    local test_configs=("$@")
    local pids=()
    
    log "INFO" "${CYAN}🔄 Running tests in parallel...${NC}"
    
    for config in "${test_configs[@]}"; do
        IFS='|' read -r test_name test_command test_args <<< "$config"
        (run_test "$test_name" "$test_command" "$test_args") &
        pids+=($!)
        log "INFO" "  Started $test_name (PID: $!)"
    done
    
    # Wait for all tests to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    if [ "$all_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to run tests sequentially
run_tests_sequential() {
    local test_configs=("$@")
    local all_success=true
    
    log "INFO" "${CYAN}🔄 Running tests sequentially...${NC}"
    
    for config in "${test_configs[@]}"; do
        IFS='|' read -r test_name test_command test_args <<< "$config"
        if ! run_test "$test_name" "$test_command" "$test_args"; then
            all_success=false
        fi
    done
    
    if [ "$all_success" = true ]; then
        return 0
    else
        return 1
    fi
}

# Function to prepare test configurations
prepare_test_configs() {
    local configs=()
    local remaining_args="$*"
    
    for test in "${SELECTED_TESTS[@]}"; do
        case $test in
            comprehensive)
                configs+=("Comprehensive_Testing|./run_comprehensive_tests.sh|$remaining_args")
                ;;
            simulation)
                configs+=("Daily_Simulation|./simulate_daily_scheduling.sh|$remaining_args")
                ;;
            performance)
                configs+=("Massive_Performance|./generate_massive_performance_test.sh|$remaining_args")
                ;;
            quick)
                configs+=("Quick_Testing|./run_comprehensive_tests.sh|--quick $remaining_args")
                ;;
            all)
                configs+=("Comprehensive_Testing|./run_comprehensive_tests.sh|$remaining_args")
                configs+=("Daily_Simulation|./simulate_daily_scheduling.sh|--contacts 500 $remaining_args")
                configs+=("Massive_Performance|./generate_massive_performance_test.sh|$remaining_args")
                ;;
        esac
    done
    
    printf '%s\n' "${configs[@]}"
}

# Function to generate master report
generate_master_report() {
    log "INFO" "${CYAN}📋 Generating master test report...${NC}"
    
    local report_file="$RESULTS_DIR/MASTER_TEST_REPORT.md"
    
    cat > "$report_file" << EOF
# Master Email Scheduler Test Report

**Generated:** $(date)  
**Test Suite:** Master Testing Framework  
**Tests Executed:** ${SELECTED_TESTS[*]}  
**Parallel Execution:** $PARALLEL_EXECUTION  
**Results Directory:** $RESULTS_DIR  

## Executive Summary

$(if [ -f "$RESULTS_DIR/test_results.txt" ]; then
    local total_tests=$(wc -l < "$RESULTS_DIR/test_results.txt")
    local successful_tests=$(grep -c "SUCCESS" "$RESULTS_DIR/test_results.txt")
    local failed_tests=$(grep -c "FAILED" "$RESULTS_DIR/test_results.txt" || echo "0")
    local total_duration=$(awk -F'|' '{sum += $3} END {print sum}' "$RESULTS_DIR/test_results.txt")
    
    echo "- **Total Tests:** $total_tests"
    echo "- **Successful:** $successful_tests"
    echo "- **Failed:** $failed_tests"
    echo "- **Total Duration:** ${total_duration}s"
    echo "- **Success Rate:** $(echo "scale=1; 100 * $successful_tests / $total_tests" | bc -l)%"
else
    echo "No test results available"
fi)

## Test Results Summary

$(if [ -f "$RESULTS_DIR/test_results.txt" ]; then
    echo "| Test Name | Status | Duration | Details |"
    echo "|-----------|--------|----------|---------|"
    while IFS='|' read -r test_name status duration test_dir; do
        local status_icon
        if [ "$status" = "SUCCESS" ]; then
            status_icon="✅"
        else
            status_icon="❌"
        fi
        echo "| $test_name | $status_icon $status | ${duration}s | [View Details]($test_dir) |"
    done < "$RESULTS_DIR/test_results.txt"
else
    echo "No detailed results available"
fi)

## Individual Test Reports

$(if [ -f "$RESULTS_DIR/test_results.txt" ]; then
    while IFS='|' read -r test_name status duration test_dir; do
        echo "### $test_name"
        echo ""
        echo "- **Status:** $status"
        echo "- **Duration:** ${duration}s"
        echo "- **Output Directory:** \`$test_dir\`"
        echo ""
        
        # Try to find and link to specific reports
        for report in "$test_dir"/*.md; do
            if [ -f "$report" ]; then
                local report_name=$(basename "$report")
                echo "- **Detailed Report:** [$report_name]($report)"
            fi
        done
        
        # Show any database files created
        for db in "$test_dir"/*.db; do
            if [ -f "$db" ]; then
                local db_name=$(basename "$db")
                local db_size=$(stat -c%s "$db" 2>/dev/null || stat -f%z "$db" 2>/dev/null || echo "0")
                local db_size_mb=$((db_size / 1024 / 1024))
                echo "- **Database:** \`$db_name\` (${db_size_mb}MB)"
            fi
        done
        
        echo ""
    done < "$RESULTS_DIR/test_results.txt"
else
    echo "No individual test details available"
fi)

## Performance Summary

$(if grep -q "Massive_Performance.*SUCCESS" "$RESULTS_DIR/test_results.txt" 2>/dev/null; then
    echo "### Massive Performance Test Results"
    echo ""
    local perf_dir=$(grep "Massive_Performance.*SUCCESS" "$RESULTS_DIR/test_results.txt" | cut -d'|' -f4)
    if [ -f "$perf_dir/MASSIVE_PERFORMANCE_REPORT.md" ]; then
        echo "Massive performance testing completed successfully."
        echo "See detailed analysis in: [\`MASSIVE_PERFORMANCE_REPORT.md\`]($perf_dir/MASSIVE_PERFORMANCE_REPORT.md)"
    fi
    echo ""
fi)

$(if grep -q "Daily_Simulation.*SUCCESS" "$RESULTS_DIR/test_results.txt" 2>/dev/null; then
    echo "### Daily Simulation Results"
    echo ""
    local sim_dir=$(grep "Daily_Simulation.*SUCCESS" "$RESULTS_DIR/test_results.txt" | cut -d'|' -f4)
    if [ -f "$sim_dir/SIMULATION_REPORT.md" ]; then
        echo "Daily simulation completed successfully."
        echo "See detailed analysis in: [\`SIMULATION_REPORT.md\`]($sim_dir/SIMULATION_REPORT.md)"
    fi
    echo ""
fi)

$(if grep -q "Comprehensive_Testing.*SUCCESS" "$RESULTS_DIR/test_results.txt" 2>/dev/null; then
    echo "### Comprehensive Testing Results"
    echo ""
    local comp_dir=$(grep "Comprehensive_Testing.*SUCCESS" "$RESULTS_DIR/test_results.txt" | cut -d'|' -f4)
    if [ -f "$comp_dir"/test_results_*/COMPREHENSIVE_TEST_REPORT.md ]; then
        echo "Comprehensive testing completed successfully."
        echo "See detailed analysis in the comprehensive test report."
    fi
    echo ""
fi)

## Recommendations

Based on the test results:

### Production Readiness
$(if [ -f "$RESULTS_DIR/test_results.txt" ]; then
    local failed_count=$(grep -c "FAILED" "$RESULTS_DIR/test_results.txt" || echo "0")
    if [ "$failed_count" -eq 0 ]; then
        echo "- ✅ **All tests passed** - System is ready for production deployment"
        echo "- ✅ **Email scheduler validated** across all test scenarios"
        echo "- ✅ **Performance characteristics** established and documented"
    else
        echo "- ⚠️  **$failed_count test(s) failed** - Review failed tests before production"
        echo "- 🔍 **Investigation required** for failed test scenarios"
    fi
else
    echo "- ❓ **Incomplete testing** - No test results available for analysis"
fi)

### Next Steps
1. **Review Individual Reports:** Examine detailed reports for each test type
2. **Address Any Failures:** Investigate and resolve any failed test scenarios  
3. **Performance Monitoring:** Set up production monitoring based on test benchmarks
4. **Automated Testing:** Integrate successful test configurations into CI/CD pipeline

## Files and Artifacts

### Master Framework Files
- **Master Log:** \`$RESULTS_DIR/master_test.log\`
- **Test Results:** \`$RESULTS_DIR/test_results.txt\`
- **This Report:** \`$report_file\`

### Individual Test Artifacts
$(if [ -f "$RESULTS_DIR/test_results.txt" ]; then
    while IFS='|' read -r test_name status duration test_dir; do
        echo "- **$test_name:** All files in \`$test_dir/\`"
    done < "$RESULTS_DIR/test_results.txt"
fi)

---

**Testing Framework Version:** v2.0  
**Framework Components:** Comprehensive Testing + Daily Simulation + Massive Performance  
**Total Testing Capability:** Up to 1M+ contacts with time-based simulation and real-world scenarios  

EOF

    log "INFO" "${GREEN}✅ Master report generated: $report_file${NC}"
}

# Function to cleanup test files
cleanup_test_files() {
    if [ "$CLEANUP_AFTER" = true ]; then
        log "INFO" "${YELLOW}🧹 Cleaning up test files...${NC}"
        
        # Clean up individual test directories but keep reports
        if [ -f "$RESULTS_DIR/test_results.txt" ]; then
            while IFS='|' read -r test_name status duration test_dir; do
                # Keep .md reports and .log files, remove databases
                find "$test_dir" -name "*.db" -delete 2>/dev/null || true
                find "$test_dir" -name "temp_*" -type d -exec rm -rf {} + 2>/dev/null || true
            done < "$RESULTS_DIR/test_results.txt"
        fi
        
        log "INFO" "${GREEN}✅ Cleanup completed (reports preserved)${NC}"
    else
        log "INFO" "${CYAN}💾 Test files preserved for manual inspection${NC}"
    fi
}

# Main execution function
main() {
    local start_time=$(date +%s)
    
    log "INFO" "${BOLD}🎯 Starting Master Testing Framework${NC}"
    log "INFO" "${CYAN}Selected tests: ${SELECTED_TESTS[*]}${NC}"
    log "INFO" "${CYAN}Parallel execution: $PARALLEL_EXECUTION${NC}"
    log "INFO" "${CYAN}Results directory: $RESULTS_DIR${NC}"
    
    # Check prerequisites
    local missing_scripts=()
    for script in "./run_comprehensive_tests.sh" "./simulate_daily_scheduling.sh" "./generate_massive_performance_test.sh"; do
        if [ ! -x "$script" ]; then
            missing_scripts+=("$script")
        fi
    done
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        log "ERROR" "${RED}❌ Missing required scripts: ${missing_scripts[*]}${NC}"
        exit 1
    fi
    
    # Prepare test configurations
    mapfile -t test_configs < <(prepare_test_configs "$@")
    
    if [ ${#test_configs[@]} -eq 0 ]; then
        log "ERROR" "${RED}❌ No valid test configurations generated${NC}"
        exit 1
    fi
    
    log "INFO" "${CYAN}📋 Prepared ${#test_configs[@]} test configuration(s)${NC}"
    
    # Execute tests
    local success=true
    if [ "$PARALLEL_EXECUTION" = true ] && [ ${#test_configs[@]} -gt 1 ]; then
        if ! run_tests_parallel "${test_configs[@]}"; then
            success=false
        fi
    else
        if ! run_tests_sequential "${test_configs[@]}"; then
            success=false
        fi
    fi
    
    # Generate master report
    generate_master_report
    
    # Cleanup if requested
    cleanup_test_files
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # Final summary
    log "INFO" "${BOLD}🎉 Master Testing Framework Complete!${NC}"
    log "INFO" "${GREEN}📊 Total execution time: ${total_duration}s${NC}"
    
    if [ "$success" = true ]; then
        log "INFO" "${GREEN}✅ All tests completed successfully${NC}"
        echo ""
        echo -e "${BOLD}=== TESTING FRAMEWORK COMPLETE ===${NC}"
        echo -e "${GREEN}✅ All test phases completed successfully${NC}"
        echo -e "${CYAN}📊 Master report: $RESULTS_DIR/MASTER_TEST_REPORT.md${NC}"
        echo -e "${CYAN}📁 All results: $RESULTS_DIR/${NC}"
        return 0
    else
        log "ERROR" "${RED}❌ Some tests failed - check individual reports${NC}"
        echo ""
        echo -e "${BOLD}=== TESTING FRAMEWORK COMPLETE WITH ISSUES ===${NC}"
        echo -e "${RED}❌ Some tests failed${NC}"
        echo -e "${CYAN}📊 Master report: $RESULTS_DIR/MASTER_TEST_REPORT.md${NC}"
        echo -e "${CYAN}📁 All results: $RESULTS_DIR/${NC}"
        return 1
    fi
}

# Execute main function
main "$@"