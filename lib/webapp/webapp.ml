open Fmlib_browser

module Http =
struct
    type error = Task.http_error
    type res = (string, error) result
end

type msg =
    | Decrement
    | Increment
    | SendRequest
    | BackendReply of Common.message_object
    | ErrorResponse

type state = {
    counter: int;
    response_text: string;
}

let unpack_json_from_response (response: ((string, Http.error) result)) =
    match response with
     | Ok a  -> 
        let backend_message = Yojson.Safe.from_string a |> Common.message_object_of_yojson in
        BackendReply backend_message
    | Error _ -> ErrorResponse
    
let fetch_from_backend = Command.attempt unpack_json_from_response (Task.http_text "GET" "/" [] "")

let view (state: state): msg Html.t * string =
    let open Html in
    let open Attribute in
    div []
        [ h1 [] [text "Welcome to Full-Stack Ocaml!"];
         button
            [color "blue"; on_click Decrement]
            [text "-"]
        ; span
            [background_color "silver"; font_size "20px"]
            [text (string_of_int state.counter)]
        ; button
            [color "blue"; on_click Increment]
            [text "+"]
        ; button
            [color "green"; on_click SendRequest]
            [text "Query Backend"]
        ; text state.response_text
        ]
    ,
    "FullStack Ocaml Template"

let update (state: state): msg -> state * msg Command.t = function
    | Decrement ->
        { state with counter = state.counter - 1 }, Command.none
    | Increment ->
        { state with counter = state.counter + 1 }, Command.none
    | SendRequest ->
        state, fetch_from_backend
    | BackendReply response ->
        {state with response_text = String.cat response.message (Int.to_string response.id) }, Command.none
    | ErrorResponse ->
        {state with response_text = "Failed request"}, Command.none

let _ =
    basic_application
        { counter = 0; response_text = "" }
        Command.none
        view
        (fun _ -> Subscription.none)
        update 
