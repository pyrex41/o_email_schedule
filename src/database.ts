import { createClient } from '@libsql/client'
import { config } from './config'
import { logger } from './logger'
import { TursoService } from './services/turso'
import { Database as BunDatabase } from 'bun:sqlite'
import fs from 'fs'
import path from 'path'
import { parse } from 'csv-parse'
import { pipeline } from 'stream/promises'
import fetch, { Response } from 'node-fetch'
import type { RequestInit, RequestInfo, BodyInit } from 'node-fetch'
import type { ContactCreate } from './types'
import { LocalDatabaseOperation } from './services/localDatabaseOperation'

import fsPromises from 'fs/promises'
import Bun from 'bun'
import { ZIP_DATA } from './index' // Import ZIP_DATA for state lookup

// Connection pool to reuse database connections
interface ConnectionInfo {
  client: any;
  url: string;
  lastUsed: number;
}

class ConnectionPool {
  private static instance: ConnectionPool;
  private connections: Map<string, ConnectionInfo> = new Map();
  private readonly MAX_IDLE_TIME = 60000; // 60 seconds max idle time
  private readonly MAX_POOL_SIZE = 20; // Maximum connections to keep in the pool
  private cleanupInterval: any;

  private constructor() {
    // Start the cleanup interval to remove idle connections
    this.cleanupInterval = setInterval(() => this.cleanupIdleConnections(), 30000);
  }

  public static getInstance(): ConnectionPool {
    if (!ConnectionPool.instance) {
      ConnectionPool.instance = new ConnectionPool();
    }
    return ConnectionPool.instance;
  }

  public getConnection(url: string, authToken: string): any {
    // Check if we have a connection for this URL
    if (this.connections.has(url)) {
      const conn = this.connections.get(url)!;
      conn.lastUsed = Date.now();
      return conn.client;
    }

    // If we've reached max pool size, remove the oldest connection
    if (this.connections.size >= this.MAX_POOL_SIZE) {
      let oldestTime = Infinity;
      let oldestUrl = '';
      
      for (const [connUrl, conn] of this.connections.entries()) {
        if (conn.lastUsed < oldestTime) {
          oldestTime = conn.lastUsed;
          oldestUrl = connUrl;
        }
      }
      
      if (oldestUrl) {
        logger.info(`Connection pool: removing oldest connection ${oldestUrl}`);
        this.connections.delete(oldestUrl);
      }
    }

    // Create a new connection
    logger.info(`Creating new Turso connection for ${url}`);
    const client = createClient({
      url,
      authToken,
      concurrency: 25, // Lower concurrency to prevent rate limits
      fetch: async (fetchUrl: RequestInfo, options: RequestInit) => {
        // Add custom fetch with retry for 429 errors
        const maxRetries = 3;
        for (let attempt = 0; attempt < maxRetries; attempt++) {
          try {
            const response = await fetch(fetchUrl, options);
            if (response.status === 429) {
              // Rate limited, wait with exponential backoff
              const delay = Math.pow(2, attempt) * 1000;
              logger.warn(`Rate limit hit in Turso API call, retry ${attempt+1}/${maxRetries} after ${delay}ms`);
              await new Promise(resolve => setTimeout(resolve, delay));
              continue;
            }
            return response;
          } catch (error) {
            if (attempt === maxRetries - 1) throw error;
            const delay = Math.pow(2, attempt) * 1000;
            logger.warn(`Error in Turso API call, retry ${attempt+1}/${maxRetries} after ${delay}ms: ${error}`);
            await new Promise(resolve => setTimeout(resolve, delay));
          }
        }
        throw new Error('Max retries reached for Turso API call');
      }
    });

    // Store in the pool
    this.connections.set(url, {
      client,
      url,
      lastUsed: Date.now()
    });

    return client;
  }

  private cleanupIdleConnections() {
    const now = Date.now();
    let cleanedCount = 0;
    
    for (const [url, conn] of this.connections.entries()) {
      if (now - conn.lastUsed > this.MAX_IDLE_TIME) {
        this.connections.delete(url);
        cleanedCount++;
      }
    }
    
    if (cleanedCount > 0) {
      logger.info(`Connection pool: cleaned up ${cleanedCount} idle connections, remaining: ${this.connections.size}`);
    }
  }

  public shutdown() {
    clearInterval(this.cleanupInterval);
    this.connections.clear();
  }
}

type ColumnMapping = {
  firstName: string;
  lastName: string;
  email: string;
  phoneNumber: string;
  state?: string; // Make state optional since we'll infer it from zip code
  currentCarrier: string;
  effectiveDate: string;
  birthDate: string;
  tobaccoUser: string;
  gender: string;
  zipCode: string;
  planType: string;
};

type CarrierMapping = {
  detectedCarriers: string[];
  mappings: Record<string, string>;
};

interface FetchOptions extends RequestInit {
  method?: string;
  headers?: Record<string, string>;
  body?: BodyInit;
}

export class Database {
  private client: any
  private url: string
  private isLocal: boolean
  private bunDb: BunDatabase | null = null

  public static normalizeDbUrl(url: string): { hostname: string, apiUrl: string, dbUrl: string, dbName: string } {
    // Strip any protocol prefix
    const hostname = url.replace(/(^https?:\/\/)|(^libsql:\/\/)/, '');
    const dbName = hostname.split('/').pop()?.split('.')[0] || '';
    return {
      hostname,  // Raw hostname without protocol
      apiUrl: `https://${hostname}`,  // For API calls
      dbUrl: `libsql://${hostname}`,   // For database connections
      dbName // For local SQLite files
    };
  }

  constructor(dbUrl?: string, authToken?: string) {
    const url = dbUrl || config.TURSO_DATABASE_URL
    const token = authToken || config.TURSO_AUTH_TOKEN

    if (!url) {
      logger.error('Missing database URL')
      throw new Error('Missing database URL')
    }

    const { dbUrl: normalizedUrl, dbName } = Database.normalizeDbUrl(url)
    this.url = normalizedUrl
    this.isLocal = config.USE_LOCAL_SQLITE

    if (this.isLocal) {
      const dbPath = path.join(process.cwd(), config.LOCAL_DB_PATH, `${dbName}.sqlite`)
      logger.info(`Using local SQLite database at: ${dbPath}`)
      
      // Create directory if it doesn't exist
      const dbDir = path.dirname(dbPath)
      if (!fs.existsSync(dbDir)) {
        fs.mkdirSync(dbDir, { recursive: true })
      }
      
      this.bunDb = new BunDatabase(dbPath)
      this.client = this.bunDb
      
      // Enable foreign keys
      this.bunDb.exec('PRAGMA foreign_keys = ON;')
    } else {
      if (!token) {
        logger.error('Missing database token')
        throw new Error('Missing database token')
      }
      this.client = createClient({
        url: normalizedUrl,
        authToken: token,
        concurrency: 25, // Reduced concurrency to prevent rate limits
        fetch: async (fetchUrl: RequestInfo, options: RequestInit) => {
          // Add custom fetch with retry for 429 errors
          const maxRetries = 3;
          for (let attempt = 0; attempt < maxRetries; attempt++) {
            try {
              const response = await fetch(fetchUrl, options);
              if (response.status === 429) {
                // Rate limited, wait with exponential backoff
                const delay = Math.pow(2, attempt) * 1000;
                logger.warn(`Rate limit hit in Turso API call, retry ${attempt+1}/${maxRetries} after ${delay}ms`);
                await new Promise(resolve => setTimeout(resolve, delay));
                continue;
              }
              return response;
            } catch (error) {
              if (attempt === maxRetries - 1) throw error;
              const delay = Math.pow(2, attempt) * 1000;
              logger.warn(`Error in Turso API call, retry ${attempt+1}/${maxRetries} after ${delay}ms: ${error}`);
              await new Promise(resolve => setTimeout(resolve, delay));
            }
          }
          throw new Error('Max retries reached for Turso API call');
        }
      })
    }
    
    logger.info(`Database connected to: ${this.isLocal ? dbName : this.url}`)
  }

  static async getOrgDb(orgId: string): Promise<Database> {
    logger.info(`Getting org database for org ${orgId}`);
    const mainDb = new Database();
    
    try {
      const org = await mainDb.fetchOne<{ turso_db_url: string; turso_auth_token: string }>(
        'SELECT turso_db_url, turso_auth_token FROM organizations WHERE id = ?',
        [orgId]
      );
      logger.info(`[OrgDB] Organization record: ${JSON.stringify(org)}`);

      if (!org) {
        logger.warn(`[OrgDB] Organization record not found for orgId: ${orgId}`);
        throw new Error('Organization database not configured');
      }
      if (!org.turso_db_url) {
        logger.warn(`[OrgDB] No turso_db_url found in organization record for orgId: ${orgId}. Record: ${JSON.stringify(org)}`);
        throw new Error('Organization database not configured');
      }
      if (!org.turso_auth_token) {
        logger.warn(`[OrgDB] No turso_auth_token found in organization record for orgId: ${orgId}. Record: ${JSON.stringify(org)}`);
        throw new Error('Organization database not configured (missing token)');
      }

      logger.info(`[OrgDB] Found credentials for org ${orgId}. URL: ${org.turso_db_url.substring(0, 20)}... Token: ${org.turso_auth_token ? 'present' : 'MISSING'}`);
      const db = new Database(org.turso_db_url, org.turso_auth_token);

      // Validate connection by running a simple query with timeout
      logger.info(`[OrgDB] Validating database connection for org ${orgId}...`);
      try {
        const timeoutPromise = new Promise((_, reject) => {
          setTimeout(() => reject(new Error('Database validation timed out after 5 seconds')), 5000);
        });
        
        const queryPromise = db.execute('SELECT 1');
        
        const result = await Promise.race([queryPromise, timeoutPromise]);
        logger.info(`Database connection validation successful for org ${orgId}. Result: ${JSON.stringify(result)}`);
        return db;
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : String(error);
        logger.error(`Database connection validation failed for org ${orgId}. Error: ${errorMessage}`);
        if (error instanceof Error && error.stack) {
          logger.error(`Stack trace: ${error.stack}`);
        }
        throw new Error(`Failed to establish database connection: ${errorMessage}`);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      logger.error(`Error getting org database for org ${orgId}: ${errorMessage}`);
      if (error instanceof Error && error.stack) {
        logger.error(`Stack trace: ${error.stack}`);
      }
      throw error;
    }
  }

  getClient() {
    return this.client
  }

  async execute(sql: string, args: any[] = []) {
    try {
      if (this.isLocal && this.bunDb) {
        // For local SQLite
        const stmt = this.bunDb.prepare(sql)
        const result = stmt.run(...args)
        return {
          rows: Array.isArray(result) ? result : result.changes > 0 ? [result] : [],
          rowsAffected: result.changes
        }
      } else {
        // For Turso
        const result = await this.client.execute({
          sql,
          args
        })
        return result
      }
    } catch (error) {
      logger.error(`Database execute error: ${error}`)
      throw error
    }
  }
  
  async batch(statements: { sql: string, args: any[] }[], mode: 'read' | 'write' = 'write') {
    try {
      if (this.isLocal && this.bunDb) {
        // For local SQLite, implement batch manually with transaction
        this.bunDb.exec('BEGIN TRANSACTION');
        const results = [];
        
        try {
          for (const { sql, args } of statements) {
            const stmt = this.bunDb.prepare(sql);
            const result = stmt.run(...args);
            results.push({
              rows: Array.isArray(result) ? result : result.changes > 0 ? [result] : [],
              rowsAffected: result.changes
            });
          }
          
          this.bunDb.exec('COMMIT');
          return results;
        } catch (error) {
          this.bunDb.exec('ROLLBACK');
          throw error;
        }
      } else {
        // For Turso, use native batch support
        const batchStatements = statements.map(({ sql, args }) => ({
          sql,
          args: args || []
        }));
        
        return await this.client.batch(batchStatements, mode);
      }
    } catch (error) {
      logger.error(`Database batch error: ${error}`);
      throw error;
    }
  }

  async fetchAll(sql: string, args: any[] = []) {
    try {
      if (this.isLocal && this.bunDb) {
        // For local SQLite
        const stmt = this.bunDb.prepare(sql)
        const rows = stmt.all(...args)
        return rows || []
      } else {
        // For Turso
        const result = await this.client.execute({
          sql,
          args
        })
        return result.rows || []
      }
    } catch (error) {
      logger.error(`Database fetchAll error: ${error}`)
      throw error
    }
  }

  async fetchOne<T>(sql: string, args: any[] = []): Promise<T | null> {
    if (this.isLocal && this.bunDb) {
      // For local SQLite
      const stmt = this.bunDb.prepare(sql)
      const row = stmt.get(...args)
      return row as T || null
    } else {
      // For Turso
      const result = await this.execute(sql, args)
      if (!result.rows || result.rows.length === 0) return null
      const row = result.rows[0]
      const columns = result.columns || []
      const obj: any = {}
      columns.forEach((col: string, i: number) => (obj[col] = row[i]))
      return obj as T
    }
  }

  async query<T = any>(sql: string, args: any[] = []): Promise<T[]> {
    return this.fetchAll(sql, args)
  }

  close() {
    if (this.isLocal && this.bunDb) {
      this.bunDb.close()
    }
  }

  // Add static methods for operations that should use the LocalDatabaseOperation pattern
  /**
   * Create or update a single contact using the LocalDatabaseOperation pattern
   */
  static async createOrUpdateContact(
    orgId: string,
    contactData: {
      first_name: string;
      last_name: string;
      email: string;
      phone_number?: string;
      state?: string;
      current_carrier?: string;
      effective_date?: string;
      birth_date?: string;
      tobacco_user?: boolean;
      gender?: string;
      zip_code?: string;
      plan_type?: string;
      agent_id?: number;
    }
  ): Promise<{ success: boolean; contactId?: number; message: string }> {
    return LocalDatabaseOperation.execute(orgId, async (localDb) => {
      const normalizedEmail = contactData.email.toLowerCase().trim();

      // Handle re-activation: Remove from deleted_contacts if exists
      localDb.prepare('DELETE FROM deleted_contacts WHERE LOWER(TRIM(email)) = ?').run(normalizedEmail);
      logger.info(`Cleared ${normalizedEmail} from deleted_contacts (if existed) for org ${orgId} during contact creation/update.`);

      // Infer state from zip code if provided
      let inferredState = contactData.state;
      if (contactData.zip_code && ZIP_DATA[contactData.zip_code]) {
        inferredState = ZIP_DATA[contactData.zip_code].state;
      }

      // Use UPSERT to create or update the contact
      const stmt = localDb.prepare(`
        INSERT INTO contacts (
          first_name, last_name, email, phone_number, state, 
          current_carrier, effective_date, birth_date, tobacco_user, 
          gender, zip_code, plan_type, agent_id, created_at, updated_at, status
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'New')
        ON CONFLICT(LOWER(TRIM(email))) DO UPDATE SET
          first_name = excluded.first_name,
          last_name = excluded.last_name,
          phone_number = excluded.phone_number,
          state = excluded.state,
          current_carrier = excluded.current_carrier,
          effective_date = excluded.effective_date,
          birth_date = excluded.birth_date,
          tobacco_user = excluded.tobacco_user,
          gender = excluded.gender,
          zip_code = excluded.zip_code,
          plan_type = excluded.plan_type,
          agent_id = excluded.agent_id,
          updated_at = CURRENT_TIMESTAMP,
          status = CASE WHEN contacts.status = 'Deleted' THEN 'Reactivated' ELSE contacts.status END
      `);

      const result = stmt.run(
        contactData.first_name,
        contactData.last_name,
        normalizedEmail,
        contactData.phone_number || '',
        inferredState || '',
        contactData.current_carrier || '',
        contactData.effective_date || '',
        contactData.birth_date || '',
        contactData.tobacco_user ? 1 : 0,
        contactData.gender || '',
        contactData.zip_code || '',
        contactData.plan_type || '',
        contactData.agent_id || null
      );

      logger.info(`Successfully created/updated contact ${normalizedEmail} for org ${orgId}.`);
      return { 
        success: true, 
        contactId: result.lastInsertRowid as number, 
        message: 'Contact created/updated successfully' 
      };
    });
  }

  /**
   * Delete contacts using the LocalDatabaseOperation pattern
   */
  static async deleteContacts(
    orgId: string, 
    contactIds: number[]
  ): Promise<{ success: boolean; deleted_ids: number[]; failed_to_move_ids: any[]; message: string }> {
    return LocalDatabaseOperation.execute(orgId, async (localDb) => {
      const successfullyMovedIds: number[] = [];
      const failedToMoveIds: any[] = [];

      for (const contactId of contactIds) {
        try {
          // Begin transaction for this contact
          localDb.exec('BEGIN TRANSACTION');

          try {
            // 1. Select the contact from the 'contacts' table
            const contact = localDb.prepare('SELECT * FROM contacts WHERE id = ?').get(contactId) as any;

            if (!contact) {
              logger.warn(`Contact with ID ${contactId} not found in contacts table for org ${orgId}.`);
              failedToMoveIds.push({ id: contactId, error: 'Not found' });
              localDb.exec('ROLLBACK');
              continue;
            }

            const normalizedEmail = contact.email.toLowerCase().trim();

            // 2. Insert into 'deleted_contacts' table
            const insertStmt = localDb.prepare(`
              INSERT INTO deleted_contacts (
                original_contact_id, first_name, last_name, email, phone_number, 
                current_carrier, plan_type, effective_date, birth_date, 
                tobacco_user, gender, state, zip_code, agent_id, status, deleted_at
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            `);

            insertStmt.run(
              contact.id, contact.first_name, contact.last_name, normalizedEmail, contact.phone_number,
              contact.current_carrier, contact.plan_type, contact.effective_date, contact.birth_date,
              contact.tobacco_user, contact.gender, contact.state, contact.zip_code, 
              contact.agent_id, contact.status
            );

            // 3. Delete from 'contacts' table (cascade deletes will handle related tables)
            const deleteStmt = localDb.prepare('DELETE FROM contacts WHERE id = ?');
            deleteStmt.run(contactId);
            
            localDb.exec('COMMIT');
            successfullyMovedIds.push(contactId);
            logger.info(`Successfully moved contact ID ${contactId} to deleted_contacts for org ${orgId}`);
          } catch (error) {
            localDb.exec('ROLLBACK');
            throw error;
          }
        } catch (e) {
          logger.error(`Error moving contact ID ${contactId} to deleted_contacts: ${e}`);
          failedToMoveIds.push({ id: contactId, error: e instanceof Error ? e.message : String(e) });
        }
      }

      const responseMessage = `Moved ${successfullyMovedIds.length} contacts. Failed to move ${failedToMoveIds.length} contacts.`;
      logger.info(`Delete contacts result for org ${orgId}: ${responseMessage}`);

      return {
        success: successfullyMovedIds.length > 0,
        deleted_ids: successfullyMovedIds,
        failed_to_move_ids: failedToMoveIds,
        message: responseMessage
      };
    });
  }
}

export const db = new Database()

/**
 * Get user from session cookie
 */
export async function getUserFromSession(request: any): Promise<any> {
  try {
    const db = new Database();
    let sessionCookie: string | undefined;

    // Handle different request header formats
    if (request.headers) {
      if (typeof request.headers.get === 'function') {
        // Standard Request object
        sessionCookie = request.headers.get('cookie')?.split(';')
          .find((c: string) => c.trim().startsWith('session='))
          ?.split('=')[1];
      } else if (typeof request.headers === 'object') {
        // Raw headers object or Express request
        const cookieHeader = request.headers.cookie || request.headers['cookie'] || request.headers['Cookie'];
        if (typeof cookieHeader === 'string') {
          sessionCookie = cookieHeader.split(';')
            .find((c: string) => c.trim().startsWith('session='))
            ?.split('=')[1];
        }
      }
    }

    if (!sessionCookie) {
      logger.info('No session cookie found');
      return null;
    }

    const session = await db.fetchOne<{ id: string, user_id: number, expires_at: string, created_at: string }>(
      'SELECT * FROM sessions WHERE id = ?',
      [sessionCookie]
    );

    if (!session) {
      logger.info('No valid session found');
      return null;
    }

    // Check if session has expired
    const expiresAt = new Date(session.expires_at);
    const now = new Date();
    
    if (expiresAt < now) {
      logger.info('Session has expired');
      return null;
    }

    // Get the user associated with the session
    const user = await db.fetchOne(
      'SELECT u.*, o.name as organization_name FROM users u JOIN organizations o ON u.organization_id = o.id WHERE u.id = ?',
      [session.user_id]
    );

    if (!user) {
      logger.info('No user found for session');
      return null;
    }
    
    return user;
  } catch (error) {
    logger.error(`Error getting user from session: ${error}`);
    return null;
  }
}

export async function getOrganizationById(orgId: number): Promise<any> {
  try {
    const db = new Database();
    const org = await db.query('SELECT * FROM organizations WHERE id = ?', [orgId]);
    if (!org || org.length === 0) return null;
    return org[0];
  } catch (error) {
    logger.error(`Error getting organization: ${error}`);
    return null;
  }
}