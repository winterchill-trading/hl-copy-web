open! Core
open! Async_kernel
open Api_types
module Http = Async_js.Http

type 'a result = 'a Or_error.t Deferred.t

type t =
  { description : string
  ; is_mock : bool
  ; leaders : unit -> Leaders_response.t result
  ; leader : Address.t -> Leader_detail.t result
  ; challenge : Auth.Challenge_request.t -> Auth.Challenge.t result
  ; login : Auth.Login_request.t -> Auth.Session.t result
  ; agent_offer : token:string -> Agent_offer.t result
  ; follow : token:string -> Follow_request.t -> Follow.t result
  ; dashboard : token:string -> Dashboard.t result
  ; follow_command : token:string -> id:string -> Follow_command.t -> Follow.t result
  }

let decode of_yojson body =
  Or_error.try_with (fun () -> of_yojson (Yojson.Safe.from_string body))
  |> Or_error.tag ~tag:"cannot decode the response"
;;

let api_error ~code body =
  let detail =
    match Or_error.try_with (fun () -> Api_error.t_of_yojson (Yojson.Safe.from_string body)) with
    | Ok { error } -> error
    | Error _ -> String.prefix body 200
  in
  Error.of_string (sprintf "HTTP %d: %s" code detail)
;;

let call ?token ?body ~url of_yojson =
  let headers =
    List.filter_opt
      [ Option.map token ~f:(fun token -> "Authorization", "Bearer " ^ token)
      ; Option.map body ~f:(fun _ -> "Content-Type", "application/json")
      ]
  in
  let method_ : Http.Method_with_args.t =
    match body with
    | None -> Get []
    | Some json -> Post (Some (String (Yojson.Safe.to_string json)))
  in
  match%map Http.request ~headers ~url ~response_type:Default method_ with
  | Error _ as e -> e
  | Ok response when response.code >= 200 && response.code < 300 ->
    decode of_yojson response.content
  | Ok response -> Error (api_error ~code:response.code response.content)
;;

let live ~base_url =
  let url path = base_url ^ path in
  { description = base_url
  ; is_mock = false
  ; leaders = (fun () -> call ~url:(url Endpoint.leaders) Leaders_response.t_of_yojson)
  ; leader = (fun a -> call ~url:(url (Endpoint.leader a)) Leader_detail.t_of_yojson)
  ; challenge =
      (fun r ->
        call
          ~url:(url Endpoint.auth_challenge)
          ~body:(Auth.Challenge_request.yojson_of_t r)
          Auth.Challenge.t_of_yojson)
  ; login =
      (fun r ->
        call
          ~url:(url Endpoint.auth_login)
          ~body:(Auth.Login_request.yojson_of_t r)
          Auth.Session.t_of_yojson)
  ; agent_offer =
      (fun ~token ->
        call ~token ~url:(url Endpoint.agent) ~body:(`Assoc []) Agent_offer.t_of_yojson)
  ; follow =
      (fun ~token r ->
        call
          ~token
          ~url:(url Endpoint.follows)
          ~body:(Follow_request.yojson_of_t r)
          Follow.t_of_yojson)
  ; dashboard = (fun ~token -> call ~token ~url:(url Endpoint.follows) Dashboard.t_of_yojson)
  ; follow_command =
      (fun ~token ~id command ->
        call
          ~token
          ~url:(url (Endpoint.follow_command ~id command))
          ~body:(`Assoc [])
          Follow.t_of_yojson)
  }
;;

(* Milliseconds since the epoch from the browser clock, as a float (see Api_types). *)
let now_ms () = Js_of_ocaml.Js.to_float Js_of_ocaml.Js.date##now

let mock ~fixtures =
  let file name of_yojson = call ~url:(fixtures ^ name) of_yojson in
  let account = ref None in
  let with_account f =
    let%map.Deferred.Or_error dashboard =
      match !account with
      | Some d -> return (Ok d)
      | None -> file "dashboard.json" Dashboard.t_of_yojson
    in
    let dashboard, result = f dashboard in
    account := Some dashboard;
    result
  in
  { description = "mock data"
  ; is_mock = true
  ; leaders = (fun () -> file "leaders.json" Leaders_response.t_of_yojson)
  ; leader =
      (fun a ->
        file ("leaders/" ^ Address.to_string a ^ ".json") Leader_detail.t_of_yojson)
  ; challenge = (fun _ -> file "auth-challenge.json" Auth.Challenge.t_of_yojson)
  ; login =
      (fun r ->
        let%map.Deferred.Or_error session = file "session.json" Auth.Session.t_of_yojson in
        { session with address = r.address })
  ; agent_offer = (fun ~token:_ -> file "agent-offer.json" Agent_offer.t_of_yojson)
  ; follow =
      (fun ~token:_ r ->
        with_account (fun d -> Copy_web_model.Mock_state.add_follow d r ~now:(now_ms ())))
  ; dashboard = (fun ~token:_ -> with_account (fun d -> d, d))
  ; follow_command =
      (fun ~token:_ ~id command ->
        with_account (fun d ->
          match Copy_web_model.Mock_state.apply_command d ~id command with
          | Ok (d', follow) -> d', Ok follow
          | Error _ as e -> d, e)
        |> Deferred.map ~f:Or_error.join)
  }
;;

let of_query query =
  match List.Assoc.find query ~equal:String.equal "api" with
  | Some base_url when not (String.is_empty base_url) ->
    live ~base_url:(String.chop_suffix_if_exists base_url ~suffix:"/")
  | _ -> mock ~fixtures:"dev/"
;;
