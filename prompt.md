# OCaml Email Scheduler Implementation Prompt

## Context

You are implementing a sophisticated email scheduling system in OCaml based on the provided business logic documentation. The system must handle complex date calculations, state-based exclusion rules, campaign management, and scale to process up to 3 million contacts efficiently.

## Primary Objectives

1. Implement a type-safe, performant email scheduler in OCaml
2. Create a domain-specific language (DSL) for expressing scheduling rules
3. Ensure all date calculations handle edge cases correctly
4. Build with streaming architecture for memory efficiency at scale
5. Provide comprehensive audit trails and error recovery

## Technical Requirements

### Core Libraries to Use

```ocaml
(* dune-project *)
(lang dune 3.0)
(name email_scheduler)

(package
 (name email_scheduler)
 (depends
  ocaml (>= 4.14)
  dune (>= 3.0)
  sqlite3 (>= 5.0.0)
  caqti (>= 2.0.0)
  caqti-driver-sqlite3
  caqti-lwt
  lwt (>= 5.6.0)
  ptime
  timedesc  ; for timezone handling
  yojson    ; for JSON config
  logs      ; for structured logging
  alcotest  ; for testing
  bisect_ppx ; for coverage
))
```

### Module Structure

```
lib/
├── domain/
│   ├── types.ml         # Core domain types
│   ├── contact.ml       # Contact operations
│   ├── campaign.ml      # Campaign types and logic
│   └── email_schedule.ml # Schedule types
├── rules/
│   ├── state_rules.ml   # State-specific exclusions
│   ├── exclusion_window.ml
│   └── dsl.ml          # Rule DSL
├── scheduling/
│   ├── date_calc.ml    # Date calculations
│   ├── scheduler.ml    # Main scheduling logic
│   └── load_balancer.ml
├── persistence/
│   ├── database.ml     # DB operations
│   ├── queries.ml      # SQL queries
│   └── migrations.ml
└── utils/
    ├── audit.ml        # Audit trail
    └── config.ml       # Configuration
```

## Implementation Guidelines

### 1. Domain Types (types.ml)

```ocaml
(* Start with comprehensive type definitions *)
module Types = struct
  (* US States - use variant type for compile-time safety *)
  type state = 
    | CA | CT | ID | KY | MA | MD | MO | NV 
    | NY | OK | OR | VA | WA 
    | Other of string

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

  type email_type =
    | Anniversary of anniversary_email
    | Campaign of campaign_email
    | Followup of followup_type

  and followup_type =
    | Cold
    | ClickedNoHQ
    | HQNoYes
    | HQWithYes

  (* Schedule status *)
  type schedule_status =
    | PreScheduled
    | Skipped of string  (* reason *)
    | Scheduled
    | Processing
    | Sent

  (* Contact type *)
  type contact = {
    id: int;
    email: string;
    zip_code: string option;
    state: state option;
    birthday: Ptime.date option;
    effective_date: Ptime.date option;
  }

  (* Email schedule *)
  type email_schedule = {
    contact_id: int;
    email_type: email_type;
    scheduled_date: Ptime.date;
    scheduled_time: Ptime.time;
    status: schedule_status;
    priority: int;
    template_id: string option;
    campaign_instance_id: int option;
    scheduler_run_id: string;
  }
end
```

### 2. State Rules DSL (dsl.ml)

```ocaml
(* Create a DSL for expressing exclusion rules *)
module RuleDSL = struct
  type window = {
    before_days: int;
    after_days: int;
    use_month_start: bool;
  }

  type rule =
    | BirthdayWindow of window
    | EffectiveDateWindow of window
    | YearRoundExclusion
    | NoExclusion

  (* DSL functions for building rules *)
  let birthday_window ~before ~after ?(use_month_start=false) () =
    BirthdayWindow { before_days = before; after_days = after; use_month_start }

  let effective_date_window ~before ~after =
    EffectiveDateWindow { before_days = before; after_days = after }

  let year_round = YearRoundExclusion
  let no_exclusion = NoExclusion

  (* State rule definitions using the DSL *)
  let rules_for_state = function
    | CA -> birthday_window ~before:30 ~after:60 ()
    | ID -> birthday_window ~before:0 ~after:63 ()
    | KY -> birthday_window ~before:0 ~after:60 ()
    | MD -> birthday_window ~before:0 ~after:30 ()
    | NV -> birthday_window ~before:0 ~after:60 ~use_month_start:true ()
    | OK -> birthday_window ~before:0 ~after:60 ()
    | OR -> birthday_window ~before:0 ~after:31 ()
    | VA -> birthday_window ~before:0 ~after:30 ()
    | MO -> effective_date_window ~before:30 ~after:33
    | CT | MA | NY | WA -> year_round
    | Other _ -> no_exclusion
end
```

### 3. Date Calculations (date_calc.ml)

```ocaml
module DateCalc = struct
  open Ptime

  (* Add pre-window exclusion buffer *)
  let pre_window_buffer_days = 60

  (* Calculate next anniversary from today *)
  let next_anniversary (today: date) (event_date: date) : date =
    (* Implementation should handle:
       - Year wraparound
       - February 29th in non-leap years
       - Past anniversaries this year
    *)

  (* Check if date falls within exclusion window *)
  let in_exclusion_window (check_date: date) (window: RuleDSL.window) (anchor_date: date) : bool =
    (* Implementation should handle:
       - Windows spanning year boundaries
       - Nevada's month-start rule
       - Pre-window buffer extension
    *)

  (* Calculate jitter for load balancing *)
  let calculate_jitter ~contact_id ~event_type ~year ~window_days : int =
    (* Use deterministic hash for consistent distribution *)
    let hash_input = Printf.sprintf "%d-%s-%d" contact_id event_type year in
    (Hashtbl.hash hash_input) mod window_days - (window_days / 2)
end
```

### 4. Streaming Architecture (scheduler.ml)

```ocaml
module Scheduler = struct
  open Lwt.Syntax

  (* Process contacts in streaming fashion *)
  let schedule_emails_streaming ~db ~config ~run_id =
    let chunk_size = 10_000 in
    
    let rec process_chunk offset =
      let* contacts = Database.fetch_contacts_batch ~offset ~limit:chunk_size db in
      match contacts with
      | [] -> Lwt.return_unit
      | batch ->
          let* schedules = 
            batch
            |> Lwt_list.map_p (calculate_schedules ~config ~run_id)
            |> Lwt.map List.concat
          in
          
          let* balanced_schedules = LoadBalancer.distribute_schedules schedules config in
          let* () = Database.insert_schedules db balanced_schedules in
          
          (* Update checkpoint *)
          let* () = Audit.update_checkpoint ~run_id ~contacts_processed:chunk_size db in
          
          process_chunk (offset + chunk_size)
    in
    
    process_chunk 0
end
```

### 5. Database Operations (database.ml)

```ocaml
module Database = struct
  open Caqti_request.Infix
  open Caqti_type.Std

  (* Type-safe queries using Caqti *)
  module Q = struct
    let fetch_contacts_batch =
      (int2 ->* Caqti_type.(tup4 int string (option string) (option ptime_date)))
      "SELECT id, email, zip_code, birthday FROM contacts \
       WHERE id > ? ORDER BY id LIMIT ?"

    let clear_existing_schedules =
      (string ->. unit)
      "DELETE FROM email_schedules \
       WHERE scheduler_run_id != ? \
       AND status IN ('pre-scheduled', 'skipped')"

    let insert_schedule =
      (Caqti_type.(tup6 int string ptime_date string int string) ->. unit)
      "INSERT OR IGNORE INTO email_schedules \
       (contact_id, email_type, scheduled_send_date, status, priority, scheduler_run_id) \
       VALUES (?, ?, ?, ?, ?, ?)"
  end

  (* Connection pool management *)
  let with_transaction (db: Caqti_lwt.connection) f =
    let open Lwt.Syntax in
    let* () = Caqti_lwt.start db in
    Lwt.catch
      (fun () ->
        let* result = f () in
        let* () = Caqti_lwt.commit db in
        Lwt.return result)
      (fun exn ->
        let* () = Caqti_lwt.rollback db in
        Lwt.fail exn)
end
```

### 6. Load Balancing (load_balancer.ml)

```ocaml
module LoadBalancer = struct
  type daily_stats = {
    date: Ptime.date;
    total_count: int;
    ed_count: int;
  }

  (* Implement smoothing algorithm *)
  let smooth_effective_dates schedules config =
    (* Group by date and identify clusters *)
    let daily_counts = count_by_date schedules in
    
    (* Apply jitter to dates over threshold *)
    List.map (fun schedule ->
      match schedule.email_type with
      | Anniversary EffectiveDate when is_over_threshold daily_counts schedule.scheduled_date ->
          apply_jitter schedule config
      | _ -> schedule
    ) schedules
end
```

### 7. Testing Strategy

```ocaml
(* test/test_exclusion_windows.ml *)
open Alcotest

let test_california_birthday_window () =
  let contact = { default_contact with state = Some CA; birthday = Some test_date } in
  let result = calculate_exclusion_window contact in
  check bool "CA birthday window" true (is_excluded result)

let test_year_boundary_window () =
  (* Test window spanning Dec 15 - Jan 15 *)
  let dec_date = make_date 2024 12 20 in
  let jan_date = make_date 2025 1 10 in
  (* Both should be in exclusion window *)

let test_suite = [
  "Exclusion Windows", [
    test_case "California birthday" `Quick test_california_birthday_window;
    test_case "Year boundary" `Quick test_year_boundary_window;
  ];
]
```

### 8. Performance Requirements

1. **Memory Usage**: Stream processing to keep memory under 1GB for 3M contacts
2. **Processing Speed**: Target 100k contacts/minute
3. **Database Optimization**: 
   - Use prepared statements
   - Batch inserts (2000 records/transaction)
   - Proper indexes on all query columns

### 9. Error Handling

```ocaml
type scheduler_error =
  | DatabaseError of string
  | InvalidContactData of { contact_id: int; reason: string }
  | ConfigurationError of string
  | UnexpectedError of exn

let handle_error = function
  | DatabaseError msg -> 
      Log.err (fun m -> m "Database error: %s" msg);
      (* Implement retry logic *)
  | InvalidContactData { contact_id; reason } ->
      Log.warn (fun m -> m "Skipping contact %d: %s" contact_id reason);
      (* Continue processing *)
  | ConfigurationError msg ->
      Log.err (fun m -> m "Configuration error: %s" msg);
      (* Halt processing *)
  | UnexpectedError exn ->
      Log.err (fun m -> m "Unexpected error: %s" (Printexc.to_string exn));
      (* Log and re-raise *)
```

### 10. Deployment Configuration

```yaml
# config/scheduler.yaml
scheduler:
  timezone: "America/Chicago"
  batch_size: 10000
  max_memory_mb: 1024
  
timing:
  birthday_days_before: 14
  effective_date_days_before: 30
  pre_window_buffer: 60
  followup_delay_days: 2
  
load_balancing:
  daily_cap_percentage: 0.07
  ed_soft_limit: 15
  smoothing_window: 5
  
database:
  path: "org-206.sqlite3"
  backup_dir: "./backups"
  backup_retention_days: 7
```

## Implementation Steps

1. **Phase 1**: Core domain types and date calculations
2. **Phase 2**: State rules engine and DSL
3. **Phase 3**: Basic scheduling without load balancing
4. **Phase 4**: Add load balancing and smoothing
5. **Phase 5**: Campaign system integration
6. **Phase 6**: Audit trail and recovery mechanisms
7. **Phase 7**: Performance optimization and testing
8. **Phase 8**: Monitoring and observability

## Success Criteria

1. All date calculations handle edge cases correctly
2. State exclusion rules are properly enforced
3. System can process 3M contacts in under 3 minutes
4. Memory usage stays under 1GB (if possible -- would have more memory if needed to reduce time)
5. Full audit trail for compliance
6. 100% test coverage for business logic
7. Zero data loss on crashes (transactional safety)

## Additional Notes

- Use phantom types for additional type safety where appropriate
- Consider using GADTs for the email type hierarchy
- Implement property-based testing for date calculations
- Use Lwt for concurrent I/O operations
- Profile memory usage with large datasets
- Consider using Flambda for additional optimizations

Remember: The goal is to create a maintainable, type-safe system that makes invalid states unrepresentable at compile time.