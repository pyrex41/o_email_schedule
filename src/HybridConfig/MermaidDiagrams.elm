module HybridConfig.MermaidDiagrams exposing (..)

import Dict exposing (Dict)
import HybridConfig.Types exposing (..)
import HybridConfig.DataFlow exposing (..)


-- Generate the main hybrid configuration data flow diagram
generateDataFlowDiagram : VisualizationState -> String
generateDataFlowDiagram state =
    let
        initConfig = "%%{init: {\"flowchart\": {\"defaultRenderer\": \"elk\", \"curve\": \"basis\"}} }%%"
        
        flowChartHeader = "flowchart TD"
        
        -- Generate nodes with styling based on their type
        nodes = 
            hybridConfigDataFlow
                |> List.map (dataFlowNodeToMermaid state)
                |> String.join "\n    "
        
        -- Generate edges with labels and styling
        edges = 
            hybridConfigFlowEdges
                |> List.map (flowEdgeToMermaid state)
                |> String.join "\n    "
        
        -- Generate click handlers for interactivity
        clickHandlers = 
            hybridConfigDataFlow
                |> List.map (nodeClickHandler state)
                |> String.join "\n    "
        
        -- CSS styling for different flow types
        styling = flowStyling
        
        -- Subgraph groupings
        subgraphs = generateSubgraphs state
    in
    [ initConfig
    , flowChartHeader
    , "    " ++ nodes
    , "    " ++ edges
    , "    " ++ subgraphs
    , "    " ++ clickHandlers
    , "    " ++ styling
    ]
        |> String.join "\n"


-- Convert a data flow node to Mermaid syntax
dataFlowNodeToMermaid : VisualizationState -> DataFlowNode -> String
dataFlowNodeToMermaid state node =
    let
        nodeId = dataFlowNodeId node
        displayName = dataFlowNodeToString node
        
        -- Determine node shape based on type
        (nodeShape, cssClass) = 
            case node of
                CentralDatabase -> ("[(\"" ++ displayName ++ "\")]", "database-node")
                OrgSpecificDatabase -> ("[(\"" ++ displayName ++ "\")]", "database-node")
                OrganizationLoader -> ("[\"" ++ displayName ++ "\"]", "loader-node")
                ContactCounter -> ("[\"" ++ displayName ++ "\"]", "counter-node")
                SizeProfileCalculator -> ("{\"" ++ displayName ++ "\"}", "calculator-node")
                LoadBalancingComputer -> ("{\"" ++ displayName ++ "\"}", "calculator-node")
                ConfigOverrideApplier -> ("{\"" ++ displayName ++ "\"}", "config-node")
                EmailScheduler -> ("(\"" ++ displayName ++ "\")", "processor-node")
                ExclusionWindowChecker -> ("(\"" ++ displayName ++ "\")", "validator-node")
                PriorityCalculator -> ("(\"" ++ displayName ++ "\")", "calculator-node")
                LoadBalancer -> ("(\"" ++ displayName ++ "\")", "balancer-node")
        
        -- Add highlighting if node is selected or in highlighted path
        finalClass = 
            if state.selectedNode == Just nodeId then
                cssClass ++ " selected"
            else if List.member nodeId state.highlightedPath then
                cssClass ++ " highlighted"
            else
                cssClass
    in
    nodeId ++ nodeShape ++ ":::" ++ finalClass


-- Convert a flow edge to Mermaid syntax
flowEdgeToMermaid : VisualizationState -> FlowEdge -> String
flowEdgeToMermaid state edge =
    let
        fromId = sanitizeNodeId edge.from
        toId = sanitizeNodeId edge.to
        
        -- Choose edge style based on flow type
        (edgeStyle, edgeClass) = 
            case edge.flowType of
                DataFlow_ -> ("-->", "data-flow")
                ConfigFlow -> ("-.->", "config-flow")
                ControlFlow -> ("==>", "control-flow")
                ErrorFlow -> ("-.->", "error-flow")
        
        -- Add label if present
        labelPart = 
            case edge.label of
                Just label -> "|" ++ label ++ "|"
                Nothing -> ""
        
        -- Add highlighting if edge is in highlighted path
        finalEdgeStyle = 
            if List.member fromId state.highlightedPath && List.member toId state.highlightedPath then
                edgeStyle ++ " " ++ edgeClass ++ " highlighted"
            else
                edgeStyle ++ " " ++ edgeClass
    in
    fromId ++ " " ++ finalEdgeStyle ++ " " ++ toId ++ labelPart


-- Generate decision tree diagram
generateDecisionTreeDiagram : VisualizationState -> String
generateDecisionTreeDiagram state =
    let
        initConfig = "%%{init: {\"flowchart\": {\"defaultRenderer\": \"elk\"}} }%%"
        flowChartHeader = "flowchart TD"
        
        -- Generate tree nodes recursively
        treeNodes = generateDecisionTreeNodes state hybridConfigDecisionTree ""
        
        -- Generate click handlers for decision nodes
        clickHandlers = generateDecisionClickHandlers state hybridConfigDecisionTree
        
        -- Styling for decision tree
        treeStyling = decisionTreeStyling
    in
    [ initConfig
    , flowChartHeader
    , treeNodes
    , clickHandlers
    , treeStyling
    ]
        |> String.join "\n"


-- Recursively generate decision tree nodes
generateDecisionTreeNodes : VisualizationState -> DecisionTree -> String -> String
generateDecisionTreeNodes state tree parentId =
    let
        nodeId = decisionNodeId tree.node
        displayName = decisionNodeToString tree.node
        
        -- Determine if node should be expanded
        isExpanded = List.member nodeId state.expandedNodes
        
        -- Create the node
        nodeShape = 
            if List.length tree.children > 0 then
                if isExpanded then
                    "(" ++ displayName ++ " ➖)"
                else
                    "(" ++ displayName ++ " ➕)"
            else
                "[" ++ displayName ++ "]"
        
        -- Styling based on complexity
        complexity = getNodeComplexity tree.node
        complexityClass = 
            if complexity >= 8 then "high-complexity"
            else if complexity >= 5 then "medium-complexity"
            else "low-complexity"
        
        currentNode = "    " ++ nodeId ++ nodeShape ++ ":::" ++ complexityClass
        
        -- Create edge from parent if it exists
        parentEdge = 
            if parentId /= "" then
                let
                    conditionLabel = 
                        case tree.condition of
                            Just cond -> "|" ++ cond ++ "|"
                            Nothing -> ""
                in
                "    " ++ parentId ++ " --> " ++ nodeId ++ conditionLabel
            else
                ""
        
        -- Generate child nodes if expanded
        childNodes = 
            if isExpanded then
                tree.children
                    |> List.map (\child -> generateDecisionTreeNodes state child nodeId)
                    |> String.join "\n"
            else
                ""
    in
    [ currentNode
    , parentEdge
    , childNodes
    ]
        |> List.filter ((/=) "")
        |> String.join "\n"


-- Generate function call graph integration
generateFunctionCallGraph : List FunctionInfo -> VisualizationState -> String
generateFunctionCallGraph functions state =
    let
        initConfig = "%%{init: {\"flowchart\": {\"defaultRenderer\": \"elk\"}} }%%"
        flowChartHeader = "flowchart LR"
        
        -- Filter functions by complexity if specified
        filteredFunctions = 
            case state.filterComplexity of
                Just threshold -> List.filter (\f -> f.complexityScore <= threshold) functions
                Nothing -> functions
        
        -- Generate function nodes
        functionNodes = 
            filteredFunctions
                |> List.map (functionToMermaidNode state)
                |> String.join "\n    "
        
        -- Generate call edges
        callEdges = 
            generateCallEdges filteredFunctions state
        
        -- Module subgraphs if enabled
        moduleSubgraphs = 
            if state.showModules then
                generateModuleSubgraphs filteredFunctions
            else
                ""
        
        -- Click handlers for functions
        functionClickHandlers = 
            filteredFunctions
                |> List.map (\f -> "    click " ++ sanitizeFunctionName f.name ++ " callback \"Show " ++ f.name ++ " details\"")
                |> String.join "\n"
        
        styling = functionCallStyling
    in
    [ initConfig
    , flowChartHeader
    , "    " ++ functionNodes
    , "    " ++ callEdges
    , "    " ++ moduleSubgraphs
    , "    " ++ functionClickHandlers
    , "    " ++ styling
    ]
        |> String.join "\n"


-- Convert function to Mermaid node
functionToMermaidNode : VisualizationState -> FunctionInfo -> String
functionToMermaidNode state func =
    let
        nodeId = sanitizeFunctionName func.name
        displayName = 
            if state.showModules && func.module_ /= "" then
                func.module_ ++ "." ++ func.name
            else
                func.name
        
        -- Add recursion indicator
        recursionIndicator = if func.isRecursive then " 🔄" else ""
        
        -- Complexity-based styling
        complexityClass = 
            if func.complexityScore >= 10 then "high-complexity"
            else if func.complexityScore >= 5 then "medium-complexity"
            else "low-complexity"
        
        selectedClass = 
            if state.selectedNode == Just nodeId then " selected" else ""
    in
    nodeId ++ "[\"" ++ displayName ++ recursionIndicator ++ "\"]:::" ++ complexityClass ++ selectedClass


-- Helper functions
dataFlowNodeId : DataFlowNode -> String
dataFlowNodeId node =
    sanitizeNodeId (dataFlowNodeToString node)


decisionNodeId : DecisionNode -> String
decisionNodeId node =
    sanitizeNodeId (decisionNodeToString node)


sanitizeNodeId : String -> String
sanitizeNodeId str =
    str
        |> String.replace " " "_"
        |> String.replace "(" ""
        |> String.replace ")" ""
        |> String.replace "-" "_"
        |> String.replace "." "_"


sanitizeFunctionName : String -> String
sanitizeFunctionName name =
    name
        |> String.replace "_" "__"
        |> String.replace " " "_"
        |> String.replace "." "_"


-- Generate subgraphs for organization
generateSubgraphs : VisualizationState -> String
generateSubgraphs state =
    """
    subgraph central ["Central Configuration"]
        Central_Database_Turso
        Organization_Config_Loader
    end
    
    subgraph orgdb ["Organization Database"]
        Org_Specific_Database
        Contact_Counter
    end
    
    subgraph config ["Configuration Processing"]
        Size_Profile_Calculator
        Load_Balancing_Computer
        Config_Override_Applier
    end
    
    subgraph processing ["Email Processing"]
        Email_Scheduler
        Exclusion_Window_Checker
        Priority_Calculator
        Load_Balancer
    end"""


-- Generate click handlers for nodes
nodeClickHandler : VisualizationState -> DataFlowNode -> String
nodeClickHandler state node =
    let
        nodeId = dataFlowNodeId node
    in
    "click " ++ nodeId ++ " callback \"Show " ++ dataFlowNodeToString node ++ " details\""


-- Generate click handlers for decision nodes
generateDecisionClickHandlers : VisualizationState -> DecisionTree -> String
generateDecisionClickHandlers state tree =
    let
        nodeId = decisionNodeId tree.node
        currentHandler = "click " ++ nodeId ++ " callback \"Toggle " ++ decisionNodeToString tree.node ++ "\""
        
        childHandlers = 
            tree.children
                |> List.map (generateDecisionClickHandlers state)
                |> String.join "\n    "
    in
    if childHandlers /= "" then
        "    " ++ currentHandler ++ "\n    " ++ childHandlers
    else
        "    " ++ currentHandler


-- Generate call edges between functions
generateCallEdges : List FunctionInfo -> VisualizationState -> String
generateCallEdges functions state =
    let
        functionNames = List.map .name functions |> List.foldl (\name acc -> Dict.insert name True acc) Dict.empty
        
        edges = 
            functions
                |> List.concatMap (\func -> 
                    func.calls
                        |> List.filter (\callee -> Dict.member callee functionNames)
                        |> List.map (\callee -> 
                            sanitizeFunctionName func.name ++ " --> " ++ sanitizeFunctionName callee
                        )
                )
    in
    edges |> String.join "\n    "


-- Generate module subgraphs
generateModuleSubgraphs : List FunctionInfo -> String
generateModuleSubgraphs functions =
    let
        moduleGroups = 
            functions
                |> List.foldl (\func acc -> 
                    Dict.update func.module_ 
                        (\existing -> 
                            case existing of
                                Just funcs -> Just (func :: funcs)
                                Nothing -> Just [func]
                        ) 
                        acc
                ) Dict.empty
        
        subgraphsText = 
            moduleGroups
                |> Dict.toList
                |> List.map (\(moduleName, funcs) ->
                    let
                        moduleId = sanitizeNodeId moduleName
                        functionIds = List.map (.name >> sanitizeFunctionName) funcs |> String.join "\n        "
                    in
                    "    subgraph " ++ moduleId ++ " [\"" ++ moduleName ++ "\"]\n        " ++ functionIds ++ "\n    end"
                )
                |> String.join "\n"
    in
    subgraphsText


-- CSS styling for different node types
flowStyling : String
flowStyling =
    """
    classDef database-node fill:#e1f5fe,stroke:#0277bd,stroke-width:3px
    classDef loader-node fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef counter-node fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    classDef calculator-node fill:#fff3e0,stroke:#ef6c00,stroke-width:2px
    classDef config-node fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    classDef processor-node fill:#e0f2f1,stroke:#00695c,stroke-width:2px
    classDef validator-node fill:#fff8e1,stroke:#f57f17,stroke-width:2px
    classDef balancer-node fill:#f1f8e9,stroke:#33691e,stroke-width:2px
    classDef selected fill:#ffeb3b,stroke:#f57f17,stroke-width:4px
    classDef highlighted fill:#c8e6c9,stroke:#4caf50,stroke-width:3px
    
    linkStyle 0,1,2 stroke:#2196f3,stroke-width:3px
    linkStyle 3,4 stroke:#ff9800,stroke-width:2px
    linkStyle 5,6 stroke:#9c27b0,stroke-width:2px"""


-- CSS styling for decision tree
decisionTreeStyling : String
decisionTreeStyling =
    """
    classDef low-complexity fill:#d4edda,stroke:#28a745,stroke-width:2px
    classDef medium-complexity fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    classDef high-complexity fill:#f8d7da,stroke:#dc3545,stroke-width:2px
    classDef selected fill:#ffeb3b,stroke:#f57f17,stroke-width:4px"""


-- CSS styling for function call graph
functionCallStyling : String
functionCallStyling =
    """
    classDef low-complexity fill:#d4edda,stroke:#28a745,stroke-width:2px
    classDef medium-complexity fill:#fff3cd,stroke:#ffc107,stroke-width:2px
    classDef high-complexity fill:#f8d7da,stroke:#dc3545,stroke-width:2px
    classDef selected fill:#ffeb3b,stroke:#f57f17,stroke-width:4px"""