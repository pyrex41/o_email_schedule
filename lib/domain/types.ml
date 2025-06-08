type state = 
  | CA | CT | ID | KY | MA | MD | MO | NV 
  | NY | OK | OR | VA | WA 
  | Other of string

type anniversary_email = 
  | Birthday
  | EffectiveDate
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

type schedule_status =
  | PreScheduled
  | Skipped of string
  | Scheduled
  | Processing
  | Sent

type contact = {
  id: int;
  email: string;
  zip_code: string option;
  state: state option;
  birthday: Simple_date.date option;
  effective_date: Simple_date.date option;
  carrier: string option; (* Insurance carrier code *)
  failed_underwriting: bool; (* Whether contact failed health questions *)
}

type email_schedule = {
  contact_id: int;
  email_type: email_type;
  scheduled_date: Simple_date.date;
  scheduled_time: Simple_date.time;
  status: schedule_status;
  priority: int;
  template_id: string option;
  campaign_instance_id: int option;
  scheduler_run_id: string;
}

let state_of_string = function
  | "CA" -> CA | "CT" -> CT | "ID" -> ID | "KY" -> KY
  | "MA" -> MA | "MD" -> MD | "MO" -> MO | "NV" -> NV
  | "NY" -> NY | "OK" -> OK | "OR" -> OR | "VA" -> VA
  | "WA" -> WA | s -> Other s

let string_of_state = function
  | CA -> "CA" | CT -> "CT" | ID -> "ID" | KY -> "KY"
  | MA -> "MA" | MD -> "MD" | MO -> "MO" | NV -> "NV"
  | NY -> "NY" | OK -> "OK" | OR -> "OR" | VA -> "VA"
  | WA -> "WA" | Other s -> s

let string_of_anniversary_email = function
  | Birthday -> "birthday"
  | EffectiveDate -> "effective_date"
  | PostWindow -> "post_window"

let string_of_followup_type = function
  | Cold -> "cold"
  | ClickedNoHQ -> "clicked_no_hq"
  | HQNoYes -> "hq_no_yes"
  | HQWithYes -> "hq_with_yes"

let string_of_email_type = function
  | Anniversary a -> string_of_anniversary_email a
  | Campaign c -> Printf.sprintf "campaign_%s_%d" c.campaign_type c.instance_id
  | Followup f -> Printf.sprintf "followup_%s" (string_of_followup_type f)

let string_of_schedule_status = function
  | PreScheduled -> "pre-scheduled"
  | Skipped reason -> Printf.sprintf "skipped:%s" reason
  | Scheduled -> "scheduled"
  | Processing -> "processing"
  | Sent -> "sent"

let priority_of_email_type = function
  | Anniversary Birthday -> 10
  | Anniversary EffectiveDate -> 20
  | Anniversary PostWindow -> 40
  | Campaign c -> c.priority
  | Followup _ -> 50

(* Error types for comprehensive error handling *)
type scheduler_error =
  | DatabaseError of string
  | InvalidContactData of { contact_id: int; reason: string }
  | ConfigurationError of string
  | ValidationError of string
  | DateCalculationError of string
  | LoadBalancingError of string
  | UnexpectedError of exn

type 'a scheduler_result = ('a, scheduler_error) result

let string_of_error = function
  | DatabaseError msg -> Printf.sprintf "Database error: %s" msg
  | InvalidContactData { contact_id; reason } -> 
      Printf.sprintf "Invalid contact data (ID %d): %s" contact_id reason
  | ConfigurationError msg -> Printf.sprintf "Configuration error: %s" msg
  | ValidationError msg -> Printf.sprintf "Validation error: %s" msg
  | DateCalculationError msg -> Printf.sprintf "Date calculation error: %s" msg
  | LoadBalancingError msg -> Printf.sprintf "Load balancing error: %s" msg
  | UnexpectedError exn -> Printf.sprintf "Unexpected error: %s" (Printexc.to_string exn)

(* Campaign system types *)
type campaign_type_config = {
  name: string;
  respect_exclusion_windows: bool;
  enable_followups: bool;
  days_before_event: int;
  target_all_contacts: bool;
  priority: int;
  active: bool;
  spread_evenly: bool;
  skip_failed_underwriting: bool;
}

type campaign_instance = {
  id: int;
  campaign_type: string;
  instance_name: string;
  email_template: string option;
  sms_template: string option;
  active_start_date: Simple_date.date option;
  active_end_date: Simple_date.date option;
  spread_start_date: Simple_date.date option;
  spread_end_date: Simple_date.date option;
  target_states: string option;
  target_carriers: string option;
  metadata: string option;
  created_at: Simple_date.datetime;
  updated_at: Simple_date.datetime;
}

type contact_campaign = {
  id: int;
  contact_id: int;
  campaign_instance_id: int;
  trigger_date: Simple_date.date option;
  status: string;
  metadata: string option;
  created_at: Simple_date.datetime;
  updated_at: Simple_date.datetime;
}

(* Audit trail types *)
type scheduler_checkpoint = {
  id: int;
  run_timestamp: Simple_date.datetime;
  scheduler_run_id: string;
  contacts_checksum: string;
  schedules_before_checksum: string option;
  schedules_after_checksum: string option;
  contacts_processed: int option;
  emails_scheduled: int option;
  emails_skipped: int option;
  status: string;
  error_message: string option;
  completed_at: Simple_date.datetime option;
}

(* Load balancing types *)
type daily_stats = {
  date: Simple_date.date;
  total_count: int;
  ed_count: int;
  campaign_count: int;
  anniversary_count: int;
  over_threshold: bool;
}

type load_balancing_config = {
  daily_send_percentage_cap: float;
  ed_daily_soft_limit: int;
  ed_smoothing_window_days: int;
  catch_up_spread_days: int;
  overage_threshold: float;
  total_contacts: int;
}

type distribution_analysis = {
  total_emails: int;
  total_days: int;
  avg_per_day: float;
  max_day: int;
  min_day: int;
  distribution_variance: int;
}

(* Organization-level configuration for scheduling flexibility *)
type organization_config = {
  enable_post_window_emails: bool;
  effective_date_first_email_months: int;
  exclude_failed_underwriting_global: bool;
  send_without_zipcode_for_universal: bool;
}