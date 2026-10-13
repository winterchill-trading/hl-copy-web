open! Core
open! Async_kernel
open! Bonsai_web
open Api_types
module N = Vdom.Node
module A = Vdom.Attr

module Status = struct
  type t =
    | Idle
    | Busy of string
    | Failed of Error.t
end

let sign_in ~(backend : Backend.t) ~set_status ~login (wallet : Wallet.t) =
  let open Effect.Let_syntax in
  let%bind () = set_status (Status.Busy "Waiting for the signature in your wallet...") in
  let%bind result =
    Effect.of_deferred_thunk (fun () ->
      let open Deferred.Or_error.Let_syntax in
      let%bind challenge = backend.challenge { address = wallet.address } in
      let%bind signature = Wallet.personal_sign wallet ~message:challenge.message in
      let%map session =
        backend.verify { address = wallet.address; nonce = challenge.nonce; signature }
      in
      session)
  in
  match result with
  | Ok session ->
    let%bind () = set_status Idle in
    let%bind () = login wallet session in
    Nav.navigate Dashboard
  | Error e -> set_status (Failed e)
;;

let connect_injected ~backend ~set_status ~login =
  let open Effect.Let_syntax in
  (* Look for the provider when the button is clicked, not when the page renders: the
     extension may inject it after the app starts. *)
  match%bind Effect.of_thunk Ethereum.detect with
  | None ->
    set_status
      (Status.Failed
         (Error.of_string
            "No browser wallet found. Install a wallet extension, or use the demo signer \
             with mock data."))
  | Some provider ->
    let%bind () = set_status (Busy "Connecting to your wallet...") in
    (match%bind Effect.of_deferred_fun Wallet.connect provider with
     | Error e -> set_status (Failed e)
     | Ok wallet -> sign_in ~backend ~set_status ~login wallet)
;;

let view ~(backend : Backend.t) ~status ~set_status ~login ~session =
  let busy =
    match (status : Status.t) with
    | Busy _ -> true
    | Idle | Failed _ -> false
  in
  let signed_in =
    match session with
    | None -> N.none
    | Some ((wallet : Wallet.t), (s : Auth.Session.t)) ->
      Widgets.notice
        (sprintf
           "Signed in as %s%s."
           (Address.to_string s.address)
           (if Wallet.is_demo wallet then " with the demo signer" else ""))
  in
  Widgets.section
    "Connect wallet"
    [ N.p
        [ N.text
            "Sign in by signing a one-time message with your wallet. Signing it costs \
             nothing and grants no permission to trade; following a leader later asks \
             for a separate approval of a trading-only agent key."
        ]
    ; signed_in
    ; N.div
        ~attrs:[ A.class_ "actions" ]
        [ Widgets.button
            ~primary:true
            ~disabled:busy
            ~on_click:(connect_injected ~backend ~set_status ~login)
            "Connect wallet"
        ; (if backend.is_mock
           then
             Widgets.button
               ~disabled:busy
               ~on_click:(sign_in ~backend ~set_status ~login Wallet.demo)
               "Use demo signer"
           else N.none)
        ]
    ; (match status with
       | Idle -> N.none
       | Busy text -> N.div ~attrs:[ A.class_ "loading" ] [ N.text text ]
       | Failed e -> Widgets.error_box e)
    ]
;;

let component ~backend ~login ~session (local_ graph) =
  let open Bonsai.Let_syntax in
  let status, set_status = Bonsai.state Status.Idle graph in
  let%map status and set_status and session and login in
  view ~backend ~status ~set_status ~login ~session
;;
