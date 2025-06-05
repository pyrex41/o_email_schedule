(* Date calculation utilities for email scheduling *)

open Ptime
open Domain.Types
open Rules.Dsl

(* Constants *)
let pre_window_buffer_days = 60

(* Utility functions for date manipulation *)
let days_in_month year month =
  let is_leap_year year =
    (year mod 4 = 0 && year mod 100 <> 0) || (year mod 400 = 0)
  in
  match month with
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if is_leap_year year then 29 else 28
  | _ -> failwith "Invalid month"

let add_days date days =
  match Ptime.add_span date (Ptime.Span.of_int_s (days * 24 * 3600)) with
  | Some d -> Ok d
  | None -> Error "Date arithmetic overflow"

let sub_days date days =
  match Ptime.sub_span date (Ptime.Span.of_int_s (days * 24 * 3600)) with
  | Some d -> Ok d
  | None -> Error "Date arithmetic underflow"

let date_of_ymd year month day =
  match Ptime.of_date (year, month, day) with
  | Some d -> Ok d
  | None -> Error (Printf.sprintf "Invalid date: %d-%02d-%02d" year month day)

let ymd_of_date date =
  Ptime.to_date date

(* Calculate next anniversary from today *)
let next_anniversary ~today ~event_date =
  let (today_year, today_month, today_day) = ymd_of_date today in
  let (_, event_month, event_day) = ymd_of_date event_date in
  
  (* Handle February 29th in non-leap years *)
  let adjusted_day = 
    if event_month = 2 && event_day = 29 && not (today_year mod 4 = 0) then
      28
    else 
      event_day
  in
  
  (* Try this year's anniversary first *)
  let this_year_result = date_of_ymd today_year event_month adjusted_day in
  match this_year_result with
  | Error _ -> 
      (* If this year fails, try next year *)
      date_of_ymd (today_year + 1) event_month adjusted_day
  | Ok this_year_anniversary ->
      (* Check if this year's anniversary has already passed *)
      if Ptime.compare this_year_anniversary today <= 0 then
        (* Anniversary has passed, use next year *)
        let next_year = today_year + 1 in
        let next_year_day = 
          if event_month = 2 && event_day = 29 && not (next_year mod 4 = 0) then
            28
          else
            event_day
        in
        date_of_ymd next_year event_month next_year_day
      else
        (* This year's anniversary is in the future *)
        Ok this_year_anniversary

(* Calculate jitter for load balancing using deterministic hash *)
let calculate_jitter ~contact_id ~event_type ~year ~window_days =
  let hash_input = Printf.sprintf "%d-%s-%d" contact_id event_type year in
  let hash_value = Hashtbl.hash hash_input in
  (hash_value mod window_days) - (window_days / 2)

(* Check if a date falls within an exclusion window *)
let in_exclusion_window ~check_date ~window ~anchor_date =
  let { before_days; after_days; use_month_start } = window in
  
  (* Determine the actual anchor date *)
  let actual_anchor = 
    if use_month_start then
      let (year, month, _) = ymd_of_date anchor_date in
      match date_of_ymd year month 1 with
      | Ok d -> d
      | Error _ -> anchor_date
    else
      anchor_date
  in
  
  (* Calculate window bounds with pre-window buffer *)
  let extended_before = before_days + pre_window_buffer_days in
  
  match sub_days actual_anchor extended_before, add_days actual_anchor after_days with
  | Ok window_start, Ok window_end ->
      (* Handle windows that span across years *)
      let check_in_window start_date end_date =
        Ptime.compare check_date start_date >= 0 && 
        Ptime.compare check_date end_date <= 0
      in
      
      if Ptime.compare window_start window_end <= 0 then
        (* Normal window within same year *)
        check_in_window window_start window_end
      else
        (* Window spans years - check if we're in either part *)
        let (check_year, _, _) = ymd_of_date check_date in
        let (start_year, _, _) = ymd_of_date window_start in
        let (end_year, _, _) = ymd_of_date window_end in
        
        (check_year = start_year && Ptime.compare check_date window_start >= 0) ||
        (check_year = end_year && Ptime.compare check_date window_end <= 0)
  | _ -> false

(* Check if a contact is in an exclusion window for a specific email type *)
let contact_in_exclusion_window ~contact ~email_type ~check_date =
  match contact.state with
  | None -> false
  | Some state ->
      let rule = rules_for_state state in
      if not (rule_applies_to_email_type rule email_type) then
        false
      else
        match get_window_config rule with
        | None -> 
            (* Year-round exclusion *)
            rule = YearRoundExclusion
        | Some window ->
            let anchor_date_opt = match email_type with
              | Anniversary Birthday -> contact.birthday
              | Anniversary EffectiveDate -> contact.effective_date
              | _ -> None
            in
            match anchor_date_opt with
            | None -> false
            | Some anchor_date ->
                match next_anniversary ~today:check_date ~event_date:anchor_date with
                | Ok anniversary_date -> 
                    in_exclusion_window ~check_date ~window ~anchor_date:anniversary_date
                | Error _ -> false

(* Calculate send date for different email types *)
let calculate_send_date ~today ~contact ~email_type ~config =
  match email_type with
  | Anniversary Birthday ->
      (match contact.birthday with
       | None -> Error "Contact has no birthday"
       | Some birthday ->
           match next_anniversary ~today ~event_date:birthday with
           | Ok anniversary -> 
               sub_days anniversary config.birthday_days_before
           | Error e -> Error e)
  
  | Anniversary EffectiveDate ->
      (match contact.effective_date with
       | None -> Error "Contact has no effective date"
       | Some effective_date ->
           match next_anniversary ~today ~event_date:effective_date with
           | Ok anniversary ->
               sub_days anniversary config.effective_date_days_before
           | Error e -> Error e)
  
  | Anniversary AEP ->
      let (current_year, _, _) = ymd_of_date today in
      date_of_ymd current_year 9 15  (* September 15th *)
  
  | Anniversary PostWindow ->
      (* Calculate when exclusion window ends *)
      (match contact.state, contact.birthday with
       | Some state, Some birthday ->
           let rule = rules_for_state state in
           (match get_window_config rule with
            | Some window ->
                (match next_anniversary ~today ~event_date:birthday with
                 | Ok anniversary ->
                     add_days anniversary window.after_days
                 | Error e -> Error e)
            | None -> Error "No window configuration for post-window email")
       | _ -> Error "Contact missing state or birthday for post-window email")
  
  | Campaign { days_before_event; _ } ->
      (* For campaigns, we need the trigger date from contact_campaigns table *)
      (* This would typically be passed in as a parameter *)
      Error "Campaign send date calculation requires trigger date"
  
  | Followup _ ->
      (* Followups are scheduled relative to initial email send date *)
      add_days today config.followup_delay_days

(* Apply jitter for load balancing *)
let apply_jitter ~original_date ~contact_id ~email_type ~window_days =
  let (year, _, _) = ymd_of_date original_date in
  let event_type_str = string_of_email_type email_type in
  let jitter = calculate_jitter ~contact_id ~event_type:event_type_str ~year ~window_days in
  add_days original_date jitter

(* Utility function to check if date is in the past *)
let is_past_date ~check_date ~reference_date =
  Ptime.compare check_date reference_date < 0

(* Get current Central Time *)
let get_current_ct () =
  match Ptime_clock.now () with
  | None -> Error "Could not get current time"
  | Some now -> Ok now

(* Date range utilities *)
let dates_between start_date end_date =
  let rec loop acc current =
    if Ptime.compare current end_date > 0 then
      List.rev acc
    else
      match add_days current 1 with
      | Ok next_date -> loop (current :: acc) next_date
      | Error _ -> List.rev acc
  in
  loop [] start_date

(* Business day calculations (excluding weekends) *)
let is_weekend date =
  let tm = Ptime.to_date_time date in
  let (_, _, _, weekday) = tm in
  weekday = 6 || weekday = 0  (* Saturday or Sunday *)

let next_business_day date =
  let rec find_next current =
    if is_weekend current then
      match add_days current 1 with
      | Ok next_day -> find_next next_day
      | Error e -> Error e
    else
      Ok current
  in
  find_next date