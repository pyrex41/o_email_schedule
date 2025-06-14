-- Create a 100k subset from the 1M database for performance testing
.open massive_1m_test.db
.backup main backup.db
.open massive_100k_test.db

-- Copy schema
CREATE TABLE contacts (
    id INTEGER PRIMARY KEY,
    email TEXT NOT NULL,
    zip_code TEXT,
    state TEXT,
    birth_date TEXT,
    effective_date TEXT,
    carrier TEXT,
    failed_underwriting INTEGER DEFAULT 0
);

CREATE TABLE email_schedules (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    contact_id INTEGER NOT NULL,
    email_type TEXT NOT NULL,
    scheduled_date TEXT NOT NULL,
    scheduled_time TEXT NOT NULL,
    status TEXT NOT NULL,
    priority INTEGER DEFAULT 10,
    template_id TEXT,
    campaign_instance_id INTEGER,
    scheduler_run_id TEXT NOT NULL
);

-- Copy indexes
CREATE INDEX idx_contacts_birth_date ON contacts(birth_date);
CREATE INDEX idx_contacts_effective_date ON contacts(effective_date);
CREATE INDEX idx_contacts_state ON contacts(state);

-- Insert 100k contacts 
.open massive_1m_test.db
ATTACH DATABASE 'massive_100k_test.db' AS subset;

INSERT INTO subset.contacts 
SELECT * FROM contacts 
WHERE id <= 100000;

DETACH DATABASE subset;