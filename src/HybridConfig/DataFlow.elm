module HybridConfig.DataFlow exposing (..)

import Dict exposing (Dict)
import HybridConfig.Types exposing (..)



-- Define the main data flow sequence for the hybrid configuration system


hybridConfigDataFlow : List DataFlowNode
hybridConfigDataFlow =
    [ CentralDatabase
    , OrganizationLoader
    , OrgSpecificDatabase
    , ContactCounter
    , SizeProfileCalculator
    , LoadBalancingComputer
    , ConfigOverrideApplier
    , EmailScheduler
    , ExclusionWindowChecker
    , PriorityCalculator
    , LoadBalancer
    ]



-- Define edges for the data flow diagram


hybridConfigFlowEdges : List FlowEdge
hybridConfigFlowEdges =
    [ -- Initial configuration loading
      { from = "Central Database (Turso)", to = "Organization Config Loader", label = Just "Load org config", flowType = ConfigFlow }
    , { from = "Organization Config Loader", to = "Org-Specific Database", label = Just "Switch to org DB", flowType = DataFlow_ }
    , { from = "Org-Specific Database", to = "Contact Counter", label = Just "Count contacts", flowType = DataFlow_ }

    -- Size profile determination
    , { from = "Contact Counter", to = "Size Profile Calculator", label = Just "Total count", flowType = DataFlow_ }
    , { from = "Size Profile Calculator", to = "Load Balancing Computer", label = Just "Size profile", flowType = ConfigFlow }

    -- Configuration computation
    , { from = "Load Balancing Computer", to = "Config Override Applier", label = Just "Base config", flowType = ConfigFlow }
    , { from = "Organization Config Loader", to = "Config Override Applier", label = Just "Overrides", flowType = ConfigFlow }

    -- Email processing flow
    , { from = "Config Override Applier", to = "Email Scheduler", label = Just "Final config", flowType = ConfigFlow }
    , { from = "Org-Specific Database", to = "Email Scheduler", label = Just "Contacts", flowType = DataFlow_ }
    , { from = "Email Scheduler", to = "Exclusion Window Checker", label = Just "Email candidates", flowType = DataFlow_ }
    , { from = "Exclusion Window Checker", to = "Priority Calculator", label = Just "Eligible emails", flowType = DataFlow_ }
    , { from = "Priority Calculator", to = "Load Balancer", label = Just "Prioritized emails", flowType = DataFlow_ }

    -- Configuration feedback
    , { from = "Config Override Applier", to = "Exclusion Window Checker", label = Just "Buffer settings", flowType = ConfigFlow }
    , { from = "Config Override Applier", to = "Priority Calculator", label = Just "Priority rules", flowType = ConfigFlow }
    , { from = "Config Override Applier", to = "Load Balancer", label = Just "Capacity limits", flowType = ConfigFlow }

    -- Error flows
    , { from = "Central Database (Turso)", to = "Email Scheduler", label = Just "Fallback config", flowType = ErrorFlow }
    ]



-- Define the decision tree for the hybrid configuration system


hybridConfigDecisionTree : DecisionTree
hybridConfigDecisionTree =
    { node = LoadOrgConfig
    , condition = Just "org_id provided"
    , details =
        [ "Connect to central Turso database"
        , "Query organizations table for org configuration"
        , "Parse business rules, preferences, and size profile"
        , "Handle missing organization with fallback defaults"
        ]
    , children =
        [ { node = CheckContactCount
          , condition = Just "switch to org database"
          , details =
                [ "Set database path to org-specific SQLite file"
                , "Execute SELECT COUNT(*) FROM contacts"
                , "Use count for load balancing calculations"
                , "Fall back to profile estimates if query fails"
                ]
          , children =
                [ { node = DetermineProfile
                  , condition = Just "contact count available"
                  , details =
                        [ "< 10k contacts → Small profile"
                        , "10k-100k contacts → Medium profile"
                        , "100k-500k contacts → Large profile"
                        , "500k+ contacts → Enterprise profile"
                        , "Use org.size_profile if manually set"
                        ]
                  , children =
                        [ { node = CalculateCapacity
                          , condition = Just "profile determined"
                          , details =
                                [ "Small: 20% daily cap, 50 ED limit, 1k batch"
                                , "Medium: 10% daily cap, 200 ED limit, 5k batch"
                                , "Large: 7% daily cap, 500 ED limit, 10k batch"
                                , "Enterprise: 5% daily cap, 1k ED limit, 25k batch"
                                ]
                          , children =
                                [ { node = ApplyOverrides
                                  , condition = Just "config_overrides present"
                                  , details =
                                        [ "Parse JSON config_overrides field"
                                        , "Apply daily_send_percentage_cap override"
                                        , "Apply ed_daily_soft_limit override"
                                        , "Apply batch_size override"
                                        , "Ignore unknown override keys"
                                        ]
                                  , children =
                                        [ { node = ProcessContact
                                          , condition = Just "for each contact"
                                          , details =
                                                [ "Calculate anniversary dates (birthday, effective date)"
                                                , "Check if post-window emails enabled"
                                                , "Apply customer preferences (send time, timezone)"
                                                , "Apply communication frequency limits"
                                                ]
                                          , children =
                                                [ { node = CheckExclusions
                                                  , condition = Just "email candidate generated"
                                                  , details =
                                                        [ "Use org.pre_exclusion_buffer_days as base"
                                                        , "Check for state-specific buffer overrides"
                                                        , "Apply exclude_failed_underwriting_global rule"
                                                        , "Check send_without_zipcode_for_universal rule"
                                                        ]
                                                  , children =
                                                        [ { node = CalculatePriority
                                                          , condition = Just "email not excluded"
                                                          , details =
                                                                [ "Birthday: priority 10 (from SystemConstants)"
                                                                , "Effective Date: priority 20"
                                                                , "Post Window: priority 40"
                                                                , "Campaign: use campaign.priority"
                                                                , "Followup: priority 50"
                                                                ]
                                                          , children =
                                                                [ { node = ScheduleEmail
                                                                  , condition = Just "priority assigned"
                                                                  , details =
                                                                        [ "Set scheduled_date and scheduled_time"
                                                                        , "Use org send_time_hour/minute preferences"
                                                                        , "Convert to org timezone"
                                                                        , "Insert into email_schedules table"
                                                                        ]
                                                                  , children =
                                                                        [ { node = BalanceLoad
                                                                          , condition = Just "all emails scheduled"
                                                                          , details =
                                                                                [ "Check daily totals against capacity limits"
                                                                                , "Apply overage_threshold (1.2x from SystemConstants)"
                                                                                , "Spread overflow across catch_up_spread_days (7 days)"
                                                                                , "Prioritize within daily limits"
                                                                                ]
                                                                          , children = []
                                                                          }
                                                                        ]
                                                                  }
                                                                ]
                                                          }
                                                        ]
                                                  }
                                                ]
                                          }
                                        ]
                                  }
                                ]
                          }
                        ]
                  }
                ]
          }
        ]
    }



-- Function to get details for a specific decision node


getNodeDetails : DecisionNode -> List String
getNodeDetails node =
    case node of
        LoadOrgConfig ->
            [ "Query: SELECT * FROM organizations WHERE id = ? AND active = 1"
            , "Fields: enable_post_window_emails, effective_date_first_email_months"
            , "Fields: exclude_failed_underwriting_global, send_without_zipcode_for_universal"
            , "Fields: pre_exclusion_buffer_days, birthday_days_before, effective_date_days_before"
            , "Fields: send_time_hour, send_time_minute, timezone"
            , "Fields: max_emails_per_period, frequency_period_days, size_profile"
            , "Fields: config_overrides (JSON)"
            , "Fallback: Use default medium profile if org not found"
            ]

        CheckContactCount ->
            [ "Switch database connection to org-specific SQLite file"
            , "Query: SELECT COUNT(*) FROM contacts"
            , "Handle database connection errors gracefully"
            , "Estimate based on size_profile if count unavailable"
            ]

        DetermineProfile ->
            [ "Auto-detection thresholds:"
            , "  Small: < 10,000 contacts"
            , "  Medium: 10,000 - 99,999 contacts"
            , "  Large: 100,000 - 499,999 contacts"
            , "  Enterprise: 500,000+ contacts"
            , "Manual override: Use org.size_profile if explicitly set"
            ]

        ApplyOverrides ->
            [ "Parse config_overrides JSON field from organizations table"
            , "Supported overrides:"
            , "  daily_send_percentage_cap: Override daily capacity percentage"
            , "  ed_daily_soft_limit: Override effective date soft limit"
            , "  batch_size: Override processing batch size"
            , "  ed_smoothing_window_days: Override smoothing window"
            , "Ignore unknown keys to maintain forward compatibility"
            ]

        CalculateCapacity ->
            [ "Small profile: 20% daily cap, 1,000 batch size, 3-day smoothing"
            , "Medium profile: 10% daily cap, 5,000 batch size, 5-day smoothing"
            , "Large profile: 7% daily cap, 10,000 batch size, 7-day smoothing"
            , "Enterprise profile: 5% daily cap, 25,000 batch size, 10-day smoothing"
            , "ED soft limits: Small=50, Medium=200, Large=500, Enterprise=1000"
            ]

        ProcessContact ->
            [ "Calculate next birthday anniversary from contact.birthday"
            , "Calculate next effective date anniversary from contact.effective_date"
            , "Apply birthday_days_before and effective_date_days_before"
            , "Check effective_date_first_email_months rule"
            , "Apply communication frequency limits (max_emails_per_period)"
            ]

        CheckExclusions ->
            [ "Load exclusion windows by state for email type"
            , "Apply pre_exclusion_buffer_days (with state overrides)"
            , "Check exclude_failed_underwriting_global rule"
            , "Apply send_without_zipcode_for_universal rule"
            , "Post-window emails: check enable_post_window_emails flag"
            ]

        CalculatePriority ->
            [ "Use SystemConstants for base priorities:"
            , "  Birthday: 10, Effective Date: 20, Post Window: 40"
            , "  Campaign: use campaign.priority, Followup: 50"
            , "Lower numbers = higher priority"
            , "Priority affects load balancing order"
            ]

        ScheduleEmail ->
            [ "Set scheduled_date based on email type and preferences"
            , "Set scheduled_time using send_time_hour/minute"
            , "Convert time to organization timezone"
            , "Generate scheduler_run_id for tracking"
            , "Insert into email_schedules table"
            ]

        BalanceLoad ->
            [ "Calculate daily_send_cap = total_contacts * daily_send_percentage_cap"
            , "Check if any day exceeds overage_threshold (1.2x cap)"
            , "Redistribute overflow across catch_up_spread_days (7 days)"
            , "Respect ED soft limits (30% of daily cap)"
            , "Maintain priority ordering within daily limits"
            ]



-- Get the complexity score for a decision node (for visualization styling)


getNodeComplexity : DecisionNode -> Int
getNodeComplexity node =
    case node of
        LoadOrgConfig ->
            5

        CheckContactCount ->
            3

        DetermineProfile ->
            2

        ApplyOverrides ->
            4

        CalculateCapacity ->
            3

        ProcessContact ->
            7

        CheckExclusions ->
            8

        CalculatePriority ->
            4

        ScheduleEmail ->
            5

        BalanceLoad ->
            9



-- Get the module/file association for a decision node


getNodeModule : DecisionNode -> String
getNodeModule node =
    case node of
        LoadOrgConfig ->
            "Database.load_organization_config"

        CheckContactCount ->
            "Database.get_total_contact_count"

        DetermineProfile ->
            "Size_profiles.auto_detect_profile"

        ApplyOverrides ->
            "Size_profiles.apply_config_overrides"

        CalculateCapacity ->
            "Size_profiles.load_balancing_for_profile"

        ProcessContact ->
            "Email_scheduler.calculate_anniversary_emails"

        CheckExclusions ->
            "Exclusion_window.check_exclusion_window"

        CalculatePriority ->
            "Types.priority_of_email_type"

        ScheduleEmail ->
            "Email_scheduler.schedule_email"

        BalanceLoad ->
            "Load_balancer.redistribute_overflow"



-- Size profile descriptions for the UI


sizeProfileDescriptions : Dict String String
sizeProfileDescriptions =
    Dict.fromList
        [ ( "small", "< 10k contacts: Aggressive 20% daily cap, small batches" )
        , ( "medium", "10k-100k contacts: Balanced 10% daily cap, medium batches" )
        , ( "large", "100k-500k contacts: Conservative 7% daily cap, large batches" )
        , ( "enterprise", "500k+ contacts: Very conservative 5% daily cap, huge batches" )
        ]



-- System constant explanations


systemConstantExplanations : Dict String String
systemConstantExplanations =
    Dict.fromList
        [ ( "edPercentageOfDailyCap", "EDs can use 30% of daily capacity" )
        , ( "overageThreshold", "Redistribute when 20% over cap (1.2x)" )
        , ( "catchUpSpreadDays", "Spread overflow across 7 days" )
        , ( "followupLookbackDays", "Look back 35 days for follow-ups" )
        , ( "postWindowDelayDays", "Send 1 day after exclusion ends" )
        , ( "birthdayPriority", "Birthday emails: priority 10 (highest)" )
        , ( "effectiveDatePriority", "Effective date emails: priority 20" )
        , ( "postWindowPriority", "Post-window emails: priority 40" )
        , ( "followupPriority", "Follow-up emails: priority 50 (lowest)" )
        ]
