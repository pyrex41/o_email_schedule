type state = 
  | CA | CT | ID | KY | MA | MD | MO | NV 
  | NY | OK | OR | VA | WA 
  | Other of string

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
  | AEP -> "aep"
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
  | Anniversary AEP -> 30
  | Anniversary PostWindow -> 40
  | Campaign c -> c.priority
  | Followup _ -> 50