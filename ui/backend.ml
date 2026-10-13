open! Core
open! Async_kernel
open Api_types

type 'a result = 'a Or_error.t Deferred.t

type t =
  { description : string
  ; is_mock : bool
  ; leaders : unit -> Leaders_response.t result
  ; leader : Address.t -> Leader_detail.t result
  ; challenge : Auth.Challenge_request.t -> Auth.Challenge.t result
  ; verify : Auth.Verify_request.t -> Auth.Session.t result
  ; me : token:string -> Me.t result
  ; agent_new : token:string -> Agent_offer.t result
  ; agent_approved : token:string -> Agent_approval.t -> Agent_status.t result
  ; builder_fee : token:string -> Builder_fee_approval.t -> Agent_status.t result
  ; follow : token:string -> Follow_request.t -> Follow.t result
  ; update_follow : token:string -> id:string -> Follow_update.t -> Follow.t result
  ; stop_follow : token:string -> id:string -> Follow.t result
  }

let decode of_yojson body =
  Or_error.try_with (fun () -> of_yojson (Yojson.Safe.from_string body))
  |> Or_error.tag ~tag:"cannot decode the response"
;;

let api_error ~code body =
  let detail =
    match
      Or_error.try_with (fun () -> Api_error.t_of_yojson (Yojson.Safe.from_string body))
    with
    | Ok { error } -> error
    | Error _ -> String.prefix body 200
  in
  Error.of_string (sprintf "HTTP %d: %s" code detail)
;;

(* A plain XMLHttpRequest: Async_js.Http only speaks GET and POST, and the API uses PATCH
   and DELETE for follows. *)
let request ~meth ~headers ~url ~body =
  let open Js_of_ocaml in
  let result = Ivar.create () in
  let req = XmlHttpRequest.create () in
  req##_open (Js.string meth) (Js.string url) Js._true;
  List.iter headers ~f:(fun (k, v) -> req##setRequestHeader (Js.string k) (Js.string v));
  req##.onreadystatechange
  := Js.wrap_callback (fun () ->
       match req##.readyState with
       | DONE ->
         let content =
           Js.Opt.case req##.responseText (fun () -> "") (fun s -> Js.to_string s)
         in
         Ivar.fill_if_empty result (Ok (req##.status, content))
       | _ -> ());
  req##.onerror
  := Dom.handler (fun _ ->
       Ivar.fill_if_empty result (Or_error.error_s [%message "network error" meth url]);
       Js._true);
  (match body with
   | None -> req##send Js.null
   | Some body -> req##send (Js.some (Js.string body)));
  Ivar.read result
;;

let call ?token ?body ?(meth = "GET") ~url of_yojson =
  let meth = if Option.is_some body && String.equal meth "GET" then "POST" else meth in
  let headers =
    List.filter_opt
      [ Option.map token ~f:(fun token -> "Authorization", "Bearer " ^ token)
      ; Option.map body ~f:(fun _ -> "Content-Type", "application/json")
      ]
  in
  let body = Option.map body ~f:Yojson.Safe.to_string in
  match%map request ~meth ~headers ~url ~body with
  | Error _ as e -> e
  | Ok (code, content) when code >= 200 && code < 300 -> decode of_yojson content
  | Ok (code, content) -> Error (api_error ~code content)
;;

let live ~base_url =
  let url path = base_url ^ path in
  let empty = `Assoc [] in
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
  ; verify =
      (fun r ->
        call
          ~url:(url Endpoint.auth_verify)
          ~body:(Auth.Verify_request.yojson_of_t r)
          Auth.Session.t_of_yojson)
  ; me = (fun ~token -> call ~token ~url:(url Endpoint.me) Me.t_of_yojson)
  ; agent_new =
      (fun ~token ->
        call ~token ~url:(url Endpoint.agent_new) ~body:empty Agent_offer.t_of_yojson)
  ; agent_approved =
      (fun ~token r ->
        call
          ~token
          ~url:(url Endpoint.agent_approved)
          ~body:(Agent_approval.yojson_of_t r)
          Agent_status.t_of_yojson)
  ; builder_fee =
      (fun ~token r ->
        call
          ~token
          ~url:(url Endpoint.builder_fee)
          ~body:(Builder_fee_approval.yojson_of_t r)
          Agent_status.t_of_yojson)
  ; follow =
      (fun ~token r ->
        call
          ~token
          ~url:(url Endpoint.follows)
          ~body:(Follow_request.yojson_of_t r)
          Follow.t_of_yojson)
  ; update_follow =
      (fun ~token ~id r ->
        call
          ~token
          ~meth:"PATCH"
          ~url:(url (Endpoint.follow ~id))
          ~body:(Follow_update.yojson_of_t r)
          Follow.t_of_yojson)
  ; stop_follow =
      (fun ~token ~id ->
        call ~token ~meth:"DELETE" ~url:(url (Endpoint.follow ~id)) Follow.t_of_yojson)
  }
;;

(* Milliseconds since the epoch from the browser clock, as a float (see Api_types). *)
let now_ms () = Js_of_ocaml.Js.to_float Js_of_ocaml.Js.date##now

let mock ~fixtures =
  let module Mock_state = Copy_web_model.Mock_state in
  let file name of_yojson = call ~url:(fixtures ^ name) of_yojson in
  let account = ref None in
  (* Every change goes through [f] on the current account, loaded from me.json once. *)
  let with_account f =
    let%map.Deferred.Or_error me =
      match !account with
      | Some me -> return (Ok me)
      | None -> file "me.json" Me.t_of_yojson
    in
    let%map.Or_error me, result = f me in
    account := Some me;
    result
  in
  let deferred_join d = Deferred.map d ~f:Or_error.join in
  { description = "mock data"
  ; is_mock = true
  ; leaders = (fun () -> file "leaders.json" Leaders_response.t_of_yojson)
  ; leader =
      (fun a ->
        file ("leaders/" ^ Address.to_string a ^ ".json") Leader_detail.t_of_yojson)
  ; challenge = (fun _ -> file "auth-challenge.json" Auth.Challenge.t_of_yojson)
  ; verify =
      (fun r ->
        let%map.Deferred.Or_error session =
          file "session.json" Auth.Session.t_of_yojson
        in
        { session with address = r.address })
  ; me = (fun ~token:_ -> with_account (fun me -> Ok (me, me)) |> deferred_join)
  ; agent_new = (fun ~token:_ -> file "agent-offer.json" Agent_offer.t_of_yojson)
  ; agent_approved =
      (fun ~token:_ r ->
        with_account (fun me -> Ok (Mock_state.approve_agent me r ~now:(now_ms ())))
        |> deferred_join)
  ; builder_fee =
      (fun ~token:_ r ->
        with_account (fun me -> Mock_state.approve_builder_fee me r) |> deferred_join)
  ; follow =
      (fun ~token:_ r ->
        with_account (fun me -> Mock_state.add_follow me r ~now:(now_ms ()))
        |> deferred_join)
  ; update_follow =
      (fun ~token:_ ~id r ->
        with_account (fun me -> Mock_state.update_follow me ~id r) |> deferred_join)
  ; stop_follow =
      (fun ~token:_ ~id ->
        with_account (fun me -> Mock_state.stop_follow me ~id) |> deferred_join)
  }
;;

let of_query query =
  match List.Assoc.find query ~equal:String.equal "api" with
  | Some base_url when not (String.is_empty base_url) ->
    live ~base_url:(String.chop_suffix_if_exists base_url ~suffix:"/")
  | _ -> mock ~fixtures:"dev/"
;;
