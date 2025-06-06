# Database Operation Refactoring Guide

## Overview

This guide documents the refactoring of database operations to use the "download, modify locally, upload new database" pattern instead of direct synchronization, which has performance issues with bulk operations.

## The LocalDatabaseOperation Pattern

### Why This Pattern?

1. **Performance**: Direct sync operations become very slow with many changes
2. **Consistency**: Ensures all changes are atomic at the database level
3. **Locking**: Prevents concurrent modifications during operations
4. **Scalability**: Works better with large datasets

### How It Works

1. **Lock**: Acquire `is_db_provisioning = 1` lock to prevent concurrent operations
2. **Download**: Download existing database dump from Turso
3. **Local Copy**: Create local SQLite database from dump
4. **Modify**: Make all changes to the local database
5. **Upload**: Create new Turso database and upload modified data
6. **Update**: Update main database with new credentials
7. **Release**: Clear the provisioning lock

## Implementation

### 1. LocalDatabaseOperation Service

Created `src/services/localDatabaseOperation.ts`:

```typescript
export class LocalDatabaseOperation {
  // Initialize: Lock and download existing database
  async initialize(): Promise<void>
  
  // Get local database for operations
  getLocalDb(): BunDatabase
  
  // Commit: Upload to new Turso database and update main DB
  async commit(): Promise<void>
  
  // Clean up temporary files
  async cleanup(): Promise<void>
  
  // Static method for easy usage
  static async execute<T>(
    orgId: string, 
    operation: (localDb: BunDatabase) => Promise<T>
  ): Promise<T>
}
```

### 2. Database Class Extensions

Added static methods to the `Database` class:

```typescript
// Create or update a single contact
static async createOrUpdateContact(orgId: string, contactData: ContactData): Promise<Result>

// Delete multiple contacts
static async deleteContacts(orgId: string, contactIds: number[]): Promise<Result>
```

### 3. Updated Contact Routes

#### Read Operations (No Change)
- GET `/api/contacts` - Still uses direct database connection for performance
- GET `/api/contacts/check-email/:email` - Read-only, no change needed

#### Write Operations (Refactored)
- POST `/api/contacts` - Now uses `Database.createOrUpdateContact()`
- DELETE `/api/contacts` - Now uses `Database.deleteContacts()`
- POST `/api/contacts/bulk-import` - Already uses this pattern

## Usage Examples

### Creating/Updating a Contact

```typescript
// Before (direct database operation)
const orgDb = await Database.getOrInitOrgDb(orgId);
await orgDb.execute('INSERT INTO contacts ...', [...]);

// After (LocalDatabaseOperation pattern)
const result = await Database.createOrUpdateContact(orgId, contactData);
```

### Deleting Contacts

```typescript
// Before (direct database operation)
const orgDb = await Database.getOrInitOrgDb(orgId);
await orgDb.transaction(async (tx) => {
  // Move to deleted_contacts and delete
});

// After (LocalDatabaseOperation pattern)
const result = await Database.deleteContacts(orgId, contactIds);
```

### Custom Operations

```typescript
// For custom operations, use the LocalDatabaseOperation directly
const result = await LocalDatabaseOperation.execute(orgId, async (localDb) => {
  // Make any changes to localDb using BunDatabase methods
  localDb.prepare('UPDATE contacts SET status = ?').run('processed');
  
  // Return any result you need
  return { success: true, modified: localDb.changes };
});
```

## Benefits

1. **Atomic Operations**: All changes happen atomically when the new database goes live
2. **Better Performance**: No sync overhead for bulk operations
3. **Locking**: Prevents concurrent modifications automatically
4. **Consistency**: Either all changes succeed or none do
5. **Flexibility**: Can make complex multi-table changes easily

## When to Use Each Pattern

### Use LocalDatabaseOperation For:
- Creating/updating individual contacts
- Deleting contacts
- Bulk imports
- Any operation that modifies data
- Operations that need to be atomic

### Use Direct Database Connection For:
- Reading contacts (GET operations)
- Searching and filtering
- Analytics queries
- Any read-only operation

## Migration Strategy

1. ✅ Create `LocalDatabaseOperation` service
2. ✅ Add static methods to `Database` class
3. 🔄 Update POST `/api/contacts` route
4. 🔄 Update DELETE `/api/contacts` route
5. ⏳ Update any other write operations as needed
6. ⏳ Test thoroughly with various scenarios

## Error Handling

The LocalDatabaseOperation includes comprehensive error handling:

- Automatic lock release on errors
- Temporary file cleanup
- Transaction rollback for individual operations
- Detailed logging throughout the process

## Performance Considerations

- **Overhead**: Initial download/upload has overhead, so this pattern is best for operations that modify significant data
- **Lock Duration**: Operations hold a lock for the entire duration, so they should be reasonably fast
- **Memory Usage**: Local database operations use memory, but SQLite is efficient
- **Network**: Download/upload operations depend on network speed

## Testing

Test scenarios to verify:

1. Single contact creation
2. Single contact update (email exists)
3. Bulk contact deletion
4. Concurrent operation handling (should fail gracefully)
5. Error scenarios (network issues, invalid data)
6. Lock release after errors

This pattern provides a robust, scalable solution for database operations while maintaining data consistency and preventing performance issues with large datasets.