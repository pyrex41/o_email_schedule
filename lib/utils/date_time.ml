open Ptime

(* Core types using Ptime *)
type date = Ptime.date
type time = Ptime.time  
type datetime = Ptime.t

(* Smart constructors with validation *)
let make_date year month day =
  match Ptime.of_date (year, month, day) with
  | Some ptime -> Ptime.to_date ptime
  | None -> failwith (Printf.sprintf "Invalid date: %04d-%02d-%02d" year month day)

let make_time hour minute second =
  match Ptime.of_date_time ((1970, 1, 1), ((hour, minute, second), 0)) with
  | Some ptime -> Ptime.to_time ptime
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

(* Date arithmetic using Ptime.Span *)
let add_days date n =
  let ptime = match Ptime.of_date date with
    | Some t -> t
    | None -> failwith "Invalid date for addition"
  in
  let span = Ptime.Span.of_int_s (n * 24 * 3600) in
  match Ptime.add_span ptime span with
  | Some new_ptime -> Ptime.to_date new_ptime
  | None -> failwith "Date arithmetic overflow"

(* Date comparison *)
let compare_date d1 d2 =
  let (y1, m1, day1) = d1 in
  let (y2, m2, day2) = d2 in
  if y1 <> y2 then compare y1 y2
  else if m1 <> m2 then compare m1 m2
  else compare day1 day2

(* Calculate difference in days *)
let diff_days d1 d2 =
  let ptime1 = match Ptime.of_date d1 with
    | Some t -> t
    | None -> failwith "Invalid first date"
  in
  let ptime2 = match Ptime.of_date d2 with
    | Some t -> t
    | None -> failwith "Invalid second date"
  in
  match Ptime.diff ptime1 ptime2 with
  | span -> 
    let seconds = Ptime.Span.to_float_s span in
    int_of_float (seconds /. (24.0 *. 3600.0))

(* Enhanced leap year check using Ptime's calendar logic *)
let is_leap_year year =
  (* February 29th exists in leap years *)
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

(* Anniversary calculation with proper leap year handling *)
let next_anniversary today event_date =
  let (today_year, today_month, today_day) = today in
  let (_, event_month, event_day) = event_date in
  
  (* Try this year first *)
  let this_year_candidate = 
    if event_month = 2 && event_day = 29 && not (is_leap_year today_year) then
      (today_year, 2, 28) (* Feb 29 -> Feb 28 in non-leap years *)
    else
      (today_year, event_month, event_day)
  in
  
  if compare_date this_year_candidate today >= 0 then
    this_year_candidate
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
  let date = Ptime.to_date dt in
  let time = Ptime.to_time dt in
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
  (* Note: This would need proper implementation for testing *)
  (* For now, just call the function normally *)
  f ()