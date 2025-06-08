(* Core types leveraging Ptime's robust date handling *)
type date = Ptime.date  (* This is (int * int * int) but we'll use Ptime.t internally *)
type time = (int * int * int) * int  (* ((hour, minute, second), tz_offset_s) *)
type datetime = Ptime.t

(** 
 * [date_to_ptime]: Internal helper to convert date tuple to Ptime.t for calculations
 * 
 * Purpose:
 *   Safely converts date tuple format to Ptime.t for robust date arithmetic
 *   operations while providing clear error messages for invalid dates.
 * 
 * Parameters:
 *   - (year, month, day): Date tuple with integer components
 * 
 * Returns:
 *   Ptime.t representation suitable for date calculations
 * 
 * Business Logic:
 *   - Validates date components during conversion
 *   - Leverages Ptime's robust calendar logic
 *   - Handles leap year validation automatically
 *   - Provides basis for all date arithmetic operations
 * 
 * Usage Example:
 *   Used internally by add_days, compare_date, and anniversary calculations
 * 
 * Error Cases:
 *   - Fails with descriptive message for invalid dates (e.g., Feb 30)
 * 
 * @performance
 *)
let date_to_ptime (year, month, day) =
  match Ptime.of_date (year, month, day) with
  | Some ptime -> ptime
  | None -> failwith (Printf.sprintf "Invalid date: %04d-%02d-%02d" year month day)

(** 
 * [ptime_to_date]: Internal helper to convert Ptime.t back to date tuple
 * 
 * Purpose:
 *   Converts Ptime.t representation back to date tuple format for external use
 *   while maintaining precision and avoiding calculation errors.
 * 
 * Parameters:
 *   - ptime: Ptime.t instance from date calculations
 * 
 * Returns:
 *   Date tuple (year, month, day) matching system date format
 * 
 * Business Logic:
 *   - Preserves exact date values from calculations
 *   - Maintains consistency with external date format
 *   - Ensures no precision loss during conversion
 * 
 * Usage Example:
 *   Used internally by add_days and next_anniversary for result conversion
 * 
 * Error Cases:
 *   - None expected (Ptime.t should always convert to valid date)
 * 
 * @performance
 *)
let ptime_to_date ptime = Ptime.to_date ptime

(** 
 * [make_date]: Smart constructor for validated date creation
 * 
 * Purpose:
 *   Creates date tuples with comprehensive validation to prevent invalid dates
 *   from entering the system and causing calculation errors.
 * 
 * Parameters:
 *   - year: Four-digit year value
 *   - month: Month value (1-12)
 *   - day: Day value (1-31, validated against month/year)
 * 
 * Returns:
 *   Valid date tuple after successful validation
 * 
 * Business Logic:
 *   - Validates date components against calendar rules
 *   - Handles leap year validation for February 29
 *   - Ensures month/day combinations are valid
 *   - Provides fail-fast validation for data integrity
 * 
 * Usage Example:
 *   Used when creating dates from user input or database values
 * 
 * Error Cases:
 *   - Fails with descriptive message for invalid date combinations
 * 
 * @data_flow
 *)
let make_date year month day =
  match Ptime.of_date (year, month, day) with
  | Some ptime -> Ptime.to_date ptime
  | None -> failwith (Printf.sprintf "Invalid date: %04d-%02d-%02d" year month day)

(** 
 * [make_time]: Smart constructor for validated time creation
 * 
 * Purpose:
 *   Creates time tuples with validation to ensure time components are within
 *   valid ranges for consistent time handling across the system.
 * 
 * Parameters:
 *   - hour: Hour value (0-23)
 *   - minute: Minute value (0-59)
 *   - second: Second value (0-59)
 * 
 * Returns:
 *   Valid time tuple with timezone offset after successful validation
 * 
 * Business Logic:
 *   - Validates time components against 24-hour clock rules
 *   - Uses UTC timezone offset for consistency
 *   - Provides foundation for scheduling time calculations
 * 
 * Usage Example:
 *   Used when creating scheduled send times for email delivery
 * 
 * Error Cases:
 *   - Fails with descriptive message for invalid time values
 * 
 * @data_flow
 *)
let make_time hour minute second =
  match Ptime.of_date_time ((1970, 1, 1), ((hour, minute, second), 0)) with
  | Some ptime -> 
      let (_, time) = Ptime.to_date_time ptime in
      time
  | None -> failwith (Printf.sprintf "Invalid time: %02d:%02d:%02d" hour minute second)

(** 
 * [make_datetime]: Combines date and time into datetime representation
 * 
 * Purpose:
 *   Creates complete datetime objects for precise scheduling and timestamp
 *   operations while validating the date/time combination.
 * 
 * Parameters:
 *   - date: Date tuple (year, month, day)
 *   - time: Time tuple ((hour, minute, second), timezone_offset)
 * 
 * Returns:
 *   Ptime.t datetime representation for scheduling operations
 * 
 * Business Logic:
 *   - Combines separate date and time components safely
 *   - Validates the complete datetime combination
 *   - Provides basis for precise scheduling calculations
 * 
 * Usage Example:
 *   Used when creating specific send timestamps for email schedules
 * 
 * Error Cases:
 *   - Fails for invalid date/time combinations
 * 
 * @data_flow
 *)
let make_datetime date time =
  match Ptime.of_date_time (date, (time, 0)) with
  | Some ptime -> ptime
  | None -> failwith "Invalid date/time combination"

(** 
 * [current_date]: Gets current system date for scheduling calculations
 * 
 * Purpose:
 *   Provides current date as baseline for anniversary calculations and
 *   scheduling operations, ensuring consistent "today" reference.
 * 
 * Parameters:
 *   - None
 * 
 * Returns:
 *   Current date tuple representing today's date
 * 
 * Business Logic:
 *   - Uses system clock for current date determination
 *   - Provides consistent baseline for all date calculations
 *   - Ensures scheduling operates relative to actual current date
 * 
 * Usage Example:
 *   Called by anniversary calculation and exclusion window functions
 * 
 * Error Cases:
 *   - None expected (system clock should always be available)
 * 
 * @integration_point
 *)
let current_date () =
  let now = Ptime_clock.now () in
  Ptime.to_date now

(** 
 * [current_datetime]: Gets current system datetime for run tracking
 * 
 * Purpose:
 *   Provides precise current timestamp for run identification, performance
 *   tracking, and audit trail creation in scheduling operations.
 * 
 * Parameters:
 *   - None
 * 
 * Returns:
 *   Current Ptime.t datetime with full precision
 * 
 * Business Logic:
 *   - Captures precise execution timestamp
 *   - Enables performance monitoring and run tracking
 *   - Provides audit trail for scheduling operations
 * 
 * Usage Example:
 *   Used by generate_run_id and performance monitoring functions
 * 
 * Error Cases:
 *   - None expected (system clock should always be available)
 * 
 * @integration_point
 *)
let current_datetime () =
  Ptime_clock.now ()

(** 
 * [add_days]: Adds specified number of days to a date with robust arithmetic
 * 
 * Purpose:
 *   Performs reliable date arithmetic that handles month boundaries, leap years,
 *   and year transitions correctly for scheduling calculations.
 * 
 * Parameters:
 *   - date: Starting date tuple
 *   - n: Number of days to add (positive or negative)
 * 
 * Returns:
 *   New date tuple after adding the specified days
 * 
 * Business Logic:
 *   - Handles month and year boundaries correctly
 *   - Accounts for leap years in February calculations
 *   - Supports both forward and backward date arithmetic
 *   - Uses Ptime's robust calendar arithmetic internally
 * 
 * Usage Example:
 *   Used for calculating send dates based on days_before settings
 * 
 * Error Cases:
 *   - Fails on arithmetic overflow (extremely large day values)
 * 
 * @performance @business_rule
 *)
let add_days date n =
  let ptime = date_to_ptime date in
  let span = Ptime.Span.of_int_s (n * 24 * 3600) in
  match Ptime.add_span ptime span with
  | Some new_ptime -> ptime_to_date new_ptime
  | None -> failwith "Date arithmetic overflow"

(** 
 * [compare_date]: Compares two dates with robust calendar logic
 * 
 * Purpose:
 *   Provides reliable date comparison that handles edge cases and provides
 *   consistent ordering for scheduling and exclusion window operations.
 * 
 * Parameters:
 *   - d1: First date tuple for comparison
 *   - d2: Second date tuple for comparison
 * 
 * Returns:
 *   Integer indicating comparison result (-1, 0, 1)
 * 
 * Business Logic:
 *   - Uses Ptime's robust comparison logic
 *   - Handles leap year and month boundary edge cases
 *   - Provides consistent ordering for date-based decisions
 * 
 * Usage Example:
 *   Used by exclusion window and anniversary calculation functions
 * 
 * Error Cases:
 *   - None expected for valid dates
 * 
 * @performance
 *)
let compare_date d1 d2 =
  let ptime1 = date_to_ptime d1 in
  let ptime2 = date_to_ptime d2 in
  Ptime.compare ptime1 ptime2

(** 
 * [diff_days]: Calculates difference between dates in days
 * 
 * Purpose:
 *   Computes exact day difference between dates for spread calculations,
 *   exclusion window timing, and scheduling distribution.
 * 
 * Parameters:
 *   - d1: First date tuple (subtracted from)
 *   - d2: Second date tuple (subtracted)
 * 
 * Returns:
 *   Integer number of days difference (d1 - d2)
 * 
 * Business Logic:
 *   - Calculates exact day difference using robust calendar arithmetic
 *   - Handles month boundaries and leap years correctly
 *   - Provides foundation for date range calculations
 * 
 * Usage Example:
 *   Used by calculate_spread_date for campaign distribution
 * 
 * Error Cases:
 *   - None expected for valid dates
 * 
 * @performance @business_rule
 *)
let diff_days d1 d2 =
  let ptime1 = date_to_ptime d1 in
  let ptime2 = date_to_ptime d2 in
  let span = Ptime.diff ptime1 ptime2 in
  let seconds = Ptime.Span.to_float_s span in
  int_of_float (seconds /. (24.0 *. 3600.0))

(** 
 * [is_leap_year]: Determines if year is a leap year using robust logic
 * 
 * Purpose:
 *   Accurately identifies leap years for February 29 handling in anniversary
 *   calculations and date validation operations.
 * 
 * Parameters:
 *   - year: Four-digit year value to check
 * 
 * Returns:
 *   Boolean indicating if year is a leap year
 * 
 * Business Logic:
 *   - Uses Ptime's calendar logic for accurate leap year determination
 *   - Handles century years and other edge cases correctly
 *   - Critical for February 29 anniversary handling
 * 
 * Usage Example:
 *   Used by next_anniversary for leap year date adjustments
 * 
 * Error Cases:
 *   - None expected for valid year values
 * 
 * @business_rule
 *)
let is_leap_year year =
  (* February 29th exists in leap years - let Ptime handle the logic *)
  match Ptime.of_date (year, 2, 29) with
  | Some _ -> true
  | None -> false

(** 
 * [days_in_month]: Calculates number of days in specified month/year
 * 
 * Purpose:
 *   Determines exact days in month accounting for leap years, providing
 *   foundation for date validation and calendar calculations.
 * 
 * Parameters:
 *   - year: Year value for leap year context
 *   - month: Month value (1-12)
 * 
 * Returns:
 *   Integer number of days in the specified month
 * 
 * Business Logic:
 *   - Accounts for leap years in February calculations
 *   - Uses Ptime validation to find last valid day
 *   - Provides accurate month length for date operations
 * 
 * Usage Example:
 *   Used internally for date validation and calendar operations
 * 
 * Error Cases:
 *   - Returns fallback value for invalid month values
 * 
 * @performance
 *)
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

(** 
 * [next_anniversary]: Calculates next occurrence of anniversary date
 * 
 * Purpose:
 *   Core anniversary logic that finds the next occurrence of a significant date
 *   relative to today, handling leap year edge cases for February 29 birthdays.
 * 
 * Parameters:
 *   - today: Current date for calculation reference
 *   - event_date: Original anniversary date (birthday, effective date)
 * 
 * Returns:
 *   Date tuple representing next anniversary occurrence
 * 
 * Business Logic:
 *   - Tries current year first, then next year if already passed
 *   - Handles February 29 leap year birthdays by adjusting to February 28
 *   - Uses robust date comparison to determine if anniversary has passed
 *   - Critical for accurate anniversary email scheduling
 * 
 * Usage Example:
 *   Used by calculate_anniversary_emails for birthday and effective date scheduling
 * 
 * Error Cases:
 *   - None expected (handles leap year edge cases gracefully)
 * 
 * @business_rule @data_flow
 *)
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

(** 
 * [string_of_date]: Converts date tuple to standardized string format
 * 
 * Purpose:
 *   Provides consistent string representation of dates for logging, database
 *   storage, and user interface display across the system.
 * 
 * Parameters:
 *   - (year, month, day): Date tuple to format
 * 
 * Returns:
 *   String in ISO 8601 format "YYYY-MM-DD"
 * 
 * Business Logic:
 *   - Uses zero-padded format for consistent string length
 *   - Follows ISO 8601 standard for international compatibility
 *   - Provides readable format for logs and debugging
 *   - Ensures consistent date representation across components
 * 
 * Usage Example:
 *   Used for logging, database queries, and debug output
 * 
 * Error Cases:
 *   - None expected (all valid date tuples should format correctly)
 * 
 * @integration_point
 *)
let string_of_date (year, month, day) = 
  Printf.sprintf "%04d-%02d-%02d" year month day

(** 
 * [string_of_time]: Converts time tuple to standardized string format
 * 
 * Purpose:
 *   Provides consistent string representation of times for logging and
 *   scheduling display, focusing on the time component only.
 * 
 * Parameters:
 *   - ((hour, minute, second), _): Time tuple with timezone offset (ignored)
 * 
 * Returns:
 *   String in 24-hour format "HH:MM:SS"
 * 
 * Business Logic:
 *   - Uses 24-hour format for clarity and consistency
 *   - Zero-pads all components for fixed-width display
 *   - Ignores timezone offset for local time display
 *   - Provides readable format for schedule times
 * 
 * Usage Example:
 *   Used for displaying scheduled send times in logs and interfaces
 * 
 * Error Cases:
 *   - None expected (all valid time tuples should format correctly)
 * 
 * @integration_point
 *)
let string_of_time ((hour, minute, second), _) =
  Printf.sprintf "%02d:%02d:%02d" hour minute second

(** 
 * [string_of_datetime]: Converts datetime to combined date/time string
 * 
 * Purpose:
 *   Provides comprehensive string representation of complete datetime for
 *   precise logging, run tracking, and timestamp display.
 * 
 * Parameters:
 *   - dt: Ptime.t datetime to format
 * 
 * Returns:
 *   String combining date and time "YYYY-MM-DD HH:MM:SS"
 * 
 * Business Logic:
 *   - Combines date and time formatting for complete timestamp
 *   - Uses space separator for readability
 *   - Provides precise timestamp for audit trails
 *   - Maintains consistency with component string formats
 * 
 * Usage Example:
 *   Used for run ID generation and detailed logging timestamps
 * 
 * Error Cases:
 *   - None expected (valid datetime should always format correctly)
 * 
 * @integration_point
 *)
let string_of_datetime dt =
  let (date, time) = Ptime.to_date_time dt in
  Printf.sprintf "%s %s" (string_of_date date) (string_of_time time)

(** 
 * [parse_date]: Parses ISO date string into date tuple with validation
 * 
 * Purpose:
 *   Safely converts string date representations from external sources into
 *   validated date tuples for internal processing.
 * 
 * Parameters:
 *   - date_str: String in "YYYY-MM-DD" format
 * 
 * Returns:
 *   Valid date tuple after parsing and validation
 * 
 * Business Logic:
 *   - Expects ISO 8601 format with dash separators
 *   - Validates parsed components using make_date validation
 *   - Provides safe conversion from external string data
 *   - Ensures invalid dates are rejected early
 * 
 * Usage Example:
 *   Used when parsing dates from configuration files or API inputs
 * 
 * Error Cases:
 *   - Fails with descriptive message for invalid format or invalid dates
 * 
 * @data_flow
 *)
let parse_date date_str =
  match String.split_on_char '-' date_str with
  | [year_str; month_str; day_str] ->
      let year = int_of_string year_str in
      let month = int_of_string month_str in
      let day = int_of_string day_str in
      make_date year month day
  | _ -> failwith ("Invalid date format: " ^ date_str)

(** 
 * [parse_time]: Parses time string into time tuple with validation
 * 
 * Purpose:
 *   Safely converts string time representations from external sources into
 *   validated time tuples for scheduling operations.
 * 
 * Parameters:
 *   - time_str: String in "HH:MM:SS" format
 * 
 * Returns:
 *   Valid time tuple after parsing and validation
 * 
 * Business Logic:
 *   - Expects 24-hour format with colon separators
 *   - Validates parsed components using make_time validation
 *   - Provides safe conversion from external string data
 *   - Ensures invalid times are rejected early
 * 
 * Usage Example:
 *   Used when parsing send times from configuration files
 * 
 * Error Cases:
 *   - Fails with descriptive message for invalid format or invalid times
 * 
 * @data_flow
 *)
let parse_time time_str =
  match String.split_on_char ':' time_str with
  | [hour_str; minute_str; second_str] ->
      let hour = int_of_string hour_str in
      let minute = int_of_string minute_str in
      let second = int_of_string second_str in
      make_time hour minute second
  | _ -> failwith ("Invalid time format: " ^ time_str)

(** 
 * [with_fixed_time]: Utility function for testing with controlled time
 * 
 * Purpose:
 *   Provides mechanism for testing time-dependent functionality with fixed
 *   time values, enabling deterministic test results.
 * 
 * Parameters:
 *   - fixed_time: Fixed time value for testing (currently acknowledged but not used)
 *   - f: Function to execute with controlled time context
 * 
 * Returns:
 *   Result of executing function f
 * 
 * Business Logic:
 *   - Acknowledges fixed time parameter for future implementation
 *   - Currently passes through to normal function execution
 *   - Provides foundation for comprehensive time mocking
 *   - Enables deterministic testing of scheduling logic
 * 
 * Usage Example:
 *   Used in test suites to control time-dependent behavior
 * 
 * Error Cases:
 *   - None expected (passes through underlying function errors)
 * 
 * @integration_point
 *)
let with_fixed_time fixed_time f =
  (* Note: Full time mocking would require overriding current_date/current_datetime globally *)
  (* For now, acknowledge the fixed_time parameter and call function normally *)
  let _ = fixed_time in (* Acknowledge parameter to avoid unused warning *)
  f ()