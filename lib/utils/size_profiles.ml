open Types
open System_constants.SystemConstants

(** Compute load balancing configuration based on organization size *)
let load_balancing_for_profile profile total_contacts =
  let base_config = match profile with
    | Small ->  (* < 10k contacts *)
        {
          daily_send_percentage_cap = 0.20;  (* 20% - more aggressive *)
          ed_daily_soft_limit = 50;
          batch_size = 1000;
          ed_smoothing_window_days = 3;
          total_contacts;
        }
    | Medium ->  (* 10k - 100k contacts *)
        {
          daily_send_percentage_cap = 0.10;  (* 10% *)
          ed_daily_soft_limit = 200;
          batch_size = 5000;
          ed_smoothing_window_days = 5;
          total_contacts;
        }
    | Large ->  (* 100k - 500k contacts *)
        {
          daily_send_percentage_cap = 0.07;  (* 7% *)
          ed_daily_soft_limit = 500;
          batch_size = 10000;
          ed_smoothing_window_days = 7;
          total_contacts;
        }
    | Enterprise ->  (* 500k+ contacts *)
        {
          daily_send_percentage_cap = 0.05;  (* 5% - conservative *)
          ed_daily_soft_limit = 1000;
          batch_size = 25000;
          ed_smoothing_window_days = 10;
          total_contacts;
        }
  in
  base_config

(** Apply JSON overrides to computed configuration *)
let apply_config_overrides base_config overrides =
  match overrides with
  | None -> base_config
  | Some override_list ->
      List.fold_left (fun config (key, value) ->
        match key with
        | "daily_send_percentage_cap" ->
            (match value with
             | `Float f -> { config with daily_send_percentage_cap = f }
             | `Int i -> { config with daily_send_percentage_cap = float_of_int i /. 100.0 }
             | _ -> config)
        | "ed_daily_soft_limit" ->
            (match value with
             | `Int i -> { config with ed_daily_soft_limit = i }
             | _ -> config)
        | "batch_size" ->
            (match value with
             | `Int i -> { config with batch_size = i }
             | _ -> config)
        | "ed_smoothing_window_days" ->
            (match value with
             | `Int i -> { config with ed_smoothing_window_days = i }
             | _ -> config)
        | _ -> config  (* Ignore unknown overrides *)
      ) base_config override_list

(** Auto-detect appropriate size profile based on contact count *)
let auto_detect_profile total_contacts =
  if total_contacts < 10_000 then Small
  else if total_contacts < 100_000 then Medium
  else if total_contacts < 500_000 then Large
  else Enterprise