#!/usr/bin/env python3
"""
Convert SQLite binary changeset to SQL statements
For use when sessions extension is not available
"""

import sqlite3
import sys
import os

def apply_changeset_via_sql(db_path, changeset_path):
    """
    Alternative method to apply changeset when sessions extension isn't available
    """
    if not os.path.exists(changeset_path):
        print(f"Error: Changeset file {changeset_path} not found")
        return False
    
    if not os.path.exists(db_path):
        print(f"Error: Database file {db_path} not found") 
        return False
    
    try:
        # Read the changeset file
        with open(changeset_path, 'rb') as f:
            changeset_data = f.read()
        
        print(f"Changeset size: {len(changeset_data)} bytes")
        
        # Connect to database
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Try to apply using sessions extension first
        try:
            cursor.execute("PRAGMA load_extension = 1")
            cursor.execute("SELECT load_extension('sessions')")
            
            # Apply changeset
            cursor.execute("SELECT sqlite_changeset_apply(?)", (changeset_data,))
            conn.commit()
            print("✅ Changeset applied successfully using sessions extension")
            return True
            
        except sqlite3.Error as e:
            print(f"⚠️  Sessions extension not available: {e}")
            print("📋 Changeset contains binary data that requires sessions extension")
            print("💡 Alternatives:")
            print("   1. Install SQLite with sessions extension")
            print("   2. Use SQL diff approach instead:")
            print("      ./turso-workflow.sh diff")
            print("      ./turso-workflow.sh apply-diff")
            return False
            
    except Exception as e:
        print(f"❌ Error processing changeset: {e}")
        return False
    finally:
        if 'conn' in locals():
            conn.close()

def check_sessions_support(db_path):
    """Check if sessions extension is available"""
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        cursor.execute("PRAGMA load_extension = 1")
        cursor.execute("SELECT load_extension('sessions')")
        cursor.execute("SELECT sqlite_version()")
        
        print("✅ Sessions extension is available")
        return True
        
    except sqlite3.Error as e:
        print(f"❌ Sessions extension not available: {e}")
        return False
    finally:
        conn.close()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 convert_changeset.py check <database.db>")
        print("  python3 convert_changeset.py apply <database.db> <changeset.bin>")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "check":
        if len(sys.argv) != 3:
            print("Usage: python3 convert_changeset.py check <database.db>")
            sys.exit(1)
        check_sessions_support(sys.argv[2])
    
    elif command == "apply":
        if len(sys.argv) != 4:
            print("Usage: python3 convert_changeset.py apply <database.db> <changeset.bin>")
            sys.exit(1)
        
        db_path = sys.argv[2]
        changeset_path = sys.argv[3]
        
        success = apply_changeset_via_sql(db_path, changeset_path)
        sys.exit(0 if success else 1)
    
    else:
        print(f"Unknown command: {command}")
        sys.exit(1) 