# Campaign System Enhancements - Implementation Documentation

## Overview

This document details the comprehensive enhancements made to the email scheduling system to provide flexible, organization-configurable campaign management with state/carrier targeting, spread distribution, and underwriting-based exclusions.

## 🎯 Key Features Implemented

### 1. Campaign Targeting System
- **State-specific targeting**: Target campaigns to specific states (e.g., "CA,TX,NY")
- **Carrier-specific targeting**: Target campaigns to specific insurance carriers
- **Universal campaigns**: Target all contacts regardless of location/carrier
- **Mixed targeting**: Combine state AND carrier constraints

### 2. Organization Configuration Options
- **Post-window email control**: Organizations can disable post-window catch-up emails
- **Effective date timing**: Configurable months before first effective date email (11/23/35 months)
- **Underwriting exclusions**: Global exclusion of failed underwriting contacts (except AEP)
- **Universal campaign behavior**: Allow sending to contacts without zip codes for universal campaigns

### 3. Campaign-Level Exclusion Controls
- **Exclusion window override**: Per-campaign control over state exclusion rules
- **Underwriting consideration**: Per-campaign control over failed underwriting exclusions
- **Flexible compliance**: Campaigns can bypass normal restrictions when needed

### 4. Enhanced Contact Validation
- **Context-aware validation**: Different validation rules for anniversary vs. campaign emails
- **Fallback behavior**: Smart defaults for missing location data
- **Graceful degradation**: System continues working with partial contact data

## 📊 Database Schema Changes

### Updated Contact Table
```sql
ALTER TABLE contacts ADD COLUMN carrier TEXT;
ALTER TABLE contacts ADD COLUMN failed_underwriting BOOLEAN DEFAULT FALSE;
```

### Updated Campaign Types Table
```sql
ALTER TABLE campaign_types ADD COLUMN skip_failed_underwriting BOOLEAN DEFAULT FALSE;
```

### Updated Campaign Instances Table
```sql
ALTER TABLE campaign_instances ADD COLUMN target_states TEXT;
ALTER TABLE campaign_instances ADD COLUMN target_carriers TEXT;
```

## 🔧 Configuration Structure

### Organization Configuration
```yaml
organization:
  enable_post_window_emails: true          # Whether to send catch-up emails after exclusion windows
  effective_date_first_email_months: 11    # Months before first effective date anniversary
  exclude_failed_underwriting_global: false # Exclude failed underwriting from all except AEP
  send_without_zipcode_for_universal: true  # Send to contacts without zip for universal campaigns
```

### Campaign Type Configuration
```sql
INSERT INTO campaign_types (
    name, 
    respect_exclusion_windows,     -- Whether this campaign respects state exclusion rules
    enable_followups,              -- Whether to generate follow-up emails
    days_before_event,             -- Days before trigger date to send
    target_all_contacts,           -- Whether this targets all contacts
    priority,                      -- Email priority (lower = higher priority)
    active,                        -- Whether this campaign type is active
    spread_evenly,                 -- Whether to spread emails across date range
    skip_failed_underwriting       -- Whether to skip failed underwriting contacts
) VALUES (...);
```

### Campaign Instance Configuration
```sql
INSERT INTO campaign_instances (
    campaign_type,
    instance_name,
    email_template,
    sms_template,
    active_start_date,             -- When this instance becomes active
    active_end_date,               -- When this instance expires
    spread_start_date,             -- Start date for spread_evenly distribution
    spread_end_date,               -- End date for spread_evenly distribution
    target_states,                 -- "CA,TX,NY" or "ALL" or NULL
    target_carriers,               -- "AETNA,BCBS" or "ALL" or NULL
    metadata
) VALUES (...);
```

## 📝 Implementation Examples

### Example 1: AEP Campaign with Spread Distribution
```sql
-- Campaign Type: AEP with spread evenly
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'aep', 1, 1, 0, 1, 30, 1, 1, 0
);

-- Campaign Instance: September 2024 AEP spread across the month
INSERT INTO campaign_instances (
    campaign_type, instance_name, email_template, sms_template,
    active_start_date, active_end_date, spread_start_date, spread_end_date,
    target_states, target_carriers, metadata
) VALUES (
    'aep', 'aep_2024_september', 'aep_template_2024', 'aep_sms_2024',
    '2024-09-01', '2024-09-30', '2024-09-01', '2024-09-30',
    'ALL', 'ALL', 
    '{"year": 2024, "description": "AEP spread across September"}'
);
```

### Example 2: State-Specific Rate Increase Campaign
```sql
-- Campaign Type: Rate increases that respect exclusion windows
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'rate_increase', 1, 1, 14, 0, 1, 1, 0, 0
);

-- Campaign Instance: Q1 2024 rate increases for CA and TX only
INSERT INTO campaign_instances (
    campaign_type, instance_name, email_template, active_start_date, active_end_date,
    target_states, target_carriers
) VALUES (
    'rate_increase', 'rate_increase_ca_tx_q1_2024', 'rate_increase_template_v3',
    '2024-01-01', '2024-03-31', 'CA,TX', 'ALL'
);

-- Target specific contacts with their rate change dates
INSERT INTO contact_campaigns (contact_id, campaign_instance_id, trigger_date, status)
VALUES 
    (123, 1, '2024-02-15', 'pending'),  -- CA contact, rate change Feb 15
    (456, 1, '2024-03-01', 'pending'),  -- TX contact, rate change Mar 1
    (789, 1, '2024-03-15', 'pending');  -- Another contact, rate change Mar 15
```

### Example 3: Carrier-Specific Promotion (No Exclusion Windows)
```sql
-- Campaign Type: Promotional campaign that bypasses exclusion windows
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'carrier_promo', 0, 1, 7, 1, 15, 1, 0, 1  -- Note: respect_exclusion_windows = 0
);

-- Campaign Instance: AETNA-only promotion
INSERT INTO campaign_instances (
    campaign_type, instance_name, email_template, active_start_date, active_end_date,
    target_states, target_carriers
) VALUES (
    'carrier_promo', 'aetna_spring_2024', 'aetna_promo_template',
    '2024-03-01', '2024-05-31', 'ALL', 'AETNA'
);
```

### Example 4: Organization with Restricted Underwriting Policy
```yaml
# Organization configuration for strict underwriting exclusions
organization:
  enable_post_window_emails: true
  effective_date_first_email_months: 23        # Wait 23 months for first ED email
  exclude_failed_underwriting_global: true     # Exclude from all except AEP
  send_without_zipcode_for_universal: false    # Require zip codes even for universal
```

## 🔄 Scheduling Logic Flow

### Campaign Scheduling Process
1. **Fetch Active Campaigns**: Get all campaign instances active today
2. **Load Campaign Configuration**: Get campaign type settings for each instance
3. **Apply Targeting Filters**: Filter contacts based on state/carrier targeting
4. **Check Organization Exclusions**: Apply global underwriting exclusions
5. **Check Campaign Exclusions**: Apply campaign-specific exclusions
6. **Calculate Schedule Dates**: Use spread_evenly or trigger-based calculation
7. **Apply State Exclusion Windows**: If campaign respects exclusion windows
8. **Generate Schedules**: Create email_schedule records with appropriate status

### Anniversary Scheduling Process
1. **Validate Contact**: Use enhanced validation considering organization settings
2. **Check Global Exclusions**: Apply organization underwriting policy
3. **Check Effective Date Timing**: Ensure minimum months threshold met
4. **Calculate Anniversary Dates**: Determine next birthday/effective date anniversaries
5. **Apply Exclusion Windows**: Check state-specific exclusion rules
6. **Generate Post-Window Emails**: If organization enables them and emails were skipped

## 🎛️ Configuration Examples by Organization Type

### Conservative Organization
```yaml
organization:
  enable_post_window_emails: true              # Always catch up after exclusions
  effective_date_first_email_months: 23        # Wait almost 2 years
  exclude_failed_underwriting_global: true     # Very strict underwriting policy
  send_without_zipcode_for_universal: false    # Require complete contact data
```

### Aggressive Marketing Organization
```yaml
organization:
  enable_post_window_emails: false             # Don't bother with catch-ups
  effective_date_first_email_months: 11        # Standard timing
  exclude_failed_underwriting_global: false    # Allow failed underwriting
  send_without_zipcode_for_universal: true     # Send even with incomplete data
```

### Compliance-Focused Organization
```yaml
organization:
  enable_post_window_emails: true              # Always catch up
  effective_date_first_email_months: 11        # Standard timing  
  exclude_failed_underwriting_global: false    # Let campaigns decide
  send_without_zipcode_for_universal: false    # Require complete data for targeting
```

## 🚀 Benefits Achieved

### 1. **Operational Flexibility**
- Organizations can configure behavior to match their business model
- Campaigns can be quickly deployed with different compliance requirements
- State and carrier targeting enables precise marketing

### 2. **Compliance Management**
- Per-campaign exclusion window control
- Organization-level underwriting policies
- Automatic post-window catch-up emails

### 3. **Performance Optimization**
- Spread distribution prevents email infrastructure overload
- Smart contact validation reduces processing overhead
- Targeted campaigns reduce unnecessary processing

### 4. **Business Intelligence**
- Clear audit trail of why emails were scheduled or skipped
- Flexible reporting on campaign effectiveness
- Organization-specific metrics and compliance reporting

### 5. **Scalability**
- System handles unlimited campaign types and instances
- Efficient database queries with proper indexing
- Graceful handling of missing or invalid contact data

## 🔧 Migration Strategy

### Phase 1: Database Schema Updates
1. Add new columns to existing tables
2. Set default values for backward compatibility
3. Update database queries to handle new fields gracefully

### Phase 2: Configuration Migration
1. Update organization configuration with new settings
2. Migrate existing AEP logic to campaign system
3. Create initial campaign types and instances

### Phase 3: Validation and Testing
1. Test campaign targeting logic with real data
2. Validate exclusion window behavior
3. Verify organization settings work as expected

### Phase 4: Full Deployment
1. Switch from anniversary-based AEP to campaign-based AEP
2. Enable new campaign features for production use
3. Monitor performance and adjust as needed

## 📈 Performance Considerations

### Database Indexing
```sql
-- Optimize contact queries for targeting
CREATE INDEX idx_contacts_state_carrier ON contacts(state, carrier);
CREATE INDEX idx_contacts_underwriting ON contacts(failed_underwriting);

-- Optimize campaign queries
CREATE INDEX idx_campaign_instances_targeting ON campaign_instances(target_states, target_carriers);
CREATE INDEX idx_campaign_instances_active ON campaign_instances(active_start_date, active_end_date);

-- Optimize scheduling queries
CREATE INDEX idx_contact_campaigns_instance ON contact_campaigns(campaign_instance_id, status);
```

### Memory Management
- Process campaigns in batches to avoid memory exhaustion
- Use streaming contact processing for large organizations
- Cache campaign configurations to reduce database hits

### Error Handling
- Graceful degradation when campaign configuration is invalid
- Detailed error logging for troubleshooting
- Fallback behavior for missing contact data

This comprehensive enhancement provides the flexibility needed for diverse organizational requirements while maintaining the system's reliability and performance at scale.