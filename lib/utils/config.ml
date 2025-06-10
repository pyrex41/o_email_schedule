open Types
open System_constants.SystemConstants
open Size_profiles

type t = {
  (* Organization configuration from database *)
  organization: enhanced_organization_config;
  
  (* Computed load balancing configuration *)
  load_balancing: computed_load_balancing_config;
  
  (* System paths (not in database) *)
  database_path: string;
  backup_dir: string;
  backup_retention_days: int;
  max_memory_mb: int;
}

(* Load configuration for organization *)
let load_for_org org_id org_specific_db_path =
  (* First, get the organization configuration from central database *)
  match Database.load_organization_config org_id with
  | Error err ->
      Printf.eprintf "ERROR: Failed to load org %d config: %s\n" 
        org_id (Database.string_of_db_error err);
      Printf.eprintf "Using default configuration as fallback\n";
      
      (* Fallback configuration *)
      let default_org = {
        id = org_id;
        name = Printf.sprintf "Organization %d" org_id;
        enable_post_window_emails = true;
        effective_date_first_email_months = 11;
        exclude_failed_underwriting_global = false;
        send_without_zipcode_for_universal = true;
        pre_exclusion_buffer_days = 60;
        birthday_days_before = 14;
        effective_date_days_before = 30;
        send_time_hour = 8;
        send_time_minute = 30;
        timezone = "America/Chicago";
        max_emails_per_period = 3;
        frequency_period_days = 30;
        size_profile = Medium;
        config_overrides = None;
      } in
      
      (* Get contact count from org-specific database *)
      Database.set_db_path org_specific_db_path;
      let total_contacts = match Database.get_total_contact_count () with
        | Ok count -> count
        | Error _ -> 10_000  (* Fallback assumption *)
      in
      
      let load_balancing = load_balancing_for_profile Medium total_contacts in
      
      {
        organization = default_org;
        load_balancing;
        database_path = org_specific_db_path;
        backup_dir = "./backups";
        backup_retention_days = 7;
        max_memory_mb = 1024;
      }
      
  | Ok org_config ->
      (* Get contact count from org-specific database *)
      Database.set_db_path org_specific_db_path;
      let total_contacts = match Database.get_total_contact_count () with
        | Ok count -> count
        | Error _ -> 
            Printf.eprintf "WARNING: Could not get contact count, estimating based on profile\n";
            match org_config.size_profile with
            | Small -> 5_000
            | Medium -> 50_000
            | Large -> 250_000
            | Enterprise -> 1_000_000
      in
      
      (* Compute load balancing configuration *)
      let base_load_balancing = load_balancing_for_profile org_config.size_profile total_contacts in
      let load_balancing = apply_config_overrides base_load_balancing org_config.config_overrides in
      
      {
        organization = org_config;
        load_balancing;
        database_path = org_specific_db_path;
        backup_dir = "./backups";
        backup_retention_days = 7;
        max_memory_mb = 1024;
      }

(* Helper to create full load_balancing_config for algorithms *)
let to_load_balancing_config t =
  {
    daily_send_percentage_cap = t.load_balancing.daily_send_percentage_cap;
    ed_daily_soft_limit = t.load_balancing.ed_daily_soft_limit;
    ed_smoothing_window_days = t.load_balancing.ed_smoothing_window_days;
    catch_up_spread_days = SystemConstants.catch_up_spread_days;
    overage_threshold = SystemConstants.overage_threshold;
    total_contacts = t.load_balancing.total_contacts;
  }

(* Legacy compatibility function for existing code *)
let default = 
  let default_org = {
    id = 206;  (* Default org ID *)
    name = "Default Organization";
    enable_post_window_emails = true;
    effective_date_first_email_months = 11;
    exclude_failed_underwriting_global = false;
    send_without_zipcode_for_universal = true;
    pre_exclusion_buffer_days = 60;
    birthday_days_before = 14;
    effective_date_days_before = 30;
    send_time_hour = 8;
    send_time_minute = 30;
    timezone = "America/Chicago";
    max_emails_per_period = 3;
    frequency_period_days = 30;
    size_profile = Medium;
    config_overrides = None;
  } in
  
  let load_balancing = load_balancing_for_profile Medium 50_000 in
  
  {
    organization = default_org;
    load_balancing;
    database_path = "org-206.sqlite3";
    backup_dir = "./backups";
    backup_retention_days = 7;
    max_memory_mb = 1024;
  }

(* Legacy compatibility functions for existing code *)
let load_from_json _json_string = Ok default
let load_from_file _filename = Ok default