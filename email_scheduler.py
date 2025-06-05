#!/usr/bin/env python3
"""
Email Scheduling System

Implements comprehensive email scheduling business logic including:
- Anniversary-based emails (birthday, effective_date, AEP, post_window)
- Campaign system with types and instances
- State-based exclusion windows
- Load balancing and smoothing
- Follow-up email scheduling
"""

import sqlite3
import json
import logging
from datetime import datetime, date, timedelta
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass
from collections import defaultdict
import hashlib
import uuid
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class Contact:
    id: int
    email: str
    state: str
    zip_code: str
    birth_date: Optional[str]
    effective_date: Optional[str]

@dataclass
class StateRule:
    rule_type: str  # 'birthday_window', 'effective_date_window', 'year_round'
    window_before: int
    window_after: int
    use_month_start: bool = False

@dataclass
class CampaignType:
    name: str
    respect_exclusion_windows: bool
    enable_followups: bool
    days_before_event: int
    target_all_contacts: bool
    priority: int

@dataclass
class CampaignInstance:
    id: int
    campaign_type: str
    instance_name: str
    email_template: Optional[str]
    sms_template: Optional[str]
    active_start_date: Optional[str]
    active_end_date: Optional[str]
    metadata: Optional[str]

@dataclass
class EmailSchedule:
    contact_id: int
    email_type: str
    scheduled_send_date: str
    scheduled_send_time: str
    status: str
    skip_reason: Optional[str]
    priority: int
    campaign_instance_id: Optional[int]
    email_template: Optional[str]
    sms_template: Optional[str]
    scheduler_run_id: str
    event_year: Optional[int]
    event_month: Optional[int] 
    event_day: Optional[int]

class EmailScheduler:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.scheduler_run_id = str(uuid.uuid4())
        
        # Configuration - these should be configurable in real implementation
        self.config = {
            'send_time': '08:30:00',
            'batch_size': 10000,
            'max_emails_per_period': 5,
            'period_days': 30,
            'birthday_email_days_before': 14,
            'effective_date_days_before': 30,
            'pre_window_exclusion_days': 60,
            'aep_month': 9,
            'aep_day': 15,
            'daily_send_percentage_cap': 0.07,
            'ed_daily_soft_limit': 15,
            'ed_smoothing_window_days': 5,
            'catch_up_spread_days': 7,
            'overage_threshold': 1.2
        }
        
        # State rules - should be loaded from configuration
        self.state_rules = {
            'CA': StateRule('birthday_window', 30, 60),
            'ID': StateRule('birthday_window', 0, 63),
            'KY': StateRule('birthday_window', 0, 60),
            'MD': StateRule('birthday_window', 0, 30),
            'NV': StateRule('birthday_window', 0, 60, use_month_start=True),
            'OK': StateRule('birthday_window', 0, 60),
            'OR': StateRule('birthday_window', 0, 31),
            'VA': StateRule('birthday_window', 0, 30),
            'MO': StateRule('effective_date_window', 30, 33),
            'CT': StateRule('year_round', 0, 0),
            'MA': StateRule('year_round', 0, 0),
            'NY': StateRule('year_round', 0, 0),
            'WA': StateRule('year_round', 0, 0)
        }
        
    def init_database_schema(self):
        """Initialize or update database schema with required tables and columns"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Create campaign_types table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS campaign_types (
                    name TEXT PRIMARY KEY,
                    respect_exclusion_windows BOOLEAN DEFAULT TRUE,
                    enable_followups BOOLEAN DEFAULT TRUE,
                    days_before_event INTEGER DEFAULT 0,
                    target_all_contacts BOOLEAN DEFAULT FALSE,
                    priority INTEGER DEFAULT 10,
                    active BOOLEAN DEFAULT TRUE,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            
            # Create campaign_instances table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS campaign_instances (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    campaign_type TEXT NOT NULL,
                    instance_name TEXT NOT NULL,
                    email_template TEXT,
                    sms_template TEXT,
                    active_start_date DATE,
                    active_end_date DATE,
                    metadata TEXT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(campaign_type, instance_name),
                    FOREIGN KEY (campaign_type) REFERENCES campaign_types(name)
                )
            """)
            
            # Create contact_campaigns table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS contact_campaigns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    contact_id INTEGER NOT NULL,
                    campaign_instance_id INTEGER NOT NULL,
                    trigger_date DATE,
                    status TEXT DEFAULT 'pending',
                    metadata TEXT,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                    UNIQUE(contact_id, campaign_instance_id, trigger_date),
                    FOREIGN KEY (campaign_instance_id) REFERENCES campaign_instances(id),
                    FOREIGN KEY (contact_id) REFERENCES contacts(id)
                )
            """)
            
            # Add missing columns to email_schedules table
            try:
                cursor.execute("ALTER TABLE email_schedules ADD COLUMN priority INTEGER DEFAULT 10")
            except sqlite3.OperationalError:
                pass  # Column already exists
                
            try:
                cursor.execute("ALTER TABLE email_schedules ADD COLUMN campaign_instance_id INTEGER")
            except sqlite3.OperationalError:
                pass
                
            try:
                cursor.execute("ALTER TABLE email_schedules ADD COLUMN email_template TEXT")
            except sqlite3.OperationalError:
                pass
                
            try:
                cursor.execute("ALTER TABLE email_schedules ADD COLUMN sms_template TEXT")
            except sqlite3.OperationalError:
                pass
                
            try:
                cursor.execute("ALTER TABLE email_schedules ADD COLUMN scheduler_run_id TEXT")
            except sqlite3.OperationalError:
                pass
            
            # Create scheduler checkpoints table
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS scheduler_checkpoints (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    run_timestamp DATETIME NOT NULL,
                    scheduler_run_id TEXT UNIQUE NOT NULL,
                    contacts_checksum TEXT NOT NULL,
                    schedules_before_checksum TEXT,
                    schedules_after_checksum TEXT,
                    contacts_processed INTEGER,
                    emails_scheduled INTEGER,
                    emails_skipped INTEGER,
                    status TEXT NOT NULL,
                    error_message TEXT,
                    completed_at DATETIME
                )
            """)
            
            conn.commit()
            logger.info("Database schema initialized successfully")
    
    def get_next_anniversary_date(self, date_str: str, reference_date: date = None) -> date:
        """Calculate next anniversary from a given date"""
        if not date_str:
            return None
            
        if reference_date is None:
            reference_date = date.today()
            
        try:
            event_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            logger.warning(f"Invalid date format: {date_str}")
            return None
            
        # Calculate this year's anniversary
        try:
            this_year_anniversary = date(reference_date.year, event_date.month, event_date.day)
        except ValueError:
            # Handle Feb 29 in non-leap years
            if event_date.month == 2 and event_date.day == 29:
                this_year_anniversary = date(reference_date.year, 2, 28)
            else:
                raise
                
        # If this year's anniversary has passed, use next year's
        if this_year_anniversary <= reference_date:
            try:
                next_anniversary = date(reference_date.year + 1, event_date.month, event_date.day)
            except ValueError:
                # Handle Feb 29 in non-leap years
                if event_date.month == 2 and event_date.day == 29:
                    next_anniversary = date(reference_date.year + 1, 2, 28)
                else:
                    raise
            return next_anniversary
        else:
            return this_year_anniversary
    
    def calculate_exclusion_window(self, contact: Contact, reference_date: date = None) -> Tuple[Optional[date], Optional[date]]:
        """Calculate exclusion window for a contact based on state rules"""
        if reference_date is None:
            reference_date = date.today()
            
        state_rule = self.state_rules.get(contact.state)
        if not state_rule:
            return None, None
            
        if state_rule.rule_type == 'year_round':
            # Year-round exclusion
            return date(reference_date.year, 1, 1), date(reference_date.year, 12, 31)
            
        elif state_rule.rule_type == 'birthday_window':
            if not contact.birth_date:
                return None, None
                
            anniversary_date = self.get_next_anniversary_date(contact.birth_date, reference_date)
            if not anniversary_date:
                return None, None
                
            # Nevada uses month start
            if state_rule.use_month_start:
                window_center = date(anniversary_date.year, anniversary_date.month, 1)
            else:
                window_center = anniversary_date
                
        elif state_rule.rule_type == 'effective_date_window':
            if not contact.effective_date:
                return None, None
                
            anniversary_date = self.get_next_anniversary_date(contact.effective_date, reference_date)
            if not anniversary_date:
                return None, None
                
            window_center = anniversary_date
            
        else:
            return None, None
            
        # Calculate window with pre-extension
        window_start = window_center - timedelta(days=state_rule.window_before + self.config['pre_window_exclusion_days'])
        window_end = window_center + timedelta(days=state_rule.window_after)
        
        return window_start, window_end
    
    def is_date_in_exclusion_window(self, send_date: date, contact: Contact) -> bool:
        """Check if a send date falls within the contact's exclusion window"""
        window_start, window_end = self.calculate_exclusion_window(contact)
        
        if window_start is None or window_end is None:
            return False
            
        # Handle windows that span years
        if window_start.year != window_end.year:
            # Window spans across years
            return (send_date >= window_start) or (send_date <= window_end)
        else:
            # Window within same year
            return window_start <= send_date <= window_end
    
    def get_contacts_batch(self, limit: int = None) -> List[Contact]:
        """Fetch contacts for processing"""
        if limit is None:
            limit = self.config['batch_size']
            
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, email, state, zip_code, birth_date, effective_date
                FROM contacts 
                WHERE email IS NOT NULL AND email != ''
                AND state IS NOT NULL AND state != ''
                AND zip_code IS NOT NULL AND zip_code != ''
                LIMIT ?
            """, (limit,))
            
            contacts = []
            for row in cursor.fetchall():
                contacts.append(Contact(*row))
                
            return contacts
    
    def clear_existing_schedules(self, contact_ids: List[int]):
        """Clear existing pre-scheduled and skipped emails for contacts"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            placeholders = ','.join('?' * len(contact_ids))
            cursor.execute(f"""
                DELETE FROM email_schedules 
                WHERE status IN ('pre-scheduled', 'skipped')
                AND contact_id IN ({placeholders})
            """, contact_ids)
            
            conn.commit()
            logger.info(f"Cleared existing schedules for {len(contact_ids)} contacts")
    
    def schedule_anniversary_emails(self, contacts: List[Contact]) -> List[EmailSchedule]:
        """Schedule anniversary-based emails (birthday, effective_date, AEP, post_window)"""
        schedules = []
        today = date.today()
        
        for contact in contacts:
            contact_schedules = []
            exclusion_window_start, exclusion_window_end = self.calculate_exclusion_window(contact)
            
            # Birthday emails
            if contact.birth_date:
                birthday_anniversary = self.get_next_anniversary_date(contact.birth_date)
                if birthday_anniversary:
                    send_date = birthday_anniversary - timedelta(days=self.config['birthday_email_days_before'])
                    
                    if send_date >= today:
                        is_excluded = self.is_date_in_exclusion_window(send_date, contact)
                        status = 'skipped' if is_excluded else 'pre-scheduled'
                        skip_reason = 'exclusion_window' if is_excluded else None
                        
                        schedule = EmailSchedule(
                            contact_id=contact.id,
                            email_type='birthday',
                            scheduled_send_date=send_date.isoformat(),
                            scheduled_send_time=self.config['send_time'],
                            status=status,
                            skip_reason=skip_reason,
                            priority=5,
                            campaign_instance_id=None,
                            email_template='birthday_default',
                            sms_template=None,
                            scheduler_run_id=self.scheduler_run_id,
                            event_year=birthday_anniversary.year,
                            event_month=birthday_anniversary.month,
                            event_day=birthday_anniversary.day
                        )
                        contact_schedules.append(schedule)
            
            # Effective date emails
            if contact.effective_date:
                ed_anniversary = self.get_next_anniversary_date(contact.effective_date)
                if ed_anniversary:
                    send_date = ed_anniversary - timedelta(days=self.config['effective_date_days_before'])
                    
                    if send_date >= today:
                        is_excluded = self.is_date_in_exclusion_window(send_date, contact)
                        status = 'skipped' if is_excluded else 'pre-scheduled'
                        skip_reason = 'exclusion_window' if is_excluded else None
                        
                        schedule = EmailSchedule(
                            contact_id=contact.id,
                            email_type='effective_date',
                            scheduled_send_date=send_date.isoformat(),
                            scheduled_send_time=self.config['send_time'],
                            status=status,
                            skip_reason=skip_reason,
                            priority=5,
                            campaign_instance_id=None,
                            email_template='effective_date_default',
                            sms_template=None,
                            scheduler_run_id=self.scheduler_run_id,
                            event_year=ed_anniversary.year,
                            event_month=ed_anniversary.month,
                            event_day=ed_anniversary.day
                        )
                        contact_schedules.append(schedule)
            
            # AEP emails - September 15th
            aep_date = date(today.year, self.config['aep_month'], self.config['aep_day'])
            if aep_date <= today:
                aep_date = date(today.year + 1, self.config['aep_month'], self.config['aep_day'])
                
            is_excluded = self.is_date_in_exclusion_window(aep_date, contact)
            status = 'skipped' if is_excluded else 'pre-scheduled'
            skip_reason = 'exclusion_window' if is_excluded else None
            
            schedule = EmailSchedule(
                contact_id=contact.id,
                email_type='aep',
                scheduled_send_date=aep_date.isoformat(),
                scheduled_send_time=self.config['send_time'],
                status=status,
                skip_reason=skip_reason,
                priority=5,
                campaign_instance_id=None,
                email_template='aep_default',
                sms_template=None,
                scheduler_run_id=self.scheduler_run_id,
                event_year=aep_date.year,
                event_month=aep_date.month,
                event_day=aep_date.day
            )
            contact_schedules.append(schedule)
            
            # Post-window emails for skipped emails
            skipped_schedules = [s for s in contact_schedules if s.status == 'skipped']
            if skipped_schedules and exclusion_window_end:
                post_window_date = exclusion_window_end + timedelta(days=1)
                
                if post_window_date >= today:
                    schedule = EmailSchedule(
                        contact_id=contact.id,
                        email_type='post_window',
                        scheduled_send_date=post_window_date.isoformat(),
                        scheduled_send_time=self.config['send_time'],
                        status='pre-scheduled',
                        skip_reason=None,
                        priority=3,  # Higher priority
                        campaign_instance_id=None,
                        email_template='post_window_default',
                        sms_template=None,
                        scheduler_run_id=self.scheduler_run_id,
                        event_year=post_window_date.year,
                        event_month=post_window_date.month,
                        event_day=post_window_date.day
                    )
                    contact_schedules.append(schedule)
            
            schedules.extend(contact_schedules)
            
        return schedules
    
    def get_active_campaign_instances(self) -> List[CampaignInstance]:
        """Get currently active campaign instances"""
        today = date.today().isoformat()
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT id, campaign_type, instance_name, email_template, sms_template,
                       active_start_date, active_end_date, metadata
                FROM campaign_instances
                WHERE (active_start_date IS NULL OR active_start_date <= ?)
                AND (active_end_date IS NULL OR active_end_date >= ?)
            """, (today, today))
            
            instances = []
            for row in cursor.fetchall():
                instances.append(CampaignInstance(*row))
                
            return instances
    
    def get_campaign_type(self, name: str) -> Optional[CampaignType]:
        """Get campaign type configuration"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT name, respect_exclusion_windows, enable_followups, days_before_event,
                       target_all_contacts, priority
                FROM campaign_types
                WHERE name = ? AND active = TRUE
            """, (name,))
            
            row = cursor.fetchone()
            if row:
                return CampaignType(*row)
            return None
    
    def schedule_campaign_emails(self, contacts: List[Contact]) -> List[EmailSchedule]:
        """Schedule campaign-based emails"""
        schedules = []
        today = date.today()
        
        active_instances = self.get_active_campaign_instances()
        if not active_instances:
            logger.info("No active campaign instances found")
            return schedules
        
        for instance in active_instances:
            campaign_type = self.get_campaign_type(instance.campaign_type)
            if not campaign_type:
                logger.warning(f"Campaign type not found: {instance.campaign_type}")
                continue
                
            # Get targeted contacts for this campaign
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT cc.contact_id, cc.trigger_date
                    FROM contact_campaigns cc
                    WHERE cc.campaign_instance_id = ?
                    AND cc.status = 'pending'
                """, (instance.id,))
                
                campaign_targets = {row[0]: row[1] for row in cursor.fetchall()}
            
            # Schedule emails for targeted contacts
            for contact in contacts:
                if contact.id not in campaign_targets:
                    continue
                    
                trigger_date_str = campaign_targets[contact.id]
                if not trigger_date_str:
                    logger.warning(f"No trigger date for contact {contact.id} in campaign {instance.instance_name}")
                    continue
                    
                try:
                    trigger_date = datetime.strptime(trigger_date_str, '%Y-%m-%d').date()
                    send_date = trigger_date - timedelta(days=campaign_type.days_before_event)
                except ValueError:
                    logger.warning(f"Invalid trigger date format: {trigger_date_str}")
                    continue
                
                if send_date < today:
                    logger.warning(f"Send date {send_date} is in the past for contact {contact.id}")
                    continue
                
                # Check exclusion windows if campaign respects them
                is_excluded = False
                skip_reason = None
                
                if campaign_type.respect_exclusion_windows:
                    is_excluded = self.is_date_in_exclusion_window(send_date, contact)
                    skip_reason = 'exclusion_window' if is_excluded else None
                
                status = 'skipped' if is_excluded else 'pre-scheduled'
                
                schedule = EmailSchedule(
                    contact_id=contact.id,
                    email_type=f'campaign_{campaign_type.name}',
                    scheduled_send_date=send_date.isoformat(),
                    scheduled_send_time=self.config['send_time'],
                    status=status,
                    skip_reason=skip_reason,
                    priority=campaign_type.priority,
                    campaign_instance_id=instance.id,
                    email_template=instance.email_template,
                    sms_template=instance.sms_template,
                    scheduler_run_id=self.scheduler_run_id,
                    event_year=trigger_date.year,
                    event_month=trigger_date.month,
                    event_day=trigger_date.day
                )
                schedules.append(schedule)
        
        return schedules
    
    def apply_load_balancing(self, schedules: List[EmailSchedule]) -> List[EmailSchedule]:
        """Apply load balancing and smoothing to email schedules"""
        if not schedules:
            return schedules
            
        # Group schedules by date for analysis
        daily_counts = defaultdict(int)
        ed_daily_counts = defaultdict(int)
        
        for schedule in schedules:
            if schedule.status == 'pre-scheduled':
                daily_counts[schedule.scheduled_send_date] += 1
                if schedule.email_type == 'effective_date':
                    ed_daily_counts[schedule.scheduled_send_date] += 1
        
        # Calculate organizational daily cap (7% of total contacts)
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT COUNT(*) FROM contacts")
            total_contacts = cursor.fetchone()[0]
        
        daily_cap = int(total_contacts * self.config['daily_send_percentage_cap'])
        ed_soft_limit = min(self.config['ed_daily_soft_limit'], int(daily_cap * 0.3))
        
        logger.info(f"Daily cap: {daily_cap}, ED soft limit: {ed_soft_limit}")
        
        # Apply effective date smoothing
        for schedule in schedules:
            if (schedule.email_type == 'effective_date' and 
                schedule.status == 'pre-scheduled' and
                ed_daily_counts[schedule.scheduled_send_date] > ed_soft_limit):
                
                # Apply deterministic jitter
                jitter_input = f"{schedule.contact_id}_{schedule.email_type}_{schedule.event_year}"
                jitter_hash = int(hashlib.md5(jitter_input.encode()).hexdigest(), 16)
                jitter_days = (jitter_hash % self.config['ed_smoothing_window_days']) - 2  # ±2 days
                
                original_date = datetime.strptime(schedule.scheduled_send_date, '%Y-%m-%d').date()
                new_date = original_date + timedelta(days=jitter_days)
                
                # Ensure new date is not in the past
                if new_date >= date.today():
                    schedule.scheduled_send_date = new_date.isoformat()
        
        # Apply global daily cap enforcement
        updated_daily_counts = defaultdict(int)
        for schedule in schedules:
            if schedule.status == 'pre-scheduled':
                updated_daily_counts[schedule.scheduled_send_date] += 1
        
        # Move overflow to next day if needed
        for send_date, count in updated_daily_counts.items():
            if count > daily_cap * self.config['overage_threshold']:
                # This is a simplified implementation - in production you'd want more sophisticated redistribution
                logger.warning(f"Daily cap exceeded on {send_date}: {count} > {daily_cap}")
        
        return schedules
    
    def enforce_frequency_limits(self, schedules: List[EmailSchedule]) -> List[EmailSchedule]:
        """Enforce per-contact frequency limits"""
        today = date.today()
        period_start = today - timedelta(days=self.config['period_days'])
        
        # Get recent email counts per contact
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT contact_id, COUNT(*) as email_count
                FROM email_schedules
                WHERE scheduled_send_date >= ?
                AND scheduled_send_date < ?
                AND status IN ('sent', 'delivered', 'pre-scheduled')
                AND email_type NOT LIKE 'followup_%'
                GROUP BY contact_id
            """, (period_start.isoformat(), today.isoformat()))
            
            recent_counts = {row[0]: row[1] for row in cursor.fetchall()}
        
        # Sort schedules by priority (lower number = higher priority)
        schedules.sort(key=lambda s: (s.priority, s.scheduled_send_date))
        
        contact_scheduled_count = defaultdict(int)
        filtered_schedules = []
        
        for schedule in schedules:
            current_count = recent_counts.get(schedule.contact_id, 0)
            scheduled_count = contact_scheduled_count[schedule.contact_id]
            total_count = current_count + scheduled_count
            
            if total_count < self.config['max_emails_per_period']:
                filtered_schedules.append(schedule)
                contact_scheduled_count[schedule.contact_id] += 1
            else:
                # Skip due to frequency limit
                schedule.status = 'skipped'
                schedule.skip_reason = 'frequency_limit'
                filtered_schedules.append(schedule)
        
        return filtered_schedules
    
    def save_schedules(self, schedules: List[EmailSchedule]):
        """Save email schedules to database"""
        if not schedules:
            return
            
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Prepare batch insert
            insert_data = []
            for schedule in schedules:
                insert_data.append((
                    schedule.contact_id,
                    schedule.email_type,
                    schedule.scheduled_send_date,
                    schedule.scheduled_send_time,
                    schedule.status,
                    schedule.skip_reason,
                    schedule.priority,
                    schedule.campaign_instance_id,
                    schedule.email_template,
                    schedule.sms_template,
                    schedule.scheduler_run_id,
                    schedule.event_year,
                    schedule.event_month,
                    schedule.event_day
                ))
            
            cursor.executemany("""
                INSERT OR IGNORE INTO email_schedules (
                    contact_id, email_type, scheduled_send_date, scheduled_send_time,
                    status, skip_reason, priority, campaign_instance_id,
                    email_template, sms_template, scheduler_run_id,
                    event_year, event_month, event_day
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, insert_data)
            
            conn.commit()
            logger.info(f"Saved {len(schedules)} email schedules")
    
    def create_checkpoint(self, status: str, contacts_processed: int = 0, 
                         emails_scheduled: int = 0, emails_skipped: int = 0,
                         error_message: str = None):
        """Create scheduler checkpoint for audit trail"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            if status == 'started':
                cursor.execute("""
                    INSERT INTO scheduler_checkpoints (
                        run_timestamp, scheduler_run_id, contacts_checksum, status
                    ) VALUES (?, ?, ?, ?)
                """, (datetime.now().isoformat(), self.scheduler_run_id, "tbd", status))
            else:
                cursor.execute("""
                    UPDATE scheduler_checkpoints
                    SET status = ?, contacts_processed = ?, emails_scheduled = ?,
                        emails_skipped = ?, error_message = ?, completed_at = ?
                    WHERE scheduler_run_id = ?
                """, (status, contacts_processed, emails_scheduled, emails_skipped,
                      error_message, datetime.now().isoformat(), self.scheduler_run_id))
            
            conn.commit()
    
    def run_scheduler(self):
        """Main scheduler execution"""
        logger.info(f"Starting email scheduler run: {self.scheduler_run_id}")
        
        try:
            # Initialize database schema
            self.init_database_schema()
            
            # Create checkpoint
            self.create_checkpoint('started')
            
            # Get contacts to process
            contacts = self.get_contacts_batch()
            logger.info(f"Processing {len(contacts)} contacts")
            
            if not contacts:
                logger.info("No contacts to process")
                self.create_checkpoint('completed', 0, 0, 0)
                return
            
            # Clear existing schedules
            contact_ids = [c.id for c in contacts]
            self.clear_existing_schedules(contact_ids)
            
            # Schedule anniversary-based emails
            logger.info("Scheduling anniversary-based emails...")
            anniversary_schedules = self.schedule_anniversary_emails(contacts)
            
            # Schedule campaign-based emails
            logger.info("Scheduling campaign-based emails...")
            campaign_schedules = self.schedule_campaign_emails(contacts)
            
            # Combine all schedules
            all_schedules = anniversary_schedules + campaign_schedules
            logger.info(f"Generated {len(all_schedules)} total schedules")
            
            # Apply load balancing
            logger.info("Applying load balancing...")
            all_schedules = self.apply_load_balancing(all_schedules)
            
            # Enforce frequency limits
            logger.info("Enforcing frequency limits...")
            all_schedules = self.enforce_frequency_limits(all_schedules)
            
            # Save schedules
            logger.info("Saving schedules...")
            self.save_schedules(all_schedules)
            
            # Count results
            scheduled_count = len([s for s in all_schedules if s.status == 'pre-scheduled'])
            skipped_count = len([s for s in all_schedules if s.status == 'skipped'])
            
            # Complete checkpoint
            self.create_checkpoint('completed', len(contacts), scheduled_count, skipped_count)
            
            logger.info(f"Scheduler completed successfully:")
            logger.info(f"  Contacts processed: {len(contacts)}")
            logger.info(f"  Emails scheduled: {scheduled_count}")
            logger.info(f"  Emails skipped: {skipped_count}")
            
        except Exception as e:
            logger.error(f"Scheduler failed: {str(e)}")
            self.create_checkpoint('failed', error_message=str(e))
            raise


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Email Scheduling System')
    parser.add_argument('--db', default='org-206.sqlite3', help='Database file path')
    parser.add_argument('--init-only', action='store_true', help='Only initialize database schema')
    parser.add_argument('--test-campaigns', action='store_true', help='Create test campaign data')
    
    args = parser.parse_args()
    
    scheduler = EmailScheduler(args.db)
    
    if args.init_only:
        scheduler.init_database_schema()
        logger.info("Database schema initialized")
        return
    
    if args.test_campaigns:
        logger.info("Creating test campaign data...")
        create_test_campaign_data(args.db)
        return
    
    scheduler.run_scheduler()


def create_test_campaign_data(db_path: str):
    """Create test campaign types, instances, and contact targets"""
    with sqlite3.connect(db_path) as conn:
        cursor = conn.cursor()
        
        # Create test campaign types
        campaign_types = [
            ('rate_increase', True, True, 14, False, 1, True),
            ('seasonal_promo', True, True, 7, False, 5, True),
            ('initial_blast', False, False, 0, True, 10, True)
        ]
        
        cursor.executemany("""
            INSERT OR REPLACE INTO campaign_types (
                name, respect_exclusion_windows, enable_followups, days_before_event,
                target_all_contacts, priority, active
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, campaign_types)
        
        # Create test campaign instances
        today = date.today()
        future_date = today + timedelta(days=90)
        
        campaign_instances = [
            ('rate_increase', 'rate_increase_q1_2024', 'rate_increase_template_v1', 'rate_increase_sms_v1',
             today.isoformat(), future_date.isoformat(), None),
            ('seasonal_promo', 'spring_enrollment_2024', 'spring_promo_template', 'spring_promo_sms',
             today.isoformat(), future_date.isoformat(), None)
        ]
        
        cursor.executemany("""
            INSERT OR REPLACE INTO campaign_instances (
                campaign_type, instance_name, email_template, sms_template,
                active_start_date, active_end_date, metadata
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, campaign_instances)
        
        # Get campaign instance IDs
        cursor.execute("SELECT id FROM campaign_instances WHERE instance_name = 'rate_increase_q1_2024'")
        rate_instance_id = cursor.fetchone()[0]
        
        cursor.execute("SELECT id FROM campaign_instances WHERE instance_name = 'spring_enrollment_2024'")
        promo_instance_id = cursor.fetchone()[0]
        
        # Get some test contacts
        cursor.execute("SELECT id FROM contacts LIMIT 50")
        contact_ids = [row[0] for row in cursor.fetchall()]
        
        # Create test contact campaigns
        trigger_date = today + timedelta(days=30)
        contact_campaigns = []
        
        # Add first 25 contacts to rate increase campaign
        for contact_id in contact_ids[:25]:
            contact_campaigns.append((contact_id, rate_instance_id, trigger_date.isoformat(), 'pending', None))
        
        # Add next 25 contacts to seasonal promo campaign
        for contact_id in contact_ids[25:]:
            contact_campaigns.append((contact_id, promo_instance_id, trigger_date.isoformat(), 'pending', None))
        
        cursor.executemany("""
            INSERT OR REPLACE INTO contact_campaigns (
                contact_id, campaign_instance_id, trigger_date, status, metadata
            ) VALUES (?, ?, ?, ?, ?)
        """, contact_campaigns)
        
        conn.commit()
        logger.info(f"Created test campaign data for {len(contact_ids)} contacts")


if __name__ == '__main__':
    main()