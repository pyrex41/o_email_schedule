-- Migration 002: Add state-specific buffer override support
-- This migration adds optional state-specific pre-exclusion buffer overrides

-- Create table for state-specific buffer overrides
CREATE TABLE IF NOT EXISTS organization_state_buffers (
    org_id INTEGER NOT NULL,
    state_code TEXT NOT NULL CHECK (length(state_code) = 2),
    pre_exclusion_buffer_days INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (org_id, state_code),
    FOREIGN KEY (org_id) REFERENCES organizations(id) ON DELETE CASCADE
);

-- Add index for efficient lookups
CREATE INDEX IF NOT EXISTS idx_org_state_buffers ON organization_state_buffers(org_id);

-- Example state-specific overrides (commented out - add as needed)
-- INSERT INTO organization_state_buffers (org_id, state_code, pre_exclusion_buffer_days) VALUES
-- (206, 'CA', 90),  -- California requires longer buffer
-- (206, 'NY', 75);  -- New York has specific requirements