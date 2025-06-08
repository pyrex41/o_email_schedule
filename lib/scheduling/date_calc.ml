open Date_time
open Types

let pre_window_buffer_days = 60

let in_exclusion_window check_date window anchor_date =
  let window_start_offset = -(window.before_days + pre_window_buffer_days) in
  let window_end_offset = window.after_days in
  
  let check_year anchor =
    let base_date = 
      if window.use_month_start then
        { anchor with day = 1 }
      else
        anchor
    in
    let window_start = add_days base_date window_start_offset in
    let window_end = add_days base_date window_end_offset in
    compare_date check_date window_start >= 0 &&
    compare_date check_date window_end <= 0
  in
  
  check_year anchor_date ||
  let prev_year_anchor = { anchor_date with year = anchor_date.year - 1 } in
  let next_year_anchor = { anchor_date with year = anchor_date.year + 1 } in
  check_year prev_year_anchor || check_year next_year_anchor

let calculate_jitter ~contact_id ~event_type ~year ~window_days =
  let hash_input = Printf.sprintf "%d-%s-%d" contact_id event_type year in
  (Hashtbl.hash hash_input) mod window_days - (window_days / 2)

let schedule_time_ct hour minute =
  { hour; minute; second = 0 }