module MainMinimal exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import HybridConfig.Types exposing (..)
import HybridConfig.DataFlow exposing (..)
import HybridConfig.MermaidDiagrams exposing (..)

type alias Model =
    { visualizationState : VisualizationState
    , currentDiagram : String
    }

type Msg
    = ChangeView ViewType

init : () -> ( Model, Cmd Msg )
init _ =
    let
        initialModel =
            { visualizationState = defaultVisualizationState
            , currentDiagram = ""
            }
    in
    ( { initialModel 
      | currentDiagram = generateDataFlowDiagram initialModel.visualizationState
      }
    , Cmd.none
    )

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
                        _ -> generateDataFlowDiagram newVisualizationState
            in
            ( { model 
              | visualizationState = newVisualizationState
              , currentDiagram = newDiagram
              }
            , Cmd.none
            )

view : Model -> Html Msg
view model =
    div []
        [ h1 [] [ text "Hybrid Config Visualizer" ]
        , button [ onClick (ChangeView DataFlowView) ] [ text "Data Flow" ]
        , div [] [ text model.currentDiagram ]
        ]

main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = \_ -> Sub.none
        }