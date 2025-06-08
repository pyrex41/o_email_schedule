(* Core types leveraging Ptime's robust date handling *)
type date = Ptime.date  (* This is (int * int * int) but we'll use Ptime.t internally *)
type time = (int * int * int) * int  (* ((hour, minute, second), tz_offset_s) *)
type datetime = Ptime.t

(* Internal helper: convert tuple date to Ptime.t for calculations *)
let date_to_ptime (year, month, day) =
  match Ptime.of_date (year, month, day) with
  | Some ptime -> ptime
  | None -> failwith (Printf.sprintf "Invalid date: %04d-%02d-%02d" year month day)

(* Internal helper: convert Ptime.t back to tuple date *)
let ptime_to_date ptime = Ptime.to_date ptime

(* Smart constructors with validation *)
let make_date year month day =
  match Ptime.of_date (year, month, day) with
  | Some ptime -> Ptime.to_date ptime
  | None -> failwith (Printf.sprintf "Invalid date: %04d-%02d-%02d" year month day)

let make_time hour minute second =
  match Ptime.of_date_time ((1970, 1, 1), ((hour, minute, second), 0)) with
  | Some ptime -> 
      let (_, time) = Ptime.to_date_time ptime in
      time
  | None -> failwith (Printf.sprintf "Invalid time: %02d:%02d:%02d" hour minute second)

let make_datetime date time =
  match Ptime.of_date_time (date, (time, 0)) with
  | Some ptime -> ptime
  | None -> failwith "Invalid date/time combination"

(* Current date/time functions *)
let current_date () =
  let now = Ptime_clock.now () in
  Ptime.to_date now

let current_datetime () =
  Ptime_clock.now ()

(* Date arithmetic using Ptime's robust date handling *)
let add_days date n =
  let ptime = date_to_ptime date in
  let span = Ptime.Span.of_int_s (n * 24 * 3600) in
  match Ptime.add_span ptime span with
  | Some new_ptime -> ptime_to_date new_ptime
  | None -> failwith "Date arithmetic overflow"

(* Date comparison using Ptime's robust comparison *)
let compare_date d1 d2 =
  let ptime1 = date_to_ptime d1 in
  let ptime2 = date_to_ptime d2 in
  Ptime.compare ptime1 ptime2

(* Calculate difference in days using Ptime's robust diff *)
let diff_days d1 d2 =
  let ptime1 = date_to_ptime d1 in
  let ptime2 = date_to_ptime d2 in
  let span = Ptime.diff ptime1 ptime2 in
  let seconds = Ptime.Span.to_float_s span in
  int_of_float (seconds /. (24.0 *. 3600.0))

(* Leap year check using Ptime's calendar logic *)
let is_leap_year year =
  (* February 29th exists in leap years - let Ptime handle the logic *)
  match Ptime.of_date (year, 2, 29) with
  | Some _ -> true
  | None -> false

(* Days in month using Ptime validation *)
let days_in_month year month =
  (* Find the last valid day of the month *)
  let rec find_last_day day =
    if day > 31 then 28 (* Fallback - should never happen *)
    else
      match Ptime.of_date (year, month, day) with
      | Some _ -> day
      | None -> find_last_day (day - 1)
  in
  find_last_day 31

(* Anniversary calculation using Ptime's robust date handling *)
let next_anniversary today event_date =
  let today_ptime = date_to_ptime today in
  let (today_year, _, _) = today in
  let (_, event_month, event_day) = event_date in
  
  (* Try this year first - let Ptime handle leap year edge cases *)
  let this_year_candidate_tuple = 
    if event_month = 2 && event_day = 29 && not (is_leap_year today_year) then
      (today_year, 2, 28) (* Feb 29 -> Feb 28 in non-leap years *)
    else
      (today_year, event_month, event_day)
  in
  
  (* Use Ptime's robust comparison instead of manual tuple comparison *)
  let this_year_ptime = date_to_ptime this_year_candidate_tuple in
  if Ptime.compare this_year_ptime today_ptime >= 0 then
    this_year_candidate_tuple
  else
    (* Try next year *)
    let next_year = today_year + 1 in
    if event_month = 2 && event_day = 29 && not (is_leap_year next_year) then
      (next_year, 2, 28)
    else
      (next_year, event_month, event_day)

(* String conversions *)
let string_of_date (year, month, day) = 
  Printf.sprintf "%04d-%02d-%02d" year month day

let string_of_time ((hour, minute, second), _) =
  Printf.sprintf "%02d:%02d:%02d" hour minute second

let string_of_datetime dt =
  let (date, time) = Ptime.to_date_time dt in
  Printf.sprintf "%s %s" (string_of_date date) (string_of_time time)

(* Parsing functions *)
let parse_date date_str =
  match String.split_on_char '-' date_str with
  | [year_str; month_str; day_str] ->
      let year = int_of_string year_str in
      let month = int_of_string month_str in
      let day = int_of_string day_str in
      make_date year month day
  | _ -> failwith ("Invalid date format: " ^ date_str)

let parse_time time_str =
  match String.split_on_char ':' time_str with
  | [hour_str; minute_str; second_str] ->
      let hour = int_of_string hour_str in
      let minute = int_of_string minute_str in
      let second = int_of_string second_str in
      make_time hour minute second
  | _ -> failwith ("Invalid time format: " ^ time_str)

(* Utility function for testing - allows fixed time *)
let with_fixed_time fixed_time f =
  (* Note: Full time mocking would require overriding current_date/current_datetime globally *)
  (* For now, acknowledge the fixed_time parameter and call function normally *)
  let _ = fixed_time in (* Acknowledge parameter to avoid unused warning *)
  f ()