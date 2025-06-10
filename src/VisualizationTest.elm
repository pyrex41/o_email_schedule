module VisualizationTest exposing (..)

import HybridConfig.Types exposing (..)

updateView : ViewType -> VisualizationState -> VisualizationState
updateView newView state =
    { state | currentView = newView }

test : VisualizationState
test =
    let
        state = defaultVisualizationState
        newState = { state | currentView = DecisionTreeView }
    in
    newState