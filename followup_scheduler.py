#!/usr/bin/env python3
"""
Follow-up Email Scheduler

Implements follow-up email scheduling logic based on user behavior:
- followup_4_hq_with_yes: Contact answered health questions with medical conditions (highest priority)
- followup_3_hq_no_yes: Contact answered health questions with no medical conditions  
- followup_2_clicked_no_hq: Contact clicked a link but didn't answer health questions
- followup_1_cold: Contact didn't click or answer health questions (lowest priority)
"""

import sqlite3
import json
import logging
from datetime import datetime, date, timedelta
from typing import Dict, List, Tuple, Optional, Any
from dataclasses import dataclass
from collections import defaultdict
import uuid

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class EmailSent:
    id: int
    contact_id: int
    email_type: str
    scheduled_send_date: str
    actual_send_datetime: Optional[str]
    campaign_instance_id: Optional[int]
    event_year: Optional[int]
    event_month: Optional[int]
    event_day: Optional[int]

@dataclass
class ContactBehavior:
    contact_id: int
    clicked_links: bool = False
    answered_health_questions: bool = False
    has_medical_conditions: bool = False
    last_click_date: Optional[str] = None
    last_eligibility_date: Optional[str] = None

@dataclass
class FollowupSchedule:
    contact_id: int
    email_type: str
    scheduled_send_date: str
    scheduled_send_time: str
    status: str
    priority: int
    initial_email_id: int
    campaign_instance_id: Optional[int]
    email_template: str
    sms_template: Optional[str]
    scheduler_run_id: str
    metadata: str

class FollowupScheduler:
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.scheduler_run_id = str(uuid.uuid4())
        
        # Configuration - should be configurable in real implementation
        self.config = {
            'send_time': '08:30:00',
            'followup_days_after': 2,  # Days after initial email to send follow-up
            'lookback_days': 35,       # Days to look back for eligible emails
            'batch_size': 1000
        }
    
    def get_eligible_initial_emails(self) -> List[EmailSent]:
        """Get initial emails eligible for follow-ups"""
        today = date.today()
        lookback_date = today - timedelta(days=self.config['lookback_days'])
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Get emails that were sent and are eligible for follow-ups
            cursor.execute("""
                SELECT es.id, es.contact_id, es.email_type, es.scheduled_send_date,
                       es.actual_send_datetime, es.campaign_instance_id,
                       es.event_year, es.event_month, es.event_day
                FROM email_schedules es
                WHERE es.status IN ('sent', 'delivered')
                AND es.scheduled_send_date >= ?
                AND es.scheduled_send_date <= ?
                AND (
                    -- Anniversary-based emails eligible for follow-ups
                    es.email_type IN ('birthday', 'effective_date', 'aep', 'post_window')
                    OR 
                    -- Campaign-based emails where campaign has follow-ups enabled
                    (es.email_type LIKE 'campaign_%' AND es.campaign_instance_id IS NOT NULL)
                )
                AND es.contact_id NOT IN (
                    -- Exclude contacts that already have follow-ups scheduled or sent
                    SELECT DISTINCT contact_id FROM email_schedules 
                    WHERE email_type LIKE 'followup_%'
                    AND scheduled_send_date >= ?
                )
            """, (lookback_date.isoformat(), today.isoformat(), lookback_date.isoformat()))
            
            emails = []
            for row in cursor.fetchall():
                emails.append(EmailSent(*row))
            
            return emails
    
    def check_campaign_followup_enabled(self, campaign_instance_id: int) -> bool:
        """Check if a campaign instance has follow-ups enabled"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT ct.enable_followups
                FROM campaign_instances ci
                JOIN campaign_types ct ON ci.campaign_type = ct.name
                WHERE ci.id = ?
            """, (campaign_instance_id,))
            
            result = cursor.fetchone()
            return result[0] if result else False
    
    def get_contact_behavior(self, contact_id: int, initial_email_date: str) -> ContactBehavior:
        """Analyze contact behavior to determine appropriate follow-up type"""
        behavior = ContactBehavior(contact_id)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Check for clicks after the initial email date
            cursor.execute("""
                SELECT MAX(clicked_at) as last_click
                FROM tracking_clicks
                WHERE contact_id = ?
                AND clicked_at >= ?
            """, (contact_id, initial_email_date))
            
            click_result = cursor.fetchone()
            if click_result and click_result[0]:
                behavior.clicked_links = True
                behavior.last_click_date = click_result[0]
            
            # Check for eligibility/health questions after the initial email date
            cursor.execute("""
                SELECT ce.metadata, MAX(ce.created_at) as last_eligibility
                FROM contact_events ce
                WHERE ce.contact_id = ?
                AND ce.event_type = 'eligibility_answered'
                AND ce.created_at >= ?
                GROUP BY ce.contact_id
            """, (contact_id, initial_email_date))
            
            eligibility_result = cursor.fetchone()
            if eligibility_result and eligibility_result[0]:
                behavior.answered_health_questions = True
                behavior.last_eligibility_date = eligibility_result[1]
                
                # Parse metadata to check for medical conditions
                try:
                    metadata = json.loads(eligibility_result[0])
                    # Check for various indicators of medical conditions
                    has_conditions = (
                        metadata.get('has_medical_conditions', False) or
                        metadata.get('main_questions_yes_count', 0) > 0 or
                        any(metadata.get(key, False) for key in metadata if 'condition' in key.lower())
                    )
                    behavior.has_medical_conditions = has_conditions
                except (json.JSONDecodeError, TypeError):
                    pass
        
        return behavior
    
    def determine_followup_type(self, behavior: ContactBehavior) -> str:
        """Determine the appropriate follow-up email type based on behavior"""
        if behavior.answered_health_questions:
            if behavior.has_medical_conditions:
                return 'followup_4_hq_with_yes'  # Highest priority
            else:
                return 'followup_3_hq_no_yes'
        elif behavior.clicked_links:
            return 'followup_2_clicked_no_hq'
        else:
            return 'followup_1_cold'  # Lowest priority
    
    def calculate_followup_send_date(self, initial_email_date: str) -> date:
        """Calculate when to send the follow-up email"""
        initial_date = datetime.strptime(initial_email_date, '%Y-%m-%d').date()
        followup_date = initial_date + timedelta(days=self.config['followup_days_after'])
        
        # If the calculated date is in the past, schedule for tomorrow
        tomorrow = date.today() + timedelta(days=1)
        if followup_date < tomorrow:
            followup_date = tomorrow
            
        return followup_date
    
    def get_followup_template(self, followup_type: str, campaign_instance_id: Optional[int] = None) -> Tuple[str, Optional[str]]:
        """Get email and SMS templates for follow-up"""
        # Default templates
        template_map = {
            'followup_1_cold': ('followup_cold_template', None),
            'followup_2_clicked_no_hq': ('followup_clicked_template', None),
            'followup_3_hq_no_yes': ('followup_hq_no_conditions_template', None),
            'followup_4_hq_with_yes': ('followup_hq_with_conditions_template', None)
        }
        
        email_template, sms_template = template_map.get(followup_type, ('followup_default_template', None))
        
        # Check for campaign-specific template overrides
        if campaign_instance_id:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT metadata FROM campaign_instances WHERE id = ?
                """, (campaign_instance_id,))
                
                result = cursor.fetchone()
                if result and result[0]:
                    try:
                        metadata = json.loads(result[0])
                        followup_templates = metadata.get('followup_templates', {})
                        if followup_type in followup_templates:
                            email_template = followup_templates[followup_type].get('email', email_template)
                            sms_template = followup_templates[followup_type].get('sms', sms_template)
                    except (json.JSONDecodeError, TypeError):
                        pass
        
        return email_template, sms_template
    
    def get_followup_priority(self, followup_type: str, campaign_instance_id: Optional[int] = None) -> int:
        """Get priority for follow-up email"""
        # Default priorities (lower number = higher priority)
        priority_map = {
            'followup_4_hq_with_yes': 1,    # Highest priority
            'followup_3_hq_no_yes': 2,
            'followup_2_clicked_no_hq': 3,
            'followup_1_cold': 4            # Lowest priority
        }
        
        base_priority = priority_map.get(followup_type, 5)
        
        # If from a campaign, inherit some priority characteristics
        if campaign_instance_id:
            with sqlite3.connect(self.db_path) as conn:
                cursor = conn.cursor()
                
                cursor.execute("""
                    SELECT ct.priority
                    FROM campaign_instances ci
                    JOIN campaign_types ct ON ci.campaign_type = ct.name
                    WHERE ci.id = ?
                """, (campaign_instance_id,))
                
                result = cursor.fetchone()
                if result:
                    # Blend campaign priority with follow-up priority
                    campaign_priority = result[0]
                    return min(base_priority, campaign_priority + 1)
        
        return base_priority
    
    def is_date_in_exclusion_window(self, send_date: date, contact_id: int) -> bool:
        """Check if send date falls in exclusion window (reuse logic from main scheduler)"""
        # This would use the same exclusion window logic as the main scheduler
        # For now, implementing a simplified version
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            cursor.execute("""
                SELECT state, birth_date, effective_date
                FROM contacts
                WHERE id = ?
            """, (contact_id,))
            
            result = cursor.fetchone()
            if not result:
                return False
                
            state, birth_date, effective_date = result
            
            # Year-round exclusion states
            if state in ['CT', 'MA', 'NY', 'WA']:
                return True
                
            # For other exclusion logic, we'd implement the full state rules
            # For this implementation, we'll be more permissive with follow-ups
            return False
    
    def schedule_followups(self, initial_emails: List[EmailSent]) -> List[FollowupSchedule]:
        """Schedule follow-up emails based on initial emails and user behavior"""
        schedules = []
        
        for initial_email in initial_emails:
            # Check if campaign-based email has follow-ups enabled
            if (initial_email.campaign_instance_id and 
                not self.check_campaign_followup_enabled(initial_email.campaign_instance_id)):
                continue
            
            # Analyze contact behavior
            behavior = self.get_contact_behavior(
                initial_email.contact_id, 
                initial_email.scheduled_send_date
            )
            
            # Determine follow-up type
            followup_type = self.determine_followup_type(behavior)
            
            # Calculate send date
            send_date = self.calculate_followup_send_date(initial_email.scheduled_send_date)
            
            # Check exclusion windows (follow-ups always respect exclusion windows)
            if self.is_date_in_exclusion_window(send_date, initial_email.contact_id):
                logger.info(f"Follow-up for contact {initial_email.contact_id} skipped due to exclusion window")
                continue
            
            # Get templates and priority
            email_template, sms_template = self.get_followup_template(
                followup_type, 
                initial_email.campaign_instance_id
            )
            priority = self.get_followup_priority(followup_type, initial_email.campaign_instance_id)
            
            # Create metadata
            metadata = {
                'initial_email_id': initial_email.id,
                'initial_email_type': initial_email.email_type,
                'followup_behavior': {
                    'clicked_links': behavior.clicked_links,
                    'answered_health_questions': behavior.answered_health_questions,
                    'has_medical_conditions': behavior.has_medical_conditions,
                    'last_click_date': behavior.last_click_date,
                    'last_eligibility_date': behavior.last_eligibility_date
                },
                'campaign_name': None  # Would get from campaign instance if needed
            }
            
            if initial_email.campaign_instance_id:
                # Get campaign name for metadata
                with sqlite3.connect(self.db_path) as conn:
                    cursor = conn.cursor()
                    cursor.execute("""
                        SELECT instance_name FROM campaign_instances WHERE id = ?
                    """, (initial_email.campaign_instance_id,))
                    result = cursor.fetchone()
                    if result:
                        metadata['campaign_name'] = result[0]
            
            schedule = FollowupSchedule(
                contact_id=initial_email.contact_id,
                email_type=followup_type,
                scheduled_send_date=send_date.isoformat(),
                scheduled_send_time=self.config['send_time'],
                status='pre-scheduled',
                priority=priority,
                initial_email_id=initial_email.id,
                campaign_instance_id=initial_email.campaign_instance_id,
                email_template=email_template,
                sms_template=sms_template,
                scheduler_run_id=self.scheduler_run_id,
                metadata=json.dumps(metadata)
            )
            
            schedules.append(schedule)
        
        return schedules
    
    def save_followup_schedules(self, schedules: List[FollowupSchedule]):
        """Save follow-up schedules to database"""
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
                    None,  # skip_reason
                    schedule.priority,
                    schedule.campaign_instance_id,
                    schedule.email_template,
                    schedule.sms_template,
                    schedule.scheduler_run_id,
                    None,  # event_year
                    None,  # event_month
                    None,  # event_day
                    None,  # batch_id
                    schedule.metadata  # Use catchup_note field for metadata
                ))
            
            cursor.executemany("""
                INSERT OR IGNORE INTO email_schedules (
                    contact_id, email_type, scheduled_send_date, scheduled_send_time,
                    status, skip_reason, priority, campaign_instance_id,
                    email_template, sms_template, scheduler_run_id,
                    event_year, event_month, event_day, batch_id, catchup_note
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, insert_data)
            
            conn.commit()
            logger.info(f"Saved {len(schedules)} follow-up schedules")
    
    def run_followup_scheduler(self):
        """Main follow-up scheduler execution"""
        logger.info(f"Starting follow-up scheduler run: {self.scheduler_run_id}")
        
        try:
            # Get eligible initial emails
            initial_emails = self.get_eligible_initial_emails()
            logger.info(f"Found {len(initial_emails)} eligible initial emails")
            
            if not initial_emails:
                logger.info("No eligible emails for follow-ups")
                return
            
            # Schedule follow-ups
            followup_schedules = self.schedule_followups(initial_emails)
            logger.info(f"Generated {len(followup_schedules)} follow-up schedules")
            
            # Save schedules
            if followup_schedules:
                self.save_followup_schedules(followup_schedules)
                
                # Report by type
                type_counts = defaultdict(int)
                for schedule in followup_schedules:
                    type_counts[schedule.email_type] += 1
                
                logger.info("Follow-up breakdown:")
                for email_type, count in sorted(type_counts.items()):
                    logger.info(f"  {email_type}: {count}")
            
            logger.info("Follow-up scheduler completed successfully")
            
        except Exception as e:
            logger.error(f"Follow-up scheduler failed: {str(e)}")
            raise


def main():
    """Main entry point"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Follow-up Email Scheduler')
    parser.add_argument('--db', default='org-206.sqlite3', help='Database file path')
    
    args = parser.parse_args()
    
    scheduler = FollowupScheduler(args.db)
    scheduler.run_followup_scheduler()


if __name__ == '__main__':
    main()