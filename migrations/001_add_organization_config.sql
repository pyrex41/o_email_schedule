-- Migration 001: Add hybrid configuration fields to organizations table
-- This migration adds essential per-organization configuration to support the hybrid config system

-- Add essential per-organization configuration
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    -- Business rules (compliance and policy)
    enable_post_window_emails BOOLEAN NOT NULL DEFAULT 1;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    effective_date_first_email_months INTEGER NOT NULL DEFAULT 11;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    exclude_failed_underwriting_global BOOLEAN NOT NULL DEFAULT 0;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    send_without_zipcode_for_universal BOOLEAN NOT NULL DEFAULT 1;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    pre_exclusion_buffer_days INTEGER NOT NULL DEFAULT 60;

-- Customer preferences
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    birthday_days_before INTEGER NOT NULL DEFAULT 14;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    effective_date_days_before INTEGER NOT NULL DEFAULT 30;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    send_time_hour INTEGER NOT NULL DEFAULT 8;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    send_time_minute INTEGER NOT NULL DEFAULT 30;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    timezone TEXT NOT NULL DEFAULT 'America/Chicago';

-- Communication frequency
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    max_emails_per_period INTEGER NOT NULL DEFAULT 3;

ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    frequency_period_days INTEGER NOT NULL DEFAULT 30;

-- Size-based tuning profile
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    size_profile TEXT NOT NULL DEFAULT 'medium' CHECK (size_profile IN ('small', 'medium', 'large', 'enterprise'));

-- Optional overrides for edge cases
ALTER TABLE organizations ADD COLUMN IF NOT EXISTS
    config_overrides JSON;

-- Add index for active organizations
CREATE INDEX IF NOT EXISTS idx_organizations_active ON organizations(id) WHERE active = 1;

-- Note: Size profiles will remain at default 'medium' value and can be updated
-- later through application logic that has access to org-specific contact databases