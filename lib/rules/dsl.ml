open Types

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

let birthday_window ~before ~after ?(use_month_start=false) () =
  BirthdayWindow { before_days = before; after_days = after; use_month_start }

let effective_date_window ~before ~after () =
  EffectiveDateWindow { before_days = before; after_days = after; use_month_start = false }

let year_round = YearRoundExclusion
let no_exclusion = NoExclusion

let rules_for_state = function
  | CA -> birthday_window ~before:30 ~after:60 ()
  | ID -> birthday_window ~before:0 ~after:63 ()
  | KY -> birthday_window ~before:0 ~after:60 ()
  | MD -> birthday_window ~before:0 ~after:30 ()
  | NV -> birthday_window ~before:0 ~after:60 ~use_month_start:true ()
  | OK -> birthday_window ~before:0 ~after:60 ()
  | OR -> birthday_window ~before:0 ~after:31 ()
  | VA -> birthday_window ~before:0 ~after:30 ()
  | MO -> effective_date_window ~before:30 ~after:33 ()
  | CT | MA | NY | WA -> year_round
  | Other _ -> no_exclusion

let has_exclusion_window state =
  match rules_for_state state with
  | NoExclusion -> false
  | _ -> true

let is_year_round_exclusion state =
  match rules_for_state state with
  | YearRoundExclusion -> true
  | _ -> false

let get_window_for_email_type state email_type =
  match rules_for_state state, email_type with
  | BirthdayWindow w, Anniversary Birthday -> Some w
  | EffectiveDateWindow w, Anniversary EffectiveDate -> Some w
  | YearRoundExclusion, Anniversary _ -> None
  | _, _ -> None