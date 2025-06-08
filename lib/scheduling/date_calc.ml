open Date_time
open Dsl

let pre_window_buffer_days = 60

let in_exclusion_window check_date window anchor_date =
  let window_start_offset = -(window.before_days + pre_window_buffer_days) in
  let window_end_offset = window.after_days in
  
  let check_year anchor =
    let base_date = 
      if window.use_month_start then
        let (year, month, _) = anchor in
        (year, month, 1)  (* Use first day of month *)
      else
        anchor
    in
    let window_start = add_days base_date window_start_offset in
    let window_end = add_days base_date window_end_offset in
    compare_date check_date window_start >= 0 &&
    compare_date check_date window_end <= 0
  in
  
  check_year anchor_date ||
  let (year, month, day) = anchor_date in
  let prev_year_anchor = (year - 1, month, day) in
  let next_year_anchor = (year + 1, month, day) in
  check_year prev_year_anchor || check_year next_year_anchor

let calculate_jitter ~contact_id ~event_type ~year ~window_days =
  let hash_input = Printf.sprintf "%d-%s-%d" contact_id event_type year in
  (Hashtbl.hash hash_input) mod window_days - (window_days / 2)

let schedule_time_ct hour minute =
  ((hour, minute, 0), 0)  (* ((hour, minute, second), tz_offset) - CT is 0 offset from our system time *)