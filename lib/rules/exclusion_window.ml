open Jitter
open Dsl
open Date_time
open Types
open Date_calc
open Simple_date

type exclusion_result = 
  | NotExcluded
  | Excluded of { reason: string; window_end: Date_time.date option }

let check_birthday_exclusion contact check_date =
  match contact.state, contact.birthday with
  | Some state, Some birthday ->
      begin match get_window_for_email_type state (Anniversary Birthday) with
      | Some window ->
          let next_bday = next_anniversary check_date birthday in
          if in_exclusion_window check_date window next_bday then
            let window_end = add_days next_bday window.after_days in
            Excluded { 
              reason = Printf.sprintf "Birthday exclusion window for %s" (string_of_state state);
              window_end = Some window_end 
            }
          else
            NotExcluded
      | None -> NotExcluded
      end
  | _ -> NotExcluded

let check_effective_date_exclusion contact check_date =
  match contact.state, contact.effective_date with
  | Some state, Some ed ->
      begin match get_window_for_email_type state (Anniversary EffectiveDate) with
      | Some window ->
          let next_ed = next_anniversary check_date ed in
          if in_exclusion_window check_date window next_ed then
            let window_end = add_days next_ed window.after_days in
            Excluded { 
              reason = Printf.sprintf "Effective date exclusion window for %s" (string_of_state state);
              window_end = Some window_end 
            }
          else
            NotExcluded
      | None -> NotExcluded
      end
  | _ -> NotExcluded

let check_year_round_exclusion contact =
  match contact.state with
  | Some state when is_year_round_exclusion state ->
      Excluded { 
        reason = Printf.sprintf "Year-round exclusion for %s" (string_of_state state);
        window_end = None 
      }
  | _ -> NotExcluded

let check_exclusion_window contact check_date =
  match check_year_round_exclusion contact with
  | Excluded _ as result -> result
  | NotExcluded ->
      match check_birthday_exclusion contact check_date with
      | Excluded _ as result -> result
      | NotExcluded -> check_effective_date_exclusion contact check_date

let should_skip_email contact email_type check_date =
  match email_type with
  | Campaign c when not c.respect_exclusions -> false
  | Anniversary PostWindow -> false
  | _ ->
      match check_exclusion_window contact check_date with
      | NotExcluded -> false
      | Excluded _ -> true

let get_post_window_date contact =
  let today = current_date () in
  let exclusions = [
    check_birthday_exclusion contact today;
    check_effective_date_exclusion contact today
  ] in
  
  let latest_window_end = 
    List.fold_left (fun acc exc ->
      match exc, acc with
      | Excluded { window_end = Some end_date; _ }, None -> Some end_date
      | Excluded { window_end = Some end_date; _ }, Some acc_date ->
          if compare_date end_date acc_date > 0 then Some end_date else Some acc_date
      | _ -> acc
    ) None exclusions
  in
  
  match latest_window_end with
  | Some end_date -> Some (add_days end_date 1)
  | None -> None