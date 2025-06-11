-- Migration 003: Add campaign system tables
-- This migration creates the core campaign tables needed for the campaign system

-- Campaign types define reusable campaign templates
CREATE TABLE IF NOT EXISTS campaign_types (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    respect_exclusion_windows INTEGER NOT NULL DEFAULT 1,
    enable_followups INTEGER NOT NULL DEFAULT 0,
    days_before_event INTEGER NOT NULL DEFAULT 30,
    target_all_contacts INTEGER NOT NULL DEFAULT 0,
    priority INTEGER NOT NULL DEFAULT 30,
    active INTEGER NOT NULL DEFAULT 1,
    spread_evenly INTEGER NOT NULL DEFAULT 0,
    skip_failed_underwriting INTEGER NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Campaign instances are specific runs of campaign types
CREATE TABLE IF NOT EXISTS campaign_instances (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_type TEXT NOT NULL,
    instance_name TEXT NOT NULL,
    email_template TEXT,
    sms_template TEXT,
    active_start_date TEXT,
    active_end_date TEXT,
    spread_start_date TEXT,
    spread_end_date TEXT,
    target_states TEXT,
    target_carriers TEXT,
    metadata TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (campaign_type) REFERENCES campaign_types(name)
);

-- Contact campaigns track which contacts are enrolled in which campaign instances
CREATE TABLE IF NOT EXISTS contact_campaigns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id INTEGER NOT NULL,
    campaign_instance_id INTEGER NOT NULL,
    trigger_date TEXT,
    status TEXT NOT NULL DEFAULT 'pending',
    metadata TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (contact_id) REFERENCES contacts(id),
    FOREIGN KEY (campaign_instance_id) REFERENCES campaign_instances(id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaign_types_name ON campaign_types(name);
CREATE INDEX IF NOT EXISTS idx_campaign_types_active ON campaign_types(active);
CREATE INDEX IF NOT EXISTS idx_campaign_instances_type ON campaign_instances(campaign_type);
CREATE INDEX IF NOT EXISTS idx_campaign_instances_dates ON campaign_instances(active_start_date, active_end_date);
CREATE INDEX IF NOT EXISTS idx_contact_campaigns_contact ON contact_campaigns(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_campaigns_instance ON contact_campaigns(campaign_instance_id);
CREATE INDEX IF NOT EXISTS idx_contact_campaigns_status ON contact_campaigns(status);

-- Insert default AEP campaign type
INSERT OR IGNORE INTO campaign_types (
    name, respect_exclusion_windows, enable_followups, days_before_event,
    target_all_contacts, priority, active, spread_evenly, skip_failed_underwriting
) VALUES (
    'aep', 1, 1, 30, 1, 30, 1, 0, 0
);

-- Insert default AEP campaign instance
INSERT OR IGNORE INTO campaign_instances (
    campaign_type, instance_name, email_template, sms_template,
    active_start_date, active_end_date, spread_start_date, spread_end_date,
    target_states, target_carriers, metadata
) VALUES (
    'aep', 'Default AEP 2025', 'aep_email_template', 'aep_sms_template',
    '2024-09-01', '2024-12-31', '2024-09-01', '2024-12-07',
    NULL, NULL, '{"description": "Default AEP campaign for 2025"}'
);