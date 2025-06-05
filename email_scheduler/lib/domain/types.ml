(* Core domain types for the email scheduler *)

open Ptime

(* US States - use variant type for compile-time safety *)
type state = 
  | CA | CT | ID | KY | MA | MD | MO | NV 
  | NY | OK | OR | VA | WA 
  | Other of string

let string_of_state = function
  | CA -> "CA" | CT -> "CT" | ID -> "ID" | KY -> "KY"
  | MA -> "MA" | MD -> "MD" | MO -> "MO" | NV -> "NV"
  | NY -> "NY" | OK -> "OK" | OR -> "OR" | VA -> "VA"
  | WA -> "WA" | Other s -> s

let state_of_string = function
  | "CA" -> CA | "CT" -> CT | "ID" -> ID | "KY" -> KY
  | "MA" -> MA | "MD" -> MD | "MO" -> MO | "NV" -> NV
  | "NY" -> NY | "OK" -> OK | "OR" -> OR | "VA" -> VA
  | "WA" -> WA | s -> Other s

(* Email types with clear discrimination *)
type anniversary_email = 
  | Birthday
  | EffectiveDate
  | AEP
  | PostWindow

type campaign_email = {
  campaign_type: string;
  instance_id: int;
  respect_exclusions: bool;
  days_before_event: int;
  priority: int;
}

type followup_type =
  | Cold
  | ClickedNoHQ
  | HQNoYes
  | HQWithYes

type email_type =
  | Anniversary of anniversary_email
  | Campaign of campaign_email
  | Followup of followup_type

let string_of_email_type = function
  | Anniversary Birthday -> "birthday"
  | Anniversary EffectiveDate -> "effective_date"
  | Anniversary AEP -> "aep"
  | Anniversary PostWindow -> "post_window"
  | Campaign c -> "campaign_" ^ c.campaign_type
  | Followup Cold -> "followup_1_cold"
  | Followup ClickedNoHQ -> "followup_2_clicked_no_hq"
  | Followup HQNoYes -> "followup_3_hq_no_yes"
  | Followup HQWithYes -> "followup_4_hq_with_yes"

(* Schedule status *)
type schedule_status =
  | PreScheduled
  | Skipped of string  (* reason *)
  | Scheduled
  | Processing
  | Sent

let string_of_status = function
  | PreScheduled -> "pre-scheduled"
  | Skipped reason -> "skipped"
  | Scheduled -> "scheduled"
  | Processing -> "processing"
  | Sent -> "sent"

(* Contact type *)
type contact = {
  id: int;
  email: string;
  zip_code: string option;
  state: state option;
  birthday: date option;
  effective_date: date option;
}

(* Email schedule *)
type email_schedule = {
  contact_id: int;
  email_type: email_type;
  scheduled_date: date;
  scheduled_time: time;
  status: schedule_status;
  priority: int;
  template_id: string option;
  campaign_instance_id: int option;
  scheduler_run_id: string;
  skip_reason: string option;
  created_at: Ptime.t;
  updated_at: Ptime.t;
}

(* Campaign types *)
type campaign_type_config = {
  name: string;
  respect_exclusion_windows: bool;
  enable_followups: bool;
  days_before_event: int;
  target_all_contacts: bool;
  priority: int;
  active: bool;
}

type campaign_instance = {
  id: int;
  campaign_type: string;
  instance_name: string;
  email_template: string option;
  sms_template: string option;
  active_start_date: date option;
  active_end_date: date option;
  metadata: Yojson.Safe.t option;
  created_at: Ptime.t;
  updated_at: Ptime.t;
}

type contact_campaign = {
  id: int;
  contact_id: int;
  campaign_instance_id: int;
  trigger_date: date option;
  status: string;
  metadata: Yojson.Safe.t option;
  created_at: Ptime.t;
  updated_at: Ptime.t;
}

(* Configuration types *)
type scheduler_config = {
  timezone: string;
  batch_size: int;
  max_memory_mb: int;
  birthday_days_before: int;
  effective_date_days_before: int;
  pre_window_buffer_days: int;
  followup_delay_days: int;
  daily_cap_percentage: float;
  ed_soft_limit: int;
  smoothing_window_days: int;
  send_time: time;
}

(* Error types *)
type scheduler_error =
  | DatabaseError of string
  | InvalidContactData of { contact_id: int; reason: string }
  | ConfigurationError of string
  | UnexpectedError of exn

(* Result types for better error handling *)
type 'a scheduler_result = ('a, scheduler_error) result

(* Audit and monitoring types *)
type scheduler_checkpoint = {
  id: int;
  run_timestamp: Ptime.t;
  scheduler_run_id: string;
  contacts_checksum: string;
  schedules_before_checksum: string option;
  schedules_after_checksum: string option;
  contacts_processed: int option;
  emails_scheduled: int option;
  emails_skipped: int option;
  status: string;
  error_message: string option;
  completed_at: Ptime.t option;
}

(* Load balancing types *)
type daily_stats = {
  date: date;
  total_count: int;
  ed_count: int;
  over_threshold: bool;
}

type load_balancing_config = {
  daily_send_percentage_cap: float;
  ed_daily_soft_limit: int;
  ed_smoothing_window_days: int;
  catch_up_spread_days: int;
  overage_threshold: float;
}