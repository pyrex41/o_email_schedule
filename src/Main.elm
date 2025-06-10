module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode
import Json.Encode as Encode
import Http
import Dict exposing (Dict)
import List.Extra
import HybridConfig.Types exposing (..)
import HybridConfig.DataFlow exposing (..)
import HybridConfig.MermaidDiagrams exposing (..)


-- MODEL

type alias Model =
    { visualizationState : VisualizationState
    , currentDiagram : String
    , detailsPanel : Maybe NodeDetails
    , functions : List FunctionInfo
    , loadingState : LoadingState
    , error : Maybe String
    , orgConfig : Maybe OrganizationConfig
    , selectedExample : ExampleOrg
    }


type LoadingState
    = Loading
    | Loaded
    | Failed String


type alias NodeDetails =
    { title : String
    , description : String
    , details : List String
    , module_ : Maybe String
    , complexity : Maybe Int
    , relatedNodes : List String
    }


type ExampleOrg
    = SmallOrg
    | MediumOrg
    | LargeOrg
    | EnterpriseOrg


-- MESSAGES

type Msg
    = ChangeView ViewType
    | SelectNode String
    | ToggleNodeExpansion String
    | ShowNodeDetails NodeDetails
    | CloseDetailsPanel
    | SetComplexityFilter (Maybe Int)
    | ToggleModules
    | LoadFunctions (Result Http.Error (List FunctionInfo))
    | HighlightPath (List String)
    | ClearHighlight
    | SelectExample ExampleOrg
    | ToggleNode String
    | ZoomToNode String


-- INIT

init : () -> ( Model, Cmd Msg )
init _ =
    let
        initialModel =
            { visualizationState = defaultVisualizationState
            , currentDiagram = ""
            , detailsPanel = Nothing
            , functions = []
            , loadingState = Loading
            , error = Nothing
            , orgConfig = Nothing
            , selectedExample = MediumOrg
            }
    in
    ( { initialModel 
      | currentDiagram = generateDataFlowDiagram initialModel.visualizationState
      , orgConfig = Just (exampleOrgConfig MediumOrg)
      }
    , loadFunctionsData
    )


-- UPDATE

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ChangeView viewType ->
            let
                newVisualizationState = 
                    { model.visualizationState | currentView = viewType }
                
                newDiagram = 
                    case viewType of
                        DataFlowView -> generateDataFlowDiagram newVisualizationState
                        DecisionTreeView -> generateDecisionTreeDiagram newVisualizationState
                        FunctionCallGraphView -> generateFunctionCallGraph model.functions newVisualizationState
                        ConfigFlowView -> generateConfigFlowDiagram model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        SelectNode nodeId ->
            let
                newVisualizationState = 
                    { model.visualizationState | selectedNode = Just nodeId }
                
                nodeDetails = createNodeDetails nodeId model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , detailsPanel = nodeDetails
              }
            , Cmd.none
            )

        ToggleNodeExpansion nodeId ->
            let
                newExpandedNodes = 
                    if List.member nodeId model.visualizationState.expandedNodes then
                        List.filter ((/=) nodeId) model.visualizationState.expandedNodes
                    else
                        nodeId :: model.visualizationState.expandedNodes
                
                newVisualizationState = 
                    { model.visualizationState | expandedNodes = newExpandedNodes }
                
                newDiagram = regenerateDiagram model.visualizationState.currentView newVisualizationState model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        ShowNodeDetails details ->
            ( { model | detailsPanel = Just details }, Cmd.none )

        CloseDetailsPanel ->
            ( { model | detailsPanel = Nothing }, Cmd.none )

        SetComplexityFilter complexity ->
            let
                newVisualizationState = 
                    { model.visualizationState | filterComplexity = complexity }
                
                newDiagram = regenerateDiagram model.visualizationState.currentView newVisualizationState model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        ToggleModules ->
            let
                newVisualizationState = 
                    { model.visualizationState | showModules = not model.visualizationState.showModules }
                
                newDiagram = regenerateDiagram model.visualizationState.currentView newVisualizationState model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        LoadFunctions result ->
            case result of
                Ok functions ->
                    ( { model 
                      | functions = functions
                      , loadingState = Loaded
                      }
                    , Cmd.none
                    )
                
                Err error ->
                    ( { model 
                      | loadingState = Failed (httpErrorToString error)
                      , error = Just (httpErrorToString error)
                      }
                    , Cmd.none
                    )

        HighlightPath path ->
            let
                newVisualizationState = 
                    { model.visualizationState | highlightedPath = path }
                
                newDiagram = regenerateDiagram model.visualizationState.currentView newVisualizationState model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        ClearHighlight ->
            let
                newVisualizationState = 
                    { model.visualizationState | highlightedPath = [] }
                
                newDiagram = regenerateDiagram model.visualizationState.currentView newVisualizationState model
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

        SelectExample example ->
            let
                newOrgConfig = exampleOrgConfig example
            in
            ( { model 
              | selectedExample = example
              , orgConfig = Just newOrgConfig
              }
            , Cmd.none
            )

        ToggleNode nodeId ->
            update (ToggleNodeExpansion nodeId) model

        ZoomToNode nodeId ->
            update (SelectNode nodeId) model


-- VIEW

view : Model -> Html Msg
view model =
    div [ class "hybrid-config-visualizer" ]
        [ header [ class "app-header" ]
            [ h1 [] [ text "🔄 Hybrid Configuration System Visualizer" ]
            , div [ class "subtitle" ] 
                [ text "Interactive exploration of the email scheduler's configuration architecture" ]
            ]
        , main_ [ class "app-main" ]
            [ viewSidebar model
            , viewVisualization model
            , viewDetailsPanel model
            ]
        ]


viewSidebar : Model -> Html Msg
viewSidebar model =
    aside [ class "sidebar" ]
        [ viewControls model
        , viewExampleOrgs model
        , viewSystemInfo model
        , viewLegend model
        ]


viewControls : Model -> Html Msg
viewControls model =
    div [ class "controls-section" ]
        [ h3 [] [ text "Views" ]
        , div [ class "view-buttons" ]
            [ viewButton DataFlowView "🌊 Data Flow" model.visualizationState.currentView
            , viewButton DecisionTreeView "🌳 Decision Tree" model.visualizationState.currentView
            , viewButton FunctionCallGraphView "📞 Function Calls" model.visualizationState.currentView
            , viewButton ConfigFlowView "⚙️ Config Flow" model.visualizationState.currentView
            ]
        , h3 [] [ text "Filters" ]
        , div [ class "filter-controls" ]
            [ label []
                [ text "Max Complexity: "
                , select [ onInput (String.toInt >> SetComplexityFilter) ]
                    [ option [ value "" ] [ text "All" ]
                    , option [ value "5" ] [ text "≤ 5" ]
                    , option [ value "10" ] [ text "≤ 10" ]
                    , option [ value "15" ] [ text "≤ 15" ]
                    ]
                ]
            , label [ class "checkbox-label" ]
                [ input 
                    [ type_ "checkbox"
                    , checked model.visualizationState.showModules
                    , onCheck (\_ -> ToggleModules)
                    ] []
                , text " Show Modules"
                ]
            ]
        ]


viewButton : ViewType -> String -> ViewType -> Html Msg
viewButton viewType label currentView =
    button 
        [ class (if viewType == currentView then "active" else "")
        , onClick (ChangeView viewType)
        ]
        [ text label ]


viewExampleOrgs : Model -> Html Msg
viewExampleOrgs model =
    div [ class "example-orgs-section" ]
        [ h3 [] [ text "Example Organizations" ]
        , div [ class "org-examples" ]
            [ orgExample SmallOrg "🏢 Small (5k contacts)" model.selectedExample
            , orgExample MediumOrg "🏬 Medium (50k contacts)" model.selectedExample
            , orgExample LargeOrg "🏭 Large (250k contacts)" model.selectedExample
            , orgExample EnterpriseOrg "🏙️ Enterprise (1M+ contacts)" model.selectedExample
            ]
        , case model.orgConfig of
            Just config ->
                div [ class "org-config-display" ]
                    [ h4 [] [ text config.name ]
                    , div [ class "config-details" ]
                        [ configDetail "Size Profile" (sizeProfileToString config.sizeProfile)
                        , configDetail "Daily Cap" (String.fromFloat (getLoadBalancingConfig config).dailySendPercentageCap * 100 ++ "%")
                        , configDetail "Batch Size" (String.fromInt (getLoadBalancingConfig config).batchSize)
                        , configDetail "ED Soft Limit" (String.fromInt (getLoadBalancingConfig config).edDailySoftLimit)
                        ]
                    ]
            Nothing ->
                text ""
        ]


orgExample : ExampleOrg -> String -> ExampleOrg -> Html Msg
orgExample org label selected =
    button 
        [ class (if org == selected then "org-example active" else "org-example")
        , onClick (SelectExample org)
        ]
        [ text label ]


configDetail : String -> String -> Html Msg
configDetail label value =
    div [ class "config-detail" ]
        [ span [ class "label" ] [ text (label ++ ": ") ]
        , span [ class "value" ] [ text value ]
        ]


viewSystemInfo : Model -> Html Msg
viewSystemInfo model =
    div [ class "system-info-section" ]
        [ h3 [] [ text "System Constants" ]
        , div [ class "system-constants" ]
            [ systemConstant "ED Daily Cap %" "30%"
            , systemConstant "Overage Threshold" "120%"
            , systemConstant "Spread Days" "7"
            , systemConstant "Lookback Days" "35"
            ]
        , h3 [] [ text "Priority Levels" ]
        , div [ class "priorities" ]
            [ priority "Birthday" "10" "#28a745"
            , priority "Effective Date" "20" "#ffc107"
            , priority "Post Window" "40" "#fd7e14"
            , priority "Follow-up" "50" "#dc3545"
            ]
        ]


systemConstant : String -> String -> Html Msg
systemConstant label value =
    div [ class "system-constant" ]
        [ span [ class "label" ] [ text label ]
        , span [ class "value" ] [ text value ]
        ]


priority : String -> String -> String -> Html Msg
priority label value color =
    div [ class "priority-item" ]
        [ div [ class "priority-indicator", style "background-color" color ] []
        , span [ class "label" ] [ text label ]
        , span [ class "value" ] [ text value ]
        ]


viewLegend : Model -> Html Msg
viewLegend model =
    div [ class "legend-section" ]
        [ h3 [] [ text "Legend" ]
        , case model.visualizationState.currentView of
            DataFlowView ->
                div [ class "legend-items" ]
                    [ legendItem "🔷 Database" "database-node"
                    , legendItem "📋 Loader" "loader-node"
                    , legendItem "🔢 Counter" "counter-node"
                    , legendItem "⚙️ Calculator" "calculator-node"
                    , legendItem "🎛️ Processor" "processor-node"
                    ]
            
            DecisionTreeView ->
                div [ class "legend-items" ]
                    [ legendItem "🟢 Low Complexity" "low-complexity"
                    , legendItem "🟡 Medium Complexity" "medium-complexity"
                    , legendItem "🔴 High Complexity" "high-complexity"
                    , legendItem "⭐ Selected" "selected"
                    ]
            
            _ ->
                div [ class "legend-items" ]
                    [ legendItem "📞 Function Call" "data-flow"
                    , legendItem "⚙️ Config Flow" "config-flow"
                    , legendItem "❌ Error Flow" "error-flow"
                    ]
        ]


legendItem : String -> String -> Html Msg
legendItem label className =
    div [ class "legend-item" ]
        [ div [ class ("legend-indicator " ++ className) ] []
        , text label
        ]


viewVisualization : Model -> Html Msg
viewVisualization model =
    div [ class "visualization-container" ]
        [ div [ class "visualization-header" ]
            [ h2 [] [ text (viewTypeToString model.visualizationState.currentView) ]
            , div [ class "visualization-actions" ]
                [ button [ onClick ClearHighlight ] [ text "Clear Highlight" ]
                , button [ onClick (ChangeView DataFlowView) ] [ text "Reset View" ]
                ]
            ]
        , div [ class "mermaid-container" ]
            [ div 
                [ id "mermaid-diagram"
                , attribute "data-diagram" model.currentDiagram
                ] 
                []
            ]
        , case model.loadingState of
            Loading -> div [ class "loading" ] [ text "Loading function data..." ]
            Failed error -> div [ class "error" ] [ text ("Error: " ++ error) ]
            Loaded -> text ""
        ]


viewDetailsPanel : Model -> Html Msg
viewDetailsPanel model =
    case model.detailsPanel of
        Just details ->
            div [ class "details-panel" ]
                [ div [ class "details-header" ]
                    [ h3 [] [ text details.title ]
                    , button [ class "close-button", onClick CloseDetailsPanel ] [ text "×" ]
                    ]
                , div [ class "details-content" ]
                    [ p [ class "description" ] [ text details.description ]
                    , case details.module_ of
                        Just module_ ->
                            div [ class "module-info" ]
                                [ strong [] [ text "Module: " ]
                                , text module_
                                ]
                        Nothing -> text ""
                    , case details.complexity of
                        Just complexity ->
                            div [ class "complexity-info" ]
                                [ strong [] [ text "Complexity: " ]
                                , span [ class (complexityClass complexity) ] [ text (String.fromInt complexity) ]
                                ]
                        Nothing -> text ""
                    , if List.length details.details > 0 then
                        div [ class "details-list" ]
                            [ h4 [] [ text "Details:" ]
                            , ul [] (List.map (\detail -> li [] [ text detail ]) details.details)
                            ]
                      else text ""
                    , if List.length details.relatedNodes > 0 then
                        div [ class "related-nodes" ]
                            [ h4 [] [ text "Related Components:" ]
                            , div [ class "related-node-buttons" ]
                                (List.map relatedNodeButton details.relatedNodes)
                            ]
                      else text ""
                    ]
                ]
        
        Nothing -> text ""


relatedNodeButton : String -> Html Msg
relatedNodeButton nodeId =
    button 
        [ class "related-node-button"
        , onClick (SelectNode nodeId)
        ] 
        [ text nodeId ]


-- HELPER FUNCTIONS

regenerateDiagram : ViewType -> VisualizationState -> Model -> String
regenerateDiagram viewType state model =
    case viewType of
        DataFlowView -> generateDataFlowDiagram state
        DecisionTreeView -> generateDecisionTreeDiagram state
        FunctionCallGraphView -> generateFunctionCallGraph model.functions state
        ConfigFlowView -> generateConfigFlowDiagram model


generateConfigFlowDiagram : Model -> String
generateConfigFlowDiagram model =
    case model.orgConfig of
        Just config ->
            generateConfigFlowFromOrg config model.visualizationState
        Nothing ->
            generateDataFlowDiagram model.visualizationState


generateConfigFlowFromOrg : OrganizationConfig -> VisualizationState -> String
generateConfigFlowFromOrg config state =
    let
        loadBalancingConfig = getLoadBalancingConfig config
        
        configNodes = 
            [ "CentralDB[\"Central Database\"]:::database-node"
            , "OrgConfig[\"Org Config: " ++ config.name ++ "\"]:::config-node"
            , "SizeProfile[\"" ++ sizeProfileToString config.sizeProfile ++ " Profile\"]:::profile-node"
            , "LoadBalancing[\"Daily Cap: " ++ String.fromFloat (loadBalancingConfig.dailySendPercentageCap * 100) ++ "%\"]:::balancing-node"
            , "BatchSize[\"Batch: " ++ String.fromInt loadBalancingConfig.batchSize ++ "\"]:::batch-node"
            ]
        
        configEdges =
            [ "CentralDB --> OrgConfig"
            , "OrgConfig --> SizeProfile"
            , "SizeProfile --> LoadBalancing"
            , "SizeProfile --> BatchSize"
            ]
        
        styling = 
            """
            classDef database-node fill:#e1f5fe,stroke:#0277bd,stroke-width:3px
            classDef config-node fill:#fce4ec,stroke:#c2185b,stroke-width:2px
            classDef profile-node fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
            classDef balancing-node fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
            classDef batch-node fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px"""
    in
    [ "%%{init: {\"flowchart\": {\"defaultRenderer\": \"elk\"}} }%%"
    , "flowchart TD"
    , "    " ++ String.join "\n    " configNodes
    , "    " ++ String.join "\n    " configEdges
    , "    " ++ styling
    ]
        |> String.join "\n"


createNodeDetails : String -> Model -> Maybe NodeDetails
createNodeDetails nodeId model =
    -- Try to match against data flow nodes first
    case findDataFlowNode nodeId of
        Just node ->
            Just (dataFlowNodeToDetails node)
        
        Nothing ->
            -- Try to match against decision nodes
            case findDecisionNode nodeId of
                Just node ->
                    Just (decisionNodeToDetails node)
                
                Nothing ->
                    -- Try to match against functions
                    case List.Extra.find (\f -> sanitizeFunctionName f.name == nodeId) model.functions of
                        Just func ->
                            Just (functionToDetails func)
                        
                        Nothing ->
                            Nothing


findDataFlowNode : String -> Maybe DataFlowNode
findDataFlowNode nodeId =
    hybridConfigDataFlow
        |> List.Extra.find (\node -> dataFlowNodeId node == nodeId)


findDecisionNode : String -> Maybe DecisionNode
findDecisionNode nodeId =
    let
        allNodes = flattenDecisionTree hybridConfigDecisionTree
    in
    allNodes
        |> List.Extra.find (\node -> decisionNodeId node == nodeId)


flattenDecisionTree : DecisionTree -> List DecisionNode
flattenDecisionTree tree =
    tree.node :: List.concatMap flattenDecisionTree tree.children


dataFlowNodeToDetails : DataFlowNode -> NodeDetails
dataFlowNodeToDetails node =
    { title = dataFlowNodeToString node
    , description = getDataFlowNodeDescription node
    , details = getDataFlowNodeDetailList node
    , module_ = Just (getDataFlowNodeModule node)
    , complexity = Nothing
    , relatedNodes = getRelatedDataFlowNodes node
    }


decisionNodeToDetails : DecisionNode -> NodeDetails
decisionNodeToDetails node =
    { title = decisionNodeToString node
    , description = getDecisionNodeDescription node
    , details = getNodeDetails node
    , module_ = Just (getNodeModule node)
    , complexity = Just (getNodeComplexity node)
    , relatedNodes = []
    }


functionToDetails : FunctionInfo -> NodeDetails
functionToDetails func =
    { title = func.name
    , description = Maybe.withDefault "No documentation available" func.documentation
    , details = 
        [ "Parameters: " ++ String.fromInt (List.length func.parameters)
        , "Calls: " ++ String.fromInt (List.length func.calls)
        , "File: " ++ func.sourceLocation.file
        , "Lines: " ++ String.fromInt func.sourceLocation.startLine ++ "-" ++ String.fromInt func.sourceLocation.endLine
        ]
    , module_ = Just func.module_
    , complexity = Just func.complexityScore
    , relatedNodes = func.calls
    }


getDataFlowNodeDescription : DataFlowNode -> String
getDataFlowNodeDescription node =
    case node of
        CentralDatabase -> "Turso database containing organization configurations"
        OrganizationLoader -> "Loads configuration from central database"
        ContactCounter -> "Counts contacts in org-specific database"
        SizeProfileCalculator -> "Determines size profile based on contact count"
        LoadBalancingComputer -> "Calculates load balancing parameters"
        ConfigOverrideApplier -> "Applies JSON configuration overrides"
        OrgSpecificDatabase -> "SQLite database with contacts and schedules"
        EmailScheduler -> "Main email scheduling logic"
        ExclusionWindowChecker -> "Validates emails against exclusion rules"
        PriorityCalculator -> "Assigns priority scores to emails"
        LoadBalancer -> "Balances email load across days"


getDataFlowNodeDetailList : DataFlowNode -> List String
getDataFlowNodeDetailList node =
    case node of
        CentralDatabase ->
            [ "Contains organizations table with business rules"
            , "Stores size profiles and configuration overrides"
            , "Single source of truth for org settings"
            , "Not replicated - central access only"
            ]
        
        ContactCounter ->
            [ "Executes: SELECT COUNT(*) FROM contacts"
            , "Used for size profile auto-detection"
            , "Falls back to estimates if query fails"
            , "Critical for load balancing calculations"
            ]
        
        _ ->
            [ "Implementation details available in source code" ]


getDataFlowNodeModule : DataFlowNode -> String
getDataFlowNodeModule node =
    case node of
        CentralDatabase -> "Database (Turso connection)"
        OrganizationLoader -> "Database.load_organization_config"
        ContactCounter -> "Database.get_total_contact_count"
        SizeProfileCalculator -> "Size_profiles.auto_detect_profile"
        LoadBalancingComputer -> "Size_profiles.load_balancing_for_profile"
        ConfigOverrideApplier -> "Size_profiles.apply_config_overrides"
        OrgSpecificDatabase -> "Database (SQLite connection)"
        EmailScheduler -> "Email_scheduler"
        ExclusionWindowChecker -> "Exclusion_window"
        PriorityCalculator -> "Types.priority_of_email_type"
        LoadBalancer -> "Load_balancer"


getRelatedDataFlowNodes : DataFlowNode -> List String
getRelatedDataFlowNodes node =
    hybridConfigFlowEdges
        |> List.concatMap (\edge ->
            if edge.from == dataFlowNodeToString node then
                [ sanitizeNodeId edge.to ]
            else if edge.to == dataFlowNodeToString node then
                [ sanitizeNodeId edge.from ]
            else
                []
        )


getDecisionNodeDescription : DecisionNode -> String
getDecisionNodeDescription node =
    case node of
        LoadOrgConfig -> "Initial step: Load organization configuration from central database"
        CheckContactCount -> "Count contacts to determine organization size"
        DetermineProfile -> "Auto-detect or use configured size profile"
        ApplyOverrides -> "Apply JSON configuration overrides from database"
        CalculateCapacity -> "Calculate daily email capacity and batch sizes"
        ProcessContact -> "Process individual contacts for email scheduling"
        CheckExclusions -> "Apply exclusion window rules and business logic"
        CalculatePriority -> "Assign priority scores based on email type"
        ScheduleEmail -> "Create email schedule entries in database"
        BalanceLoad -> "Balance email distribution across days"


viewTypeToString : ViewType -> String
viewTypeToString viewType =
    case viewType of
        DataFlowView -> "Data Flow Architecture"
        DecisionTreeView -> "Decision Tree Process"
        FunctionCallGraphView -> "Function Call Graph"
        ConfigFlowView -> "Configuration Flow"


complexityClass : Int -> String
complexityClass complexity =
    if complexity >= 8 then "high-complexity"
    else if complexity >= 5 then "medium-complexity"
    else "low-complexity"


exampleOrgConfig : ExampleOrg -> OrganizationConfig
exampleOrgConfig example =
    case example of
        SmallOrg ->
            { id = 1
            , name = "Small Insurance Agency"
            , enablePostWindowEmails = True
            , effectiveDateFirstEmailMonths = 11
            , excludeFailedUnderwritingGlobal = False
            , sendWithoutZipcodeForUniversal = True
            , preExclusionBufferDays = 60
            , birthdayDaysBefore = 14
            , effectiveDateDaysBefore = 30
            , sendTimeHour = 9
            , sendTimeMinute = 0
            , timezone = "America/New_York"
            , maxEmailsPerPeriod = 3
            , frequencyPeriodDays = 30
            , sizeProfile = Small
            , configOverrides = Nothing
            }
        
        MediumOrg ->
            { id = 2
            , name = "Regional Insurance Company"
            , enablePostWindowEmails = True
            , effectiveDateFirstEmailMonths = 11
            , excludeFailedUnderwritingGlobal = False
            , sendWithoutZipcodeForUniversal = True
            , preExclusionBufferDays = 60
            , birthdayDaysBefore = 14
            , effectiveDateDaysBefore = 30
            , sendTimeHour = 8
            , sendTimeMinute = 30
            , timezone = "America/Chicago"
            , maxEmailsPerPeriod = 3
            , frequencyPeriodDays = 30
            , sizeProfile = Medium
            , configOverrides = Nothing
            }
        
        LargeOrg ->
            { id = 3
            , name = "State-Wide Insurance Network"
            , enablePostWindowEmails = True
            , effectiveDateFirstEmailMonths = 10
            , excludeFailedUnderwritingGlobal = True
            , sendWithoutZipcodeForUniversal = False
            , preExclusionBufferDays = 45
            , birthdayDaysBefore = 21
            , effectiveDateDaysBefore = 45
            , sendTimeHour = 10
            , sendTimeMinute = 0
            , timezone = "America/Los_Angeles"
            , maxEmailsPerPeriod = 2
            , frequencyPeriodDays = 45
            , sizeProfile = Large
            , configOverrides = Just (Dict.fromList [("daily_send_percentage_cap", Encode.float 0.05)])
            }
        
        EnterpriseOrg ->
            { id = 4
            , name = "National Insurance Corporation"
            , enablePostWindowEmails = False
            , effectiveDateFirstEmailMonths = 12
            , excludeFailedUnderwritingGlobal = True
            , sendWithoutZipcodeForUniversal = False
            , preExclusionBufferDays = 90
            , birthdayDaysBefore = 30
            , effectiveDateDaysBefore = 60
            , sendTimeHour = 8
            , sendTimeMinute = 0
            , timezone = "America/New_York"
            , maxEmailsPerPeriod = 1
            , frequencyPeriodDays = 60
            , sizeProfile = Enterprise
            , configOverrides = Just (Dict.fromList 
                [ ("daily_send_percentage_cap", Encode.float 0.03)
                , ("batch_size", Encode.int 50000)
                , ("ed_daily_soft_limit", Encode.int 2000)
                ])
            }


getLoadBalancingConfig : OrganizationConfig -> LoadBalancingConfig
getLoadBalancingConfig config =
    let
        totalContacts = 
            case config.sizeProfile of
                Small -> 5000
                Medium -> 50000
                Large -> 250000
                Enterprise -> 1000000
        
        baseConfig = 
            case config.sizeProfile of
                Small -> 
                    { dailySendPercentageCap = 0.20
                    , edDailySoftLimit = 50
                    , edSmoothingWindowDays = 3
                    , batchSize = 1000
                    , totalContacts = totalContacts
                    }
                Medium ->
                    { dailySendPercentageCap = 0.10
                    , edDailySoftLimit = 200
                    , edSmoothingWindowDays = 5
                    , batchSize = 5000
                    , totalContacts = totalContacts
                    }
                Large ->
                    { dailySendPercentageCap = 0.07
                    , edDailySoftLimit = 500
                    , edSmoothingWindowDays = 7
                    , batchSize = 10000
                    , totalContacts = totalContacts
                    }
                Enterprise ->
                    { dailySendPercentageCap = 0.05
                    , edDailySoftLimit = 1000
                    , edSmoothingWindowDays = 10
                    , batchSize = 25000
                    , totalContacts = totalContacts
                    }
    in
    -- Apply overrides if present
    case config.configOverrides of
        Just overrides ->
            applyLoadBalancingOverrides baseConfig overrides
        Nothing ->
            baseConfig


applyLoadBalancingOverrides : LoadBalancingConfig -> Dict String Encode.Value -> LoadBalancingConfig
applyLoadBalancingOverrides config overrides =
    config -- Simplified for now


-- HTTP FUNCTIONS

loadFunctionsData : Cmd Msg
loadFunctionsData =
    Http.get
        { url = "/api/functions"  -- This would be served by your OCaml visualizer
        , expect = Http.expectJson LoadFunctions functionsDecoder
        }


functionsDecoder : Decode.Decoder (List FunctionInfo)
functionsDecoder =
    Decode.list functionDecoder


functionDecoder : Decode.Decoder FunctionInfo
functionDecoder =
    Decode.map9 FunctionInfo
        (Decode.field "name" Decode.string)
        (Decode.field "module" Decode.string)
        (Decode.field "parameters" (Decode.list parameterDecoder))
        (Decode.maybe (Decode.field "returnType" Decode.string))
        (Decode.field "complexityScore" Decode.int)
        (Decode.field "calls" (Decode.list Decode.string))
        (Decode.field "isRecursive" Decode.bool)
        (Decode.maybe (Decode.field "documentation" Decode.string))
        (Decode.field "sourceLocation" locationDecoder)


parameterDecoder : Decode.Decoder ( String, Maybe String )
parameterDecoder =
    Decode.map2 Tuple.pair
        (Decode.field "name" Decode.string)
        (Decode.maybe (Decode.field "type" Decode.string))


locationDecoder : Decode.Decoder { file : String, startLine : Int, endLine : Int }
locationDecoder =
    Decode.map3 (\file startLine endLine -> { file = file, startLine = startLine, endLine = endLine })
        (Decode.field "file" Decode.string)
        (Decode.field "startLine" Decode.int)
        (Decode.field "endLine" Decode.int)


httpErrorToString : Http.Error -> String
httpErrorToString error =
    case error of
        Http.BadUrl url -> "Bad URL: " ++ url
        Http.Timeout -> "Request timeout"
        Http.NetworkError -> "Network error"
        Http.BadStatus status -> "Bad status: " ++ String.fromInt status
        Http.BadBody message -> "Bad body: " ++ message


-- MAIN

main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }