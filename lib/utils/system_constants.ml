(** System-wide constants that rarely change and don't need per-org configuration *)
module SystemConstants = struct
  (* Algorithm constants *)
  let ed_percentage_of_daily_cap = 0.3      (* EDs can use 30% of daily capacity *)
  let overage_threshold = 1.2               (* Redistribute when 20% over cap *)
  let catch_up_spread_days = 7              (* Spread overflow across 7 days *)
  let followup_lookback_days = 35           (* Look back 35 days for follow-ups *)
  let followup_delay_days = 2               (* Default delay for follow-up emails *)
  let post_window_delay_days = 1            (* Send 1 day after exclusion ends *)
  
  (* Email priorities (could move to DB if needed) *)
  let birthday_priority = 10
  let effective_date_priority = 20
  let post_window_priority = 40
  let followup_priority = 50
  let default_campaign_priority = 30
  
  (* Database performance settings *)
  let sqlite_cache_size = 500000            (* ~200MB cache *)
  let sqlite_page_size = 8192
  let default_batch_insert_size = 1000
  
  (* Chunk size thresholds *)
  let large_dataset_threshold = 100000
  let huge_dataset_threshold = 500000
end