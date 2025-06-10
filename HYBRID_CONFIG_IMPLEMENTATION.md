# Hybrid Configuration System Implementation

## Overview

This implementation provides a hybrid configuration system that stores essential business rules per-organization in a central database (Turso) while keeping system constants in code. The system uses size profiles to handle load balancing variations across organizations ranging from hundreds to millions of contacts.

## Architecture

### Key Principles
1. **Central configuration** in Turso organizations table (not replicated)
2. **Org-specific databases** contain only contacts and email_schedules
3. **Single query** at scheduler start fetches org configuration
4. **Size profiles** handle load balancing variations
5. **System constants** remain in version-controlled code

## Files Modified/Created

### New Modules
- `lib/utils/system_constants.ml` - System-wide constants that rarely change
- `lib/utils/size_profiles.ml` - Size-based load balancing configuration
- `test/test_size_profiles.ml` - Unit tests for size profiles

### Modified Modules
- `lib/domain/types.ml` - Added size profile and enhanced organization config types
- `lib/utils/config.ml` - Replaced with hybrid configuration system
- `lib/db/database.ml` - Added organization config loading functions
- `lib/scheduling/email_scheduler.ml` - Updated to use new config structure
- `lib/scheduling/date_calc.ml` - Updated to accept configurable buffer days
- `lib/rules/exclusion_window.ml` - Updated to use org-specific buffer settings
- `bin/scheduler_cli.ml` - Updated to accept organization ID parameter

### Database Migrations
- `migrations/001_add_organization_config.sql` - Add config columns to organizations table
- `migrations/002_add_state_buffer_overrides.sql` - Optional state-specific buffer table

### Configuration
- `.env.hybrid.example` - Environment configuration template

## Key Features

### Size Profiles
Organizations are automatically categorized into size profiles based on contact count:
- **Small** (< 10k contacts): 20% daily cap, aggressive scheduling
- **Medium** (10k-100k contacts): 10% daily cap, balanced approach
- **Large** (100k-500k contacts): 7% daily cap, conservative approach
- **Enterprise** (500k+ contacts): 5% daily cap, very conservative

### Configuration Overrides
Organizations can have JSON-based configuration overrides for edge cases:
```json
{
  "batch_size": 50000,
  "daily_send_percentage_cap": 0.03,
  "ed_daily_soft_limit": 2000
}
```

### State-Specific Buffers
Optional state-specific pre-exclusion buffer overrides allow for compliance with varying state regulations.

## Usage

### CLI Usage
```bash
./scheduler_cli.exe /path/to/org-specific.sqlite3 206
```

### Environment Variables
```bash
export CENTRAL_DB_URL="libsql://your-database.turso.io"
export CENTRAL_DB_TOKEN="your-auth-token"
```

### Loading Configuration
```ocaml
let config = Config.load_for_org org_id org_specific_db_path in
let load_balancing = Config.to_load_balancing_config config in
```

## Performance Benefits

1. **Single Query**: One database query at startup loads all org configuration
2. **Automatic Scaling**: Size profiles automatically adjust settings based on contact count
3. **Minimal Database Changes**: Only essential fields in organizations table
4. **Backward Compatible**: Defaults ensure existing systems continue working

## System Constants

The following constants are defined in code and apply system-wide:
- ED percentage of daily cap: 30%
- Overage threshold: 120%
- Catch-up spread days: 7
- Followup lookback days: 35
- Email priorities (birthday: 10, effective date: 20, etc.)

## Migration Path

1. Apply database migrations to add configuration columns
2. Update organizations with appropriate size profiles and settings
3. Deploy updated scheduler with organization ID parameter
4. Verify configuration loading works with central database connection

## Benefits

- **Flexibility**: Easy to adjust per-organization settings without code changes
- **Performance**: Single query at startup, no config lookups during processing  
- **Scalability**: Handles orgs from 100 to 1M+ contacts with appropriate settings
- **Maintainability**: System constants in version control, business rules in database
- **Compliance**: State-specific buffer overrides for regulatory requirements

## Testing

Run the size profiles tests:
```bash
dune exec test/test_size_profiles.exe
```

## Configuration Examples

### Small Organization (5k contacts)
- Daily cap: 20% (1000 emails/day)
- Batch size: 1000
- ED soft limit: 50

### Enterprise Organization (1M contacts)  
- Daily cap: 5% (50,000 emails/day)
- Batch size: 25,000
- ED soft limit: 1000

This implementation provides the right balance between flexibility and simplicity, avoiding over-engineering while meeting the needs of diverse organization sizes.