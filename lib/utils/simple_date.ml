type date = {
  year: int;
  month: int;
  day: int;
}

type time = {
  hour: int;
  minute: int;
  second: int;
}

type datetime = {
  date: date;
  time: time;
}

let make_date year month day = { year; month; day }
let make_time hour minute second = { hour; minute; second }
let make_datetime date time = { date; time }

let current_date () =
  let tm = Unix.localtime (Unix.time ()) in
  { year = tm.tm_year + 1900; month = tm.tm_mon + 1; day = tm.tm_mday }

let current_datetime () =
  let tm = Unix.localtime (Unix.time ()) in
  {
    date = { year = tm.tm_year + 1900; month = tm.tm_mon + 1; day = tm.tm_mday };
    time = { hour = tm.tm_hour; minute = tm.tm_min; second = tm.tm_sec }
  }

let is_leap_year year =
  (year mod 4 = 0 && year mod 100 <> 0) || (year mod 400 = 0)

let days_in_month year month =
  match month with
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
  | 4 | 6 | 9 | 11 -> 30
  | 2 -> if is_leap_year year then 29 else 28
  | _ -> failwith "Invalid month"

let add_days date n =
  let rec add_days_rec d remaining =
    if remaining = 0 then d
    else if remaining > 0 then
      let days_in_current_month = days_in_month d.year d.month in
      if d.day + remaining <= days_in_current_month then
        { d with day = d.day + remaining }
      else
        let days_used = days_in_current_month - d.day + 1 in
        let new_date = 
          if d.month = 12 then
            { year = d.year + 1; month = 1; day = 1 }
          else
            { d with month = d.month + 1; day = 1 }
        in
        add_days_rec new_date (remaining - days_used)
    else
      let days_to_subtract = -remaining in
      if d.day > days_to_subtract then
        { d with day = d.day - days_to_subtract }
      else
        let new_date = 
          if d.month = 1 then
            let prev_year = d.year - 1 in
            let days_in_dec = days_in_month prev_year 12 in
            { year = prev_year; month = 12; day = days_in_dec }
          else
            let prev_month = d.month - 1 in
            let days_in_prev = days_in_month d.year prev_month in
            { d with month = prev_month; day = days_in_prev }
        in
        add_days_rec new_date (remaining + d.day)
  in
  add_days_rec date n

let compare_date d1 d2 =
  if d1.year <> d2.year then compare d1.year d2.year
  else if d1.month <> d2.month then compare d1.month d2.month
  else compare d1.day d2.day

let diff_days d1 d2 =
  let days_since_epoch date =
    let rec count_days acc year =
      if year >= date.year then acc
      else
        let days_in_year = if is_leap_year year then 366 else 365 in
        count_days (acc + days_in_year) (year + 1)
    in
    let year_days = count_days 0 1970 in
    let month_days = ref 0 in
    for m = 1 to date.month - 1 do
      month_days := !month_days + days_in_month date.year m
    done;
    year_days + !month_days + date.day
  in
  days_since_epoch d1 - days_since_epoch d2

let next_anniversary today event_date =
  let this_year_candidate = { event_date with year = today.year } in
  let this_year_candidate = 
    if event_date.month = 2 && event_date.day = 29 && not (is_leap_year today.year) then
      { this_year_candidate with day = 28 }
    else
      this_year_candidate
  in
  
  if compare_date this_year_candidate today >= 0 then
    this_year_candidate
  else
    let next_year = today.year + 1 in
    let next_year_candidate = { event_date with year = next_year } in
    if event_date.month = 2 && event_date.day = 29 && not (is_leap_year next_year) then
      { next_year_candidate with day = 28 }
    else
      next_year_candidate

let string_of_date d = Printf.sprintf "%04d-%02d-%02d" d.year d.month d.day
let string_of_time t = Printf.sprintf "%02d:%02d:%02d" t.hour t.minute t.second
let string_of_datetime dt = 
  Printf.sprintf "%s %s" (string_of_date dt.date) (string_of_time dt.time)

let parse_date date_str =
  match String.split_on_char '-' date_str with
  | [year_str; month_str; day_str] ->
      let year = int_of_string year_str in
      let month = int_of_string month_str in
      let day = int_of_string day_str in
      { year; month; day }
  | _ -> failwith ("Invalid date format: " ^ date_str)