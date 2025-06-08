open Types

type t = {
  timezone: string;
  batch_size: int;
  max_memory_mb: int;
  
  send_time_hour: int;
  send_time_minute: int;
  
  birthday_days_before: int;
  effective_date_days_before: int;
  pre_window_buffer: int;
  followup_delay_days: int;
  
  max_emails_per_period: int;
  period_days: int;
  
  daily_cap_percentage: float;
  ed_soft_limit: int;
  smoothing_window: int;
  
  database_path: string;
  backup_dir: string;
  backup_retention_days: int;
  
  (* Organization-specific configuration *)
  organization: organization_config;
}

let default = {
  timezone = "America/Chicago";
  batch_size = 10_000;
  max_memory_mb = 1024;
  
  send_time_hour = 8;
  send_time_minute = 30;
  
  birthday_days_before = 14;
  effective_date_days_before = 30;
  pre_window_buffer = 60;
  followup_delay_days = 2;
  
  max_emails_per_period = 3;
  period_days = 30;
  
  daily_cap_percentage = 0.07;
  ed_soft_limit = 15;
  smoothing_window = 5;
  
  database_path = "org-206.sqlite3";
  backup_dir = "./backups";
  backup_retention_days = 7;
  
  (* Default organization configuration *)
  organization = {
    enable_post_window_emails = true; (* Default: enable post-window emails *)
    effective_date_first_email_months = 11; (* Default: 11 months before first anniversary *)
    exclude_failed_underwriting_global = false; (* Default: don't exclude failed underwriting globally *)
    send_without_zipcode_for_universal = true; (* Default: send to contacts without zip for universal campaigns *)
  };
}

(* Simplified config loading - just return default for now *)
let load_from_json _json_string =
  Ok default

let load_from_file _filename =
  Ok default