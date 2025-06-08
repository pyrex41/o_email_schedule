# Campaign System Examples

This document demonstrates how to use the new campaign system, particularly showing how Annual Enrollment Period (AEP) is now implemented as a campaign instead of an anniversary-based email.

## AEP as a Campaign with Spread Evenly

AEP is now configured as a campaign that can spread emails evenly across a date range, rather than sending all emails on September 15th.

### 1. Create the AEP Campaign Type

```sql
INSERT INTO campaign_types (
    name, 
    respect_exclusion_windows, 
    enable_followups, 
    days_before_event, 
    target_all_contacts, 
    priority, 
    active, 
    spread_evenly
) VALUES (
    'aep', 
    1,  -- true - respect exclusion windows
    1,  -- true - enable followups
    0,  -- 0 days before event (send on the spread dates)
    1,  -- true - target all contacts
    30, -- priority 30 (same as old AEP)
    1,  -- true - active
    1   -- true - spread evenly across date range
);
```

### 2. Create an AEP Campaign Instance for 2024

```sql
INSERT INTO campaign_instances (
    campaign_type,
    instance_name,
    email_template,
    sms_template,
    active_start_date,
    active_end_date,
    spread_start_date,
    spread_end_date,
    metadata
) VALUES (
    'aep',
    'aep_2024_september',
    'aep_template_2024',
    'aep_sms_template_2024',
    '2024-09-01',  -- Campaign becomes active Sept 1
    '2024-09-30',  -- Campaign expires Sept 30
    '2024-09-01',  -- Start spreading emails from Sept 1
    '2024-09-30',  -- End spreading emails on Sept 30
    '{"year": 2024, "description": "Annual Enrollment Period September 2024"}'
);
```

### 3. How Spread Evenly Works

With `spread_evenly=true` and the spread date range of September 1-30:

- **Total contacts**: All contacts in the database (since `target_all_contacts=true`)
- **Distribution**: Emails are distributed across 30 days (Sept 1-30)
- **Algorithm**: Uses `contact_id mod 30` to determine which day each contact gets their email
- **Deterministic**: Same contact always gets assigned to the same day
- **Even distribution**: Roughly equal number of emails each day

Example distribution:
- Contact ID 1 → September 2nd (1 mod 30 = 1, so day 1 + Sept 1 = Sept 2)
- Contact ID 30 → September 1st (30 mod 30 = 0, so day 0 + Sept 1 = Sept 1)
- Contact ID 31 → September 2nd (31 mod 30 = 1, so day 1 + Sept 1 = Sept 2)

### 4. Exclusion Window Handling

Since `respect_exclusion_windows=true`, contacts in exclusion windows will:
- Have their AEP email marked as "skipped" with the exclusion reason
- Get a post-window email scheduled for after their exclusion window ends
- This ensures no contact misses AEP communication due to state regulations

### 5. Rate Increase Campaign Example

Here's how a rate increase campaign would be configured:

```sql
-- Campaign Type
INSERT INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly
) VALUES (
    'rate_increase', 1, 1, 14, 0, 1, 1, 0  -- spread_evenly=false for targeted timing
);

-- Campaign Instance
INSERT INTO campaign_instances (
    campaign_type, instance_name, email_template, active_start_date, active_end_date
) VALUES (
    'rate_increase', 'rate_increase_q1_2024', 'rate_increase_template_v2', 
    '2024-01-01', '2024-03-31'
);

-- Target specific contacts with their rate change dates
INSERT INTO contact_campaigns (
    contact_id, campaign_instance_id, trigger_date, status
) VALUES 
    (123, 1, '2024-02-15', 'pending'),  -- Rate change on Feb 15, email sent Feb 1 (14 days before)
    (456, 1, '2024-03-01', 'pending'),  -- Rate change on Mar 1, email sent Feb 15
    (789, 1, '2024-03-15', 'pending');  -- Rate change on Mar 15, email sent Mar 1
```

## Benefits of the New Campaign System

1. **Flexibility**: AEP can be spread across any date range, not just Sept 15
2. **Load Balancing**: Even distribution prevents email infrastructure overload
3. **Compliance**: Still respects state exclusion windows with post-window emails
4. **Configurability**: Easy to adjust templates, date ranges, and targeting
5. **Multiple Campaigns**: Can run multiple campaign instances simultaneously
6. **Unified Architecture**: Same system handles AEP, rate increases, promotions, etc.

## Migration from Old AEP System

The old anniversary-based AEP system that sent all emails on September 15th is now replaced by this campaign-based system. Benefits include:

- **Better deliverability**: Spread emails prevent ISP throttling
- **Reduced server load**: Even distribution over 30 days vs. single day spike
- **Improved user experience**: Recipients don't all get emails on the same day
- **Flexible timing**: Can adjust the spread window as needed
- **Template versioning**: Each year can have different templates and messaging