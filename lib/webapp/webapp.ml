open Fmlib_browser

type msg =
    | Decrement
    | Increment

type state = {
    counter: int;
}

let view (state: state): msg Html.t * string =
    let open Html in
    let open Attribute in
    div []
        [ h1 [] [text "Welcome to the Oasis framework!"];
         button
            [color "blue"; on_click Decrement]
            [text "-"]
        ; span
            [background_color "silver"; font_size "20px"]
            [text (string_of_int state.counter)]
        ; button
            [color "blue"; on_click Increment]
            [text "+"]
        ]
    ,
    "Oasis Template"

let update (state: state): msg -> state * msg Command.t = function
    | Decrement ->
        { state with counter = state.counter - 1 }, Command.none
    | Increment ->
        { state with counter = state.counter + 1 }, Command.none

let _ =
    basic_application
        { counter = 0 }
        Command.none
        view
        (fun _ -> Subscription.none)
        update 
