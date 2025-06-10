module Test exposing (..)

import Html exposing (..)

type alias Model = { value : String }

update : String -> Model -> Model
update newValue model =
    { model | value = newValue }

view : Model -> Html msg
view model =
    div [] [ text model.value ]