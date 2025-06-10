module HybridConfig.Types exposing (..)

import Dict exposing (Dict)
import Json.Decode as Decode exposing (Decoder)
import Json.Encode as Encode


-- Size profiles for load balancing variations
type SizeProfile 
    = Small 
    | Medium 
    | Large 
    | Enterprise


sizeProfileToString : SizeProfile -> String
sizeProfileToString profile =
    case profile of
        Small -> "small"
        Medium -> "medium"
        Large -> "large"
        Enterprise -> "enterprise"


sizeProfileFromString : String -> Maybe SizeProfile
sizeProfileFromString str =
    case str of
        "small" -> Just Small
        "medium" -> Just Medium
        "large" -> Just Large
        "enterprise" -> Just Enterprise
        _ -> Nothing


-- Organization configuration from central database
type alias OrganizationConfig =
    { id : Int
    , name : String
    -- Business rules
    , enablePostWindowEmails : Bool
    , effectiveDateFirstEmailMonths : Int
    , excludeFailedUnderwritingGlobal : Bool
    , sendWithoutZipcodeForUniversal : Bool
    , preExclusionBufferDays : Int
    -- Customer preferences  
    , birthdayDaysBefore : Int
    , effectiveDateDaysBefore : Int
    , sendTimeHour : Int
    , sendTimeMinute : Int
    , timezone : String
    -- Communication limits
    , maxEmailsPerPeriod : Int
    , frequencyPeriodDays : Int
    -- Size-based tuning
    , sizeProfile : SizeProfile
    -- Optional overrides
    , configOverrides : Maybe (Dict String Encode.Value)
    }


-- Computed load balancing configuration
type alias LoadBalancingConfig =
    { dailySendPercentageCap : Float
    , edDailySoftLimit : Int
    , edSmoothingWindowDays : Int
    , batchSize : Int
    , totalContacts : Int
    }


-- System constants (in code, not in database)
type alias SystemConstants =
    { edPercentageOfDailyCap : Float
    , overageThreshold : Float
    , catchUpSpreadDays : Int
    , followupLookbackDays : Int
    , postWindowDelayDays : Int
    -- Email priorities
    , birthdayPriority : Int
    , effectiveDatePriority : Int
    , postWindowPriority : Int
    , followupPriority : Int
    , defaultCampaignPriority : Int
    -- Database performance
    , sqliteCacheSize : Int
    , sqlitePageSize : Int
    , defaultBatchInsertSize : Int
    -- Thresholds
    , largeDatasetThreshold : Int
    , hugeDatasetThreshold : Int
    }


-- Complete configuration combining database and computed values
type alias HybridConfig =
    { organization : OrganizationConfig
    , loadBalancing : LoadBalancingConfig
    , systemConstants : SystemConstants
    , databasePath : String
    , backupDir : String
    , backupRetentionDays : Int
    , maxMemoryMb : Int
    }


-- Data flow representation
type DataFlowNode
    = CentralDatabase
    | OrganizationLoader
    | ContactCounter  
    | SizeProfileCalculator
    | LoadBalancingComputer
    | ConfigOverrideApplier
    | OrgSpecificDatabase
    | EmailScheduler
    | LoadBalancer
    | ExclusionWindowChecker
    | PriorityCalculator


dataFlowNodeToString : DataFlowNode -> String
dataFlowNodeToString flow =
    case flow of
        CentralDatabase -> "Central Database (Turso)"
        OrganizationLoader -> "Organization Config Loader"
        ContactCounter -> "Contact Counter"
        SizeProfileCalculator -> "Size Profile Calculator"
        LoadBalancingComputer -> "Load Balancing Computer"
        ConfigOverrideApplier -> "Config Override Applier"
        OrgSpecificDatabase -> "Org-Specific Database"
        EmailScheduler -> "Email Scheduler"
        LoadBalancer -> "Load Balancer"
        ExclusionWindowChecker -> "Exclusion Window Checker"
        PriorityCalculator -> "Priority Calculator"


-- Decision tree nodes
type DecisionNode
    = LoadOrgConfig
    | CheckContactCount
    | DetermineProfile
    | ApplyOverrides
    | CalculateCapacity
    | ProcessContact
    | CheckExclusions
    | CalculatePriority
    | ScheduleEmail
    | BalanceLoad


decisionNodeToString : DecisionNode -> String
decisionNodeToString node =
    case node of
        LoadOrgConfig -> "Load Org Config"
        CheckContactCount -> "Check Contact Count"
        DetermineProfile -> "Determine Size Profile"
        ApplyOverrides -> "Apply Config Overrides"
        CalculateCapacity -> "Calculate Daily Capacity"
        ProcessContact -> "Process Contact"
        CheckExclusions -> "Check Exclusion Windows"
        CalculatePriority -> "Calculate Priority"
        ScheduleEmail -> "Schedule Email"
        BalanceLoad -> "Balance Load"


-- Decision tree structure
type DecisionTree 
    = DecisionTree 
        { node : DecisionNode
        , condition : Maybe String
        , children : List DecisionTree
        , details : List String
        }


-- Function metadata for visualization
type alias FunctionInfo =
    { name : String
    , module_ : String
    , parameters : List ( String, Maybe String )
    , returnType : Maybe String
    , complexityScore : Int
    , calls : List String
    , isRecursive : Bool
    , documentation : Maybe String
    , sourceLocation : { file : String, startLine : Int, endLine : Int }
    }


-- Flow edge representing data/control flow
type alias FlowEdge =
    { from : String
    , to : String
    , label : Maybe String
    , flowType : FlowType
    }


type FlowType
    = DataFlow_
    | ControlFlow
    | ConfigFlow
    | ErrorFlow


-- Visualization state
type alias VisualizationState =
    { selectedNode : Maybe String
    , expandedNodes : List String  
    , currentView : ViewType
    , filterComplexity : Maybe Int
    , showModules : Bool
    , highlightedPath : List String
    }


type ViewType
    = DataFlowView
    | DecisionTreeView
    | FunctionCallGraphView
    | ConfigFlowView


-- Default values
defaultSystemConstants : SystemConstants
defaultSystemConstants =
    { edPercentageOfDailyCap = 0.3
    , overageThreshold = 1.2
    , catchUpSpreadDays = 7
    , followupLookbackDays = 35
    , postWindowDelayDays = 1
    , birthdayPriority = 10
    , effectiveDatePriority = 20
    , postWindowPriority = 40
    , followupPriority = 50
    , defaultCampaignPriority = 30
    , sqliteCacheSize = 500000
    , sqlitePageSize = 8192
    , defaultBatchInsertSize = 1000
    , largeDatasetThreshold = 100000
    , hugeDatasetThreshold = 500000
    }


defaultVisualizationState : VisualizationState
defaultVisualizationState =
    { selectedNode = Nothing
    , expandedNodes = []
    , currentView = DataFlowView
    , filterComplexity = Nothing
    , showModules = True
    , highlightedPath = []
    }