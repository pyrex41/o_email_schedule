#!/usr/bin/env python3

import sqlite3
import random
import time
from datetime import datetime, timedelta

def generate_1m_contacts():
    db_file = "massive_1m_test.db"
    print(f"🏗️  Generating 1 million contacts in {db_file}...")
    
    # Remove existing database
    import os
    if os.path.exists(db_file):
        os.remove(db_file)
    
    start_time = time.time()
    
    # Connect and create optimized database
    conn = sqlite3.connect(db_file)
    conn.execute('PRAGMA journal_mode = OFF')
    conn.execute('PRAGMA synchronous = OFF')
    conn.execute('PRAGMA cache_size = 1000000')
    conn.execute('PRAGMA temp_store = MEMORY')
    
    # Create schema
    schema_sql = """
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
    
    CREATE INDEX idx_contacts_birth_date ON contacts(birth_date);
    CREATE INDEX idx_contacts_effective_date ON contacts(effective_date);
    CREATE INDEX idx_contacts_state ON contacts(state);
    """
    
    conn.executescript(schema_sql)
    print("✅ Schema created")
    
    # Realistic state distribution (weighted by population)
    states = (
        ['CA'] * 12 + ['TX'] * 9 + ['FL'] * 7 + ['NY'] * 6 + ['PA'] * 4 +
        ['IL'] * 4 + ['OH'] * 3 + ['GA'] * 3 + ['NC'] * 3 + ['MI'] * 3 +
        ['NJ', 'VA', 'WA', 'AZ', 'MA', 'TN', 'IN', 'MD', 'MO', 'WI'] * 2 +
        ['CT', 'OR', 'KY', 'OK', 'NV', 'ID', 'AL', 'SC', 'LA', 'UT'] * 1 +
        ['NE', 'NM', 'HI', 'ME', 'MT', 'ND', 'SD', 'DE', 'RI', 'VT', 'WY', 'AK']
    )
    
    carriers = ['Anthem', 'BCBS', 'Humana', 'Aetna', 'UnitedHealth', 'Cigna', 'Kaiser']
    
    # Generate contacts in efficient batches
    batch_size = 50000
    total_contacts = 1000000
    
    conn.execute('BEGIN TRANSACTION')
    
    for batch_start in range(0, total_contacts, batch_size):
        batch_end = min(batch_start + batch_size, total_contacts)
        batch_data = []
        
        for i in range(batch_start, batch_end):
            contact_id = i + 1
            
            # Generate realistic dates
            birth_year = random.randint(1940, 2000)
            birth_month = random.randint(1, 12)
            birth_day = random.randint(1, 28)
            birth_date = f"{birth_year:04d}-{birth_month:02d}-{birth_day:02d}"
            
            # Effective date typically 2-5 years ago
            eff_year = random.randint(2019, 2023)
            eff_month = random.randint(1, 12)
            eff_day = random.randint(1, 28)
            effective_date = f"{eff_year:04d}-{eff_month:02d}-{eff_day:02d}"
            
            state = random.choice(states)
            carrier = random.choice(carriers)
            email = f"contact{contact_id}@test{random.randint(1000,9999)}.com"
            zip_code = f"{random.randint(10000, 99999)}"
            failed_underwriting = 1 if random.random() < 0.15 else 0  # 15% failure rate
            
            batch_data.append((
                contact_id, email, zip_code, state, birth_date, 
                effective_date, carrier, failed_underwriting
            ))
        
        # Bulk insert batch
        conn.executemany(
            "INSERT INTO contacts (id, email, zip_code, state, birth_date, effective_date, carrier, failed_underwriting) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            batch_data
        )
        
        elapsed = time.time() - start_time
        rate = batch_end / elapsed if elapsed > 0 else 0
        print(f"📊 Generated {batch_end:,} contacts ({rate:,.0f} contacts/sec)")
    
    conn.execute('COMMIT')
    
    # Verify count
    cursor = conn.execute("SELECT COUNT(*) FROM contacts")
    actual_count = cursor.fetchone()[0]
    
    total_time = time.time() - start_time
    
    print(f"\n🎉 DATABASE GENERATION COMPLETE:")
    print(f"   • File: {db_file}")
    print(f"   • Contacts: {actual_count:,}")
    print(f"   • Time: {total_time:.1f} seconds")
    print(f"   • Rate: {actual_count/total_time:,.0f} contacts/second")
    
    # Check file size
    import os
    file_size_mb = os.path.getsize(db_file) / (1024 * 1024)
    print(f"   • Database size: {file_size_mb:.1f} MB")
    
    conn.close()
    return db_file

if __name__ == "__main__":
    generate_1m_contacts()