import { Database as BunDatabase } from 'bun:sqlite';
import fs from 'fs';
import fsPromises from 'fs/promises';
import Bun from 'bun';
import { nanoid } from 'nanoid';
import { logger } from '../logger';
import { TursoService } from './turso';
import { Database } from '../database';

/**
 * Helper class for operations that need to download, modify locally, and upload a new database
 * This implements the pattern of:
 * 1. Acquiring a lock to prevent concurrent operations
 * 2. Downloading the existing database from Turso
 * 3. Creating a local copy for modifications
 * 4. Making changes to the local copy
 * 5. Creating a new Turso database and uploading the modified data
 * 6. Updating the main database with new credentials
 * 7. Releasing the lock
 */
export class LocalDatabaseOperation {
  private tempDumpFile: string;
  private tempDbFile: string;
  private localDb: BunDatabase | null = null;
  private orgId: string;
  private mainDb: Database;
  private tursoService: TursoService;
  private originalDbUrl: string;
  private originalAuthToken: string;

  constructor(orgId: string) {
    this.orgId = orgId;
    this.mainDb = new Database();
    this.tursoService = new TursoService();
    this.tempDumpFile = `dump-${Date.now()}-${nanoid()}.sql`;
    this.tempDbFile = `temp-${Date.now()}-${nanoid()}.db`;
  }

  /**
   * Acquire lock and download the existing database
   */
  async initialize(): Promise<void> {
    logger.info(`[LocalDbOp] Initializing for org ${this.orgId}`);
    
    // Claim the provisioning lock to prevent concurrent operations
    const claimResult = await this.mainDb.execute(
      `UPDATE organizations
       SET is_db_provisioning = 1
       WHERE id = ? AND is_db_provisioning = 0`,
      [this.orgId]
    );

    if (claimResult.rowsAffected === 0) {
      throw new Error('Another operation is already in progress for this organization');
    }

    try {
      // Get the org db url / auth token
      const orgData = await this.mainDb.fetchOne<{ turso_db_url: string, turso_auth_token: string }>(
        'SELECT turso_db_url, turso_auth_token FROM organizations WHERE id = ?',
        [this.orgId]
      );

      if (!orgData || !orgData.turso_db_url || !orgData.turso_auth_token) {
        throw new Error(`Could not get database configuration for organization ${this.orgId}`);
      }

      this.originalDbUrl = orgData.turso_db_url;
      this.originalAuthToken = orgData.turso_auth_token;

      // Download the existing database from Turso
      logger.info(`[LocalDbOp] Downloading existing database from Turso for org ${this.orgId}`);
      const dumpContent = await this.tursoService.downloadDatabaseDump(this.originalDbUrl, this.originalAuthToken);
      logger.info(`[LocalDbOp] Downloaded ${dumpContent.length} bytes of database dump`);

      // Write dump to temporary file
      await fsPromises.writeFile(this.tempDumpFile, dumpContent);

      // Use sqlite3 CLI to create and populate the database
      logger.info('[LocalDbOp] Creating temporary database from dump...');
      await new Promise((resolve, reject) => {
        const sqlite = Bun.spawn(['sqlite3', this.tempDbFile], {
          stdin: Bun.file(this.tempDumpFile),
          onExit(proc, exitCode, signalCode, error) {
            if (exitCode === 0) {
              resolve(null);
            } else {
              reject(new Error(`SQLite process exited with code ${exitCode}: ${error}`));
            }
          }
        });
      });

      logger.info('[LocalDbOp] Successfully created temporary database from dump');

      // Connect to the temporary database using BunSQLite
      this.localDb = new BunDatabase(this.tempDbFile);
      this.localDb.exec('PRAGMA journal_mode = DELETE');
      this.localDb.exec('PRAGMA foreign_keys = ON');

      logger.info(`[LocalDbOp] Connected to local database for org ${this.orgId}`);
    } catch (error) {
      // Release lock on error
      await this.releaseLock();
      throw error;
    }
  }

  /**
   * Get the local database instance for operations
   */
  getLocalDb(): BunDatabase {
    if (!this.localDb) {
      throw new Error('Local database not initialized. Call initialize() first.');
    }
    return this.localDb;
  }

  /**
   * Commit changes by uploading to new Turso database and updating main db
   */
  async commit(): Promise<void> {
    if (!this.localDb) {
      throw new Error('Local database not initialized');
    }

    try {
      logger.info(`[LocalDbOp] Committing changes for org ${this.orgId}`);

      // Force a checkpoint to ensure all changes are written to disk
      this.localDb.exec('PRAGMA wal_checkpoint(TRUNCATE)');

      // Close the database to ensure all changes are flushed
      this.localDb.close();
      this.localDb = null;

      // Create new database and upload data
      logger.info(`[LocalDbOp] Creating new Turso database for org ${this.orgId}`);
      const { dbName: newOrgDbName, url: newOrgDbUrl, token: newOrgDbToken } = await this.tursoService.createDatabaseForImport(this.orgId);
      
      // Upload the local db to the new org db
      logger.info(`[LocalDbOp] Uploading data to new Turso database at ${newOrgDbUrl}`);
      await this.tursoService.uploadDatabase(newOrgDbName, newOrgDbToken, `file:${this.tempDbFile}`);
      
      // Update main db with new org db url / auth token 
      logger.info(`[LocalDbOp] Updating organization ${this.orgId} with new database credentials`);
      await this.mainDb.execute(`
        UPDATE organizations 
        SET turso_db_url = ?, turso_auth_token = ?, is_db_provisioning = 0
        WHERE id = ?
      `, [newOrgDbUrl, newOrgDbToken, this.orgId]);
      
      logger.info(`[LocalDbOp] Successfully committed changes for organization ${this.orgId}`);
    } catch (error) {
      await this.releaseLock();
      throw error;
    }
  }

  /**
   * Release the provisioning lock
   */
  async releaseLock(): Promise<void> {
    try {
      await this.mainDb.execute(
        'UPDATE organizations SET is_db_provisioning = 0 WHERE id = ?',
        [this.orgId]
      );
      logger.info(`[LocalDbOp] Released provisioning lock for org ${this.orgId}`);
    } catch (error) {
      logger.error(`[LocalDbOp] Error releasing lock for org ${this.orgId}: ${error}`);
    }
  }

  /**
   * Clean up temporary files
   */
  async cleanup(): Promise<void> {
    try {
      if (this.localDb) {
        this.localDb.close();
        this.localDb = null;
      }
      
      if (fs.existsSync(this.tempDumpFile)) {
        await fsPromises.unlink(this.tempDumpFile);
      }
      
      if (fs.existsSync(this.tempDbFile)) {
        await fsPromises.unlink(this.tempDbFile);
      }
      
      logger.info(`[LocalDbOp] Cleaned up temporary files for org ${this.orgId}`);
    } catch (error) {
      logger.error(`[LocalDbOp] Error cleaning up temporary files for org ${this.orgId}: ${error}`);
    }
  }

  /**
   * Execute the full operation with proper cleanup
   * This is the main method to use for operations that need the download-modify-upload pattern
   */
  static async execute<T>(
    orgId: string, 
    operation: (localDb: BunDatabase) => Promise<T>
  ): Promise<T> {
    const dbOp = new LocalDatabaseOperation(orgId);
    
    try {
      await dbOp.initialize();
      const result = await operation(dbOp.getLocalDb());
      await dbOp.commit();
      return result;
    } finally {
      await dbOp.cleanup();
    }
  }
}