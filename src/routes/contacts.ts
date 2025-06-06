import { Elysia, t } from 'elysia';
import { Database } from '../database';
import { logger } from '../logger';
import { validateSession, getUserFromSession } from '../services/auth';
import fs from 'fs';
import path from 'path';
import { stringify } from 'csv-stringify/sync';
import { nanoid } from 'nanoid';
import { ZIP_DATA } from '../index';
import { TursoService } from '../services/turso';
import { TURSO_CONFIG } from '../config/turso';
import fetch from 'node-fetch';
import { 
  trackContact, 
  trackContactBatch, 
  getContactUsageStats, 
  getUniqueContactCount,
  resetContactCount
} from '../services/contactTracking';

type User = {
  id: number;
  organization_id: number;
  is_admin: boolean;
};

interface ContactImport {
  first_name: string;
  last_name: string;
  email: string;
  phone_number: string;
  state?: string;
  current_carrier: string;
  effective_date: string;
  birth_date: string;
  tobacco_user: boolean;
  gender: string;
  zip_code: string;
  plan_type: string;
}

type BulkImportRequest = {
  contacts: ContactImport[];
  overwriteExisting: boolean;
  agentId?: number | null;
};

interface Contact {
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  phone_number?: string;
  state: string;
  current_carrier?: string;
  effective_date: string;
  birth_date: string;
  tobacco_user: number;
  gender: string;
  zip_code: string;
  plan_type?: string;
  agent_id?: number;
  last_emailed?: string;
  created_at: string;
  updated_at: string;
  status?: string;
}

type Context = {
  request: Request;
  user: User;
  set: { status: number };
};

function normalizeEmail(email: string): string {
    return email.trim().toLowerCase();
}

/**
 * Contacts API endpoints
 */
export const contactsRoutes = new Elysia({ prefix: '/api/contacts' })
  .use(app => app
    .derive(async ({ request, set }) => {
      const sessionCookie = request.headers.get('cookie')?.split(';')
        .find(c => c.trim().startsWith('session='))
        ?.split('=')[1];

      if (!sessionCookie) {
        set.status = 401;
        return { error: 'Not authorized' };
      }

      const user = await validateSession(sessionCookie);
      if (!user) {
        set.status = 401;
        return { error: 'Not authorized' };
      }

      return { user };
    })
  )
  .get('/', async ({ request, user, set }: Context) => {
    if (!user || !user.organization_id) {
      set.status = 401;
      return { error: 'Not authorized' };
    }

    try {
      // Parse query parameters
      const url = new URL(request.url);
      const page = parseInt(url.searchParams.get('page') || '1');
      const limit = parseInt(url.searchParams.get('limit') || '100');
      const search = url.searchParams.get('search') || '';
      const states = url.searchParams.get('states')?.split(',').filter(Boolean) || [];
      const carriers = url.searchParams.get('carriers')?.split(',').filter(Boolean) || [];
      const agents = url.searchParams.get('agents')?.split(',').map(Number).filter(Boolean) || [];

      logger.info(`Fetching contacts for org ${user.organization_id} - page: ${page}, limit: ${limit}, search: ${search || 'none'}, states: ${states.length ? states.join(',') : 'none'}, carriers: ${carriers.length ? carriers.join(',') : 'none'}, agents: ${agents.length ? agents.join(',') : 'none'}`);

      // For read operations, we can still use the direct database connection approach
      // since we're not modifying data and want better performance
      let orgDb;
      try {
        orgDb = await Database.getOrgDb(user.organization_id.toString());
      } catch (error) {
        logger.error(`Error getting org database: ${error}`);
        set.status = 500;
        return { error: 'Database connection failed' };
      }

      // ... keep the rest of the GET route logic the same since it's read-only ...
      
      // Fetch organization's default_agent_id
      let orgDefaultAgentId: number | null = null;
      const mainDb = new Database(); // Main database instance
      try {
        const orgData = await mainDb.fetchOne<{ default_agent_id: number }>(
            'SELECT default_agent_id FROM organizations WHERE id = ?',
            [user.organization_id]
        );
        if (orgData && orgData.default_agent_id) {
            orgDefaultAgentId = orgData.default_agent_id;
            logger.info(`Organization ${user.organization_id} default agent ID: ${orgDefaultAgentId}`);
        } else {
            logger.info(`Organization ${user.organization_id} has no default agent ID configured.`);
        }
      } catch (dbError) {
        logger.error(`Failed to fetch default_agent_id for org ${user.organization_id}: ${dbError}`);
      }

      // Build base query parts
      let whereConditions = ['1=1'];
      let params: any[] = [];

      // Add search condition if present
      if (search) {
        const searchTerms = search.trim().split(/\s+/);
        
        if (searchTerms.length === 1) {
          // Single word search - check each column individually
          whereConditions.push('(first_name LIKE ? OR last_name LIKE ? OR email LIKE ? OR phone_number LIKE ?)');
          params.push(`%${search}%`, `%${search}%`, `%${search}%`, `%${search}%`);
        } else {
          // Multi-word search - treat first word as first name and remaining words as last name
          const firstName = searchTerms[0];
          const lastName = searchTerms.slice(1).join(' ');
          
          whereConditions.push('((first_name LIKE ? AND last_name LIKE ?) OR first_name LIKE ? OR last_name LIKE ? OR email LIKE ? OR phone_number LIKE ?)');
          params.push(
            `%${firstName}%`, `%${lastName}%`, // Combined name search
            `%${search}%`, `%${search}%`, // Full search term in either name field
            `%${search}%`, `%${search}%` // Email and phone
          );
        }
      }

      // Add state filter
      if (states.length > 0) {
        const zipCodesForStates = Object.entries(ZIP_DATA)
          .filter(([_, info]) => states.includes(info.state))
          .map(([zipCode]) => zipCode);
        whereConditions.push(`zip_code IN (${zipCodesForStates.map(() => '?').join(',')})`);
        params.push(...zipCodesForStates);
      }

      // Add carrier filter
      if (carriers.length > 0) {
        whereConditions.push(`(${carriers.map(() => 'current_carrier LIKE ?').join(' OR ')})`);
        params.push(...carriers.map(c => `%${c}%`));
      }

      // Add agent filter
      if (agents.length > 0) {
        const agentFilterConditions: string[] = [];
        const agentFilterParams: any[] = [];

        // Add condition for explicitly selected agent IDs
        agentFilterConditions.push(`agent_id IN (${agents.map(() => '?').join(',')})`);
        agentFilterParams.push(...agents);

        // If the organization's default agent is among the selected agents, also include unassigned contacts
        if (orgDefaultAgentId !== null && agents.includes(orgDefaultAgentId)) {
            agentFilterConditions.push('agent_id IS NULL');
        }
        
        if (agentFilterConditions.length > 0) {
            whereConditions.push(`(${agentFilterConditions.join(' OR ')})`);
            params.push(...agentFilterParams);
        }
      }

      // Combine conditions
      const whereClause = whereConditions.join(' AND ');

      // First get total count
      const countQuery = `SELECT COUNT(*) as total FROM contacts WHERE ${whereClause}`;
      const countResult = await orgDb.fetchOne<{ total: number }>(countQuery, params);
      let total = countResult?.total || 0;

      // Then get paginated results
      const offset = (page - 1) * limit;
      const selectQuery = `
        SELECT 
          COALESCE(id, rowid) as id,
          first_name, last_name, email, phone_number, state,
          current_carrier, effective_date, birth_date, tobacco_user,
          gender, zip_code, plan_type, agent_id, last_emailed,
          created_at, updated_at, status
        FROM contacts 
        WHERE ${whereClause}
        ORDER BY created_at DESC 
        LIMIT ? OFFSET ?`;
      
      const contacts = await orgDb.query<Contact>(selectQuery, [...params, limit, offset]);

      // Get filter options
      const carrierQuery = `SELECT DISTINCT current_carrier FROM contacts WHERE ${whereClause} AND current_carrier IS NOT NULL ORDER BY current_carrier`;
      const zipQuery = `SELECT DISTINCT zip_code FROM contacts WHERE ${whereClause} AND zip_code IS NOT NULL ORDER BY zip_code`;
      
      const [carrierRows, zipRows] = await Promise.all([
        orgDb.query<{current_carrier: string}>(carrierQuery, params),
        orgDb.query<{zip_code: string}>(zipQuery, params)
      ]);

      // Get unique states from zip codes using ZIP_DATA
      const uniqueStates = zipRows
        .map(row => {
          const zipInfo = ZIP_DATA[row.zip_code];
          return zipInfo?.state;
        })
        .filter((state): state is string => state !== undefined)
        .filter((value, index, self) => self.indexOf(value) === index)
        .sort();
      
      const filterOptions = {
        carriers: carrierRows.map(row => row.current_carrier).filter(Boolean),
        states: uniqueStates
      };

      // Map contacts to expected format
      const mappedContacts = contacts.map(contact => {
        const zipInfo = ZIP_DATA[contact.zip_code];
        const state = zipInfo?.state || contact.state;

        return {
          id: contact.id || 0,
          first_name: contact.first_name,
          last_name: contact.last_name,
          email: contact.email,
          phone_number: contact.phone_number || '',
          state: state,
          current_carrier: contact.current_carrier,
          effective_date: contact.effective_date,
          birth_date: contact.birth_date,
          tobacco_user: Boolean(contact.tobacco_user),
          gender: contact.gender,
          zip_code: contact.zip_code,
          plan_type: contact.plan_type,
          agent_id: contact.agent_id,
          last_emailed: contact.last_emailed,
          status: contact.status || 'New'
        };
      });

      const response = {
        contacts: mappedContacts,
        filterOptions,
        total,
        page,
        limit
      };

      return response;

    } catch (error) {
      logger.error(`Error fetching contacts: ${error}`);
      set.status = 500;
      return { error: 'Failed to fetch contacts' };
    }
  })
  // ... keep bulk import and tracking routes the same since they already use bulk patterns ...
  
  // Add new POST endpoint for single contact creation/update using LocalDatabaseOperation
  .post('', 
    async ({ body, user, set }: { body: any; user: User; set: { status: number } }) => {
      if (!user || !user.organization_id) {
        set.status = 401;
        return { success: false, message: 'Not authorized' };
      }

      const contactData = body as ContactImport;

      if (!contactData || !contactData.email) {
        set.status = 400;
        return { success: false, message: 'Invalid contact data: email is required' };
      }

      try {
        // Use the new LocalDatabaseOperation pattern for data modification
        const result = await Database.createOrUpdateContact(user.organization_id.toString(), {
          first_name: contactData.first_name,
          last_name: contactData.last_name,
          email: contactData.email,
          phone_number: contactData.phone_number,
          state: contactData.state,
          current_carrier: contactData.current_carrier,
          effective_date: contactData.effective_date,
          birth_date: contactData.birth_date,
          tobacco_user: contactData.tobacco_user,
          gender: contactData.gender,
          zip_code: contactData.zip_code,
          plan_type: contactData.plan_type,
          agent_id: user.id // Use the creating user's ID as agent_id
        });

        return result;
      } catch (error) {
        logger.error(`Error creating/updating contact: ${error}`);
        set.status = 500;
        return { success: false, message: 'Failed to create/update contact' };
      }
    },
    {
      body: t.Object({
        first_name: t.String(),
        last_name: t.String(),
        email: t.String({ format: 'email' }),
        phone_number: t.Optional(t.String()),
        state: t.Optional(t.String()),
        current_carrier: t.Optional(t.String()),
        effective_date: t.Optional(t.String()),
        birth_date: t.Optional(t.String()),
        tobacco_user: t.Optional(t.Boolean()),
        gender: t.Optional(t.String()),
        zip_code: t.Optional(t.String()),
        plan_type: t.Optional(t.String())
      })
    }
  )
  // Update DELETE endpoint to use LocalDatabaseOperation
  .delete('/', 
    async ({ body, set, request }) => {
      try {
        const user = await getUserFromSession(request);
        if (!user || 'skip_auth' in user || !user.organization_id) {
          set.status = 401;
          return { error: 'Not authorized' };
        }

        const contactIdsToDelete = body as number[];
        if (!Array.isArray(contactIdsToDelete) || contactIdsToDelete.length === 0) {
          set.status = 400;
          return { error: 'No contact IDs provided' };
        }
        
        logger.info(`DELETE /api/contacts - Attempting to delete ${contactIdsToDelete.length} contacts for org ${user.organization_id}`);
        
        // Use the new LocalDatabaseOperation pattern for data modification
        const result = await Database.deleteContacts(user.organization_id.toString(), contactIdsToDelete);

        if (result.failed_to_move_ids.length > 0) {
          set.status = result.deleted_ids.length > 0 ? 207 : 500; // 207 Multi-Status or 500 Internal Server Error
        }

        return result;

      } catch (e) {
        logger.error(`Error processing delete contacts request: ${e}`);
        set.status = 500;
        return { error: e instanceof Error ? e.message : 'Failed to delete contacts' };
      }
    },
    {
      body: t.Array(t.Number())
    }
  )