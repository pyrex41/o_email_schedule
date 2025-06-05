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
}

let load_from_json json_string =
  try
    let json = Yojson.Safe.from_string json_string in
    let open Yojson.Safe.Util in
    
    let get_string field default_val =
      try json |> member field |> to_string
      with _ -> default_val
    in
    
    let get_int field default_val =
      try json |> member field |> to_int
      with _ -> default_val
    in
    
    let get_float field default_val =
      try json |> member field |> to_float
      with _ -> default_val
    in
    
    Ok {
      timezone = get_string "timezone" default.timezone;
      batch_size = get_int "batch_size" default.batch_size;
      max_memory_mb = get_int "max_memory_mb" default.max_memory_mb;
      
      send_time_hour = get_int "send_time_hour" default.send_time_hour;
      send_time_minute = get_int "send_time_minute" default.send_time_minute;
      
      birthday_days_before = get_int "birthday_days_before" default.birthday_days_before;
      effective_date_days_before = get_int "effective_date_days_before" default.effective_date_days_before;
      pre_window_buffer = get_int "pre_window_buffer" default.pre_window_buffer;
      followup_delay_days = get_int "followup_delay_days" default.followup_delay_days;
      
      max_emails_per_period = get_int "max_emails_per_period" default.max_emails_per_period;
      period_days = get_int "period_days" default.period_days;
      
      daily_cap_percentage = get_float "daily_cap_percentage" default.daily_cap_percentage;
      ed_soft_limit = get_int "ed_soft_limit" default.ed_soft_limit;
      smoothing_window = get_int "smoothing_window" default.smoothing_window;
      
      database_path = get_string "database_path" default.database_path;
      backup_dir = get_string "backup_dir" default.backup_dir;
      backup_retention_days = get_int "backup_retention_days" default.backup_retention_days;
    }
  with e ->
    Error (Printf.sprintf "Failed to parse config: %s" (Printexc.to_string e))

let load_from_file filename =
  try
    let ic = open_in filename in
    let content = really_input_string ic (in_channel_length ic) in
    close_in ic;
    load_from_json content
  with
  | Sys_error _ -> Ok default
  | e -> Error (Printf.sprintf "Failed to read config file: %s" (Printexc.to_string e))