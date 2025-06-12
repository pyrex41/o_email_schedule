(* Database interface for the email scheduler *)

(* Error handling *)
type db_error = 
  | SqliteError of string
  | ParseError of string
  | ConnectionError of string

val string_of_db_error : db_error -> string

(* Database initialization and management *)
val set_db_path : string -> unit
val initialize_database : unit -> (unit, db_error) result
val close_database : unit -> unit

(* Contact queries *)
val get_contacts_in_scheduling_window : int -> int -> (Types.contact list, db_error) result
val get_all_contacts : unit -> (Types.contact list, db_error) result
val get_total_contact_count : unit -> (int, db_error) result

(* Schedule management - smart update functions *)
val smart_update_schedules : Types.email_schedule list -> string -> (int, db_error) result
val update_email_schedules : ?use_smart_update:bool -> Types.email_schedule list -> string -> (int, db_error) result

(* Legacy schedule management functions *)
val clear_pre_scheduled_emails : unit -> (int, db_error) result
val batch_insert_schedules_optimized : Types.email_schedule list -> (int, db_error) result
val batch_insert_schedules_chunked : Types.email_schedule list -> int -> (int, db_error) result

(* Follow-up and interaction tracking *)
val get_sent_emails_for_followup : int -> ((int * string * string * int) list, db_error) result
val get_contact_interactions : int -> string -> (bool * bool, db_error) result

(* Performance optimization *)
val optimize_sqlite_for_bulk_inserts : unit -> (unit, db_error) result
val restore_sqlite_safety : unit -> (unit, db_error) result
val ensure_performance_indexes : unit -> (unit, db_error) result

(* Low-level database access for testing *)
val execute_sql_safe : string -> (string list list, db_error) result
val execute_sql_no_result : string -> (unit, db_error) result
val batch_insert_with_prepared_statement : string -> string array list -> (int, db_error) result

(* Campaign system functions *)
val get_active_campaign_instances : unit -> (Types.campaign_instance list, db_error) result
val get_campaign_type_config : string -> (Types.campaign_type_config, db_error) result
val get_contact_campaigns_for_instance : int -> (Types.contact_campaign list, db_error) result
val get_all_contacts_for_campaign : unit -> (Types.contact list, db_error) result
val get_contacts_for_campaign : Types.campaign_instance -> (Types.contact list, db_error) result

(* Organization configuration *)
val get_enhanced_organization_config : int -> (Types.enhanced_organization_config, db_error) result
val get_state_buffer_override : int -> Types.state -> int option
val load_organization_config : int -> (Types.enhanced_organization_config, db_error) result