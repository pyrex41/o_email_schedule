module ImportTest exposing (..)

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

type alias TestModel = 
    { state : VisualizationState
    }

updateTest : ViewType -> TestModel -> TestModel  
updateTest viewType model =
    let
        newState = { model.state | currentView = viewType }
    in
    { model | state = newState }

test : String
test = "Import test successful"