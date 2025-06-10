module FieldTest exposing (..)

import HybridConfig.Types exposing (..)

-- Test updating different fields
testSelectedNode : VisualizationState -> VisualizationState
testSelectedNode state =
    { state | selectedNode = Just "test" }

testExpandedNodes : VisualizationState -> VisualizationState  
testExpandedNodes state =
    { state | expandedNodes = ["test"] }

testShowModules : VisualizationState -> VisualizationState
testShowModules state =
    { state | showModules = False }

testCurrentView : VisualizationState -> VisualizationState
testCurrentView state =
    { state | currentView = DecisionTreeView }