module ContextTest exposing (..)

import HybridConfig.Types exposing (..)

type alias TestModel =
    { visualizationState : VisualizationState
    , otherField : String
    }

type TestMsg = ChangeView ViewType

updateTest : TestMsg -> TestModel -> TestModel
updateTest msg model =
    case msg of
        ChangeView viewType ->
            let
                currentState = model.visualizationState
                newVisualizationState =
                    { currentState | currentView = viewType }
            in
            { model | visualizationState = newVisualizationState }