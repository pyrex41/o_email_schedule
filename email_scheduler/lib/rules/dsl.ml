(* Domain-Specific Language for expressing exclusion rules *)

open Domain.Types

(* Window definition for exclusion rules *)
type window = {
  before_days: int;
  after_days: int;
  use_month_start: bool;
}

(* Rule types for different exclusion patterns *)
type rule =
  | BirthdayWindow of window
  | EffectiveDateWindow of window
  | YearRoundExclusion
  | NoExclusion

(* DSL functions for building rules *)
let birthday_window ~before ~after ?(use_month_start=false) () =
  BirthdayWindow { before_days = before; after_days = after; use_month_start }

let effective_date_window ~before ~after =
  EffectiveDateWindow { before_days = before; after_days = after; use_month_start = false }

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

(* Helper functions to work with rules *)
let is_exclusion_rule = function
  | BirthdayWindow _ | EffectiveDateWindow _ | YearRoundExclusion -> true
  | NoExclusion -> false

let get_window_config = function
  | BirthdayWindow w | EffectiveDateWindow w -> Some w
  | YearRoundExclusion | NoExclusion -> None

let rule_applies_to_email_type rule email_type =
  match rule, email_type with
  | BirthdayWindow _, Anniversary Birthday -> true
  | EffectiveDateWindow _, Anniversary EffectiveDate -> true
  | YearRoundExclusion, _ -> true
  | NoExclusion, _ -> false
  | _ -> false

(* Rule description for debugging and logging *)
let describe_rule = function
  | BirthdayWindow { before_days; after_days; use_month_start } ->
      Printf.sprintf "Birthday window: %d days before to %d days after%s"
        before_days after_days 
        (if use_month_start then " (using month start)" else "")
  | EffectiveDateWindow { before_days; after_days; _ } ->
      Printf.sprintf "Effective date window: %d days before to %d days after"
        before_days after_days
  | YearRoundExclusion ->
      "Year-round exclusion (no emails allowed)"
  | NoExclusion ->
      "No exclusion rules"

(* Validation functions *)
let validate_window { before_days; after_days; _ } =
  if before_days < 0 then
    Error "before_days must be non-negative"
  else if after_days < 0 then
    Error "after_days must be non-negative"
  else
    Ok ()

let validate_rule = function
  | BirthdayWindow w | EffectiveDateWindow w -> validate_window w
  | YearRoundExclusion | NoExclusion -> Ok ()

(* Configuration export for external systems *)
let export_rules_config () =
  let all_states = [
    CA; CT; ID; KY; MA; MD; MO; NV; NY; OK; OR; VA; WA
  ] in
  List.map (fun state ->
    let rule = rules_for_state state in
    (string_of_state state, describe_rule rule)
  ) all_states