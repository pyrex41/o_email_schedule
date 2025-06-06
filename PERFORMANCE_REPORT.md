# OCaml Email Scheduler Performance Test Report

**Generated:** Thu Jun  5 22:36:59 CDT 2025
**System:** Darwin 23.2.0
**OCaml Version:** The OCaml toplevel, version 5.3.0

## Test Databases

- **org-206.sqlite3**: 1.2M (663 contacts)
- **golden_dataset.sqlite3**: 37M (24701 contacts)
- **large_test_dataset.sqlite3**: 8.0M (25000 contacts)

## Recent Test Results

The most recent performance test results can be found in:

- `performance_results/scalability_20250605_223645.txt` (Jun 5 22:36)
- `performance_results/test_results_20250605_223632.txt` (Jun 5 22:36)
- `performance_results/test_results_20250605_223210.txt` (Jun 5 22:32)
- `performance_results/test_results_20250605_222810.txt` (Jun 5 22:28)

## Performance Benchmarks

Target performance metrics:

- **Small Dataset (< 1k contacts)**: < 1 second total processing time
- **Medium Dataset (1k-10k contacts)**: < 10 seconds total processing time
- **Large Dataset (10k+ contacts)**: < 60 seconds total processing time
- **Memory Usage**: < 100MB for 25k contacts
- **Throughput**: > 1000 contacts/second for scheduling

## Next Steps

1. Run `./run_performance_tests.sh --full` for comprehensive testing
2. Check individual test results in `performance_results/` directory
3. Compare results with previous runs to track performance trends
