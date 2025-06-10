module SimpleTest exposing (..)

type alias TestModel = 
    { value : String 
    , count : Int
    }

update : String -> TestModel -> TestModel
update newValue model =
    { model | value = newValue }

test : TestModel
test =
    let
        model = { value = "old", count = 1 }
        newModel = { model | value = "new" }
    in
    newModel