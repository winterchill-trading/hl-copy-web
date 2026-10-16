open! Core
open! Async_kernel
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr
module Field = Follow_form.Field

module Status = struct
  type t =
    | Idle
    | Busy of string
    | Failed of Error.t
end

let text_field ~form ~set_form ~errors field =
  let error = List.Assoc.find errors field ~equal:Field.equal in
  N.label
    ~attrs:[ A.class_ "field" ]
    [ N.span [ N.text (Field.label field) ]
    ; N.input
        ~attrs:
          [ A.type_ "text"
          ; A.name (Sexp.to_string [%sexp (field : Field.t)])
          ; A.value (Follow_form.get form field)
          ; A.on_input (fun _ v -> set_form (Follow_form.set form field v))
          ; A.classes (if Option.is_some error then [ "invalid" ] else [])
          ]
        ()
    ; (match error with
       | None -> N.none
       | Some msg -> N.span ~attrs:[ A.class_ "field-error" ] [ N.text msg ])
    ]
;;

let scale_select ~(form : Follow_form.t) ~set_form =
  N.label
    ~attrs:[ A.class_ "field" ]
    [ N.span [ N.text "Scale mode" ]
    ; N.select
        ~attrs:
          [ A.name "scale_kind"
          ; A.on_change (fun _ v ->
              match Follow_form.Scale_kind.of_string v with
              | Some scale_kind -> set_form { form with scale_kind }
              | None -> Effect.Ignore)
          ]
        (List.map Follow_form.Scale_kind.all ~f:(fun kind ->
           N.option
             ~attrs:
               (A.value (Follow_form.Scale_kind.to_string kind)
                ::
                (if Follow_form.Scale_kind.equal kind form.scale_kind
                 then [ A.selected ]
                 else []))
             [ N.text (Follow_form.Scale_kind.label kind) ]))
    ]
;;

let algo_select ~(form : Follow_form.t) ~set_form =
  N.label
    ~attrs:[ A.class_ "field" ]
    [ N.span [ N.text "Execution" ]
    ; N.select
        ~attrs:
          [ A.name "algo"
          ; A.on_change (fun _ v ->
              match Algo_choice.Kind.of_string v with
              | Some kind -> set_form (Follow_form.with_algo form kind)
              | None -> Effect.Ignore)
          ]
        (List.map Algo_choice.Kind.all ~f:(fun kind ->
           N.option
             ~attrs:
               (A.value (Algo_choice.Kind.to_string kind)
                ::
                (if Algo_choice.Kind.equal kind form.algo then [ A.selected ] else []))
             [ N.text (Algo_choice.Kind.label kind) ]))
    ; N.span ~attrs:[ A.class_ "muted" ] [ N.text (Algo_choice.Kind.help form.algo) ]
    ]
;;

let form_view ~form ~set_form ~errors =
  let field = text_field ~form ~set_form ~errors in
  N.div
    ~attrs:[ A.class_ "form-grid" ]
    [ scale_select ~form ~set_form
    ; (match form.scale_kind with
       | Equity_ratio -> N.none
       | Multiplier | Fixed_notional -> field Scale_value)
    ; field Max_leverage
    ; field Max_notional_per_symbol
    ; field Max_daily_loss
    ; field Min_order_notional
    ; field Allowlist
    ; algo_select ~form ~set_form
    ; (match form.algo with
       | Immediate -> N.none
       | Twap | Adaptive | Passive -> field Algo_seconds)
    ; (match form.algo with
       | Twap -> field Algo_slices
       | Immediate | Adaptive | Passive -> N.none)
    ]
;;

let typed_data_view ~title json =
  N.details
    ~attrs:[ A.create "open" "" ]
    [ N.summary [ N.text title ]
    ; N.pre
        ~attrs:[ A.class_ "typed-data" ]
        [ N.text (Yojson.Safe.pretty_to_string json) ]
    ]
;;

(* Wallets refuse typed data whose domain chain id differs from the connected chain, and
   Hyperliquid accepts any chain id as long as the action carries the one it was signed
   under, so the offer's default is replaced by the wallet's. *)
let with_chain_id (offer : Agent_offer.t) chain_id : Agent_offer.t =
  match chain_id with
  | None -> offer
  | Some signature_chain_id ->
    { approve_agent = { offer.approve_agent with signature_chain_id }
    ; approve_builder_fee =
        Option.map offer.approve_builder_fee ~f:(fun b -> { b with signature_chain_id })
    }
;;

let approve
  ~(backend : Backend.t)
  ~(wallet : Wallet.t)
  ~(session : Auth.Session.t)
  ~(offer : Agent_offer.t)
  ~include_builder_fee
  =
  let open Deferred.Or_error.Let_syntax in
  let token = session.token in
  let%bind chain_id = Wallet.chain_id wallet in
  let offer = with_chain_id offer chain_id in
  let%bind signature =
    Wallet.sign_typed_data wallet (Approve_agent.typed_data offer.approve_agent)
  in
  let%bind (_ : Agent_status.t) =
    backend.agent_approved ~token { approve_agent = offer.approve_agent; signature }
  in
  match offer.approve_builder_fee with
  | Some approve_builder_fee when include_builder_fee ->
    let%bind signature =
      Wallet.sign_typed_data wallet (Approve_builder_fee.typed_data approve_builder_fee)
    in
    let%map (_ : Agent_status.t) =
      backend.builder_fee ~token { approve_builder_fee; signature }
    in
    ()
  | Some _ | None -> return ()
;;

(* Approves a new agent first when [offer] is given, then creates the follow. *)
let follow_effect
  ~backend
  ~wallet
  ~session
  ~leader
  ~validated
  ~offer
  ~include_builder_fee
  ~set_status
  =
  let open Effect.Let_syntax in
  match validated with
  | Error _ -> Effect.Ignore
  | Ok valid ->
    let%bind () =
      set_status
        (Status.Busy
           (if Option.is_some offer
            then "Waiting for the signatures in your wallet..."
            else "Creating the follow..."))
    in
    (match%bind
       Effect.of_deferred_thunk (fun () ->
         let open Deferred.Or_error.Let_syntax in
         let%bind () =
           match offer with
           | None -> return ()
           | Some offer -> approve ~backend ~wallet ~session ~offer ~include_builder_fee
         in
         (backend : Backend.t).follow
           ~token:session.Auth.Session.token
           (Follow_form.request valid ~leader))
     with
     | Ok (_ : Follow.t) ->
       let%bind () = set_status Status.Idle in
       Nav.navigate Dashboard
     | Error e -> set_status (Failed e))
;;

let approval_view
  ~(offer : Agent_offer.t)
  ~include_builder_fee
  ~set_include_builder_fee
  ~submit
  ~set_offer
  ~busy
  ~valid
  =
  N.div
    [ N.p
        [ N.text
            "Your wallet will sign this approveAgent action. It lets the agent address \
             below place and cancel orders for your account; it cannot withdraw or \
             transfer funds. You can revoke it from Hyperliquid at any time."
        ]
    ; typed_data_view
        ~title:"approveAgent typed data (EIP-712)"
        (Approve_agent.typed_data offer.approve_agent)
    ; (match offer.approve_builder_fee with
       | None -> N.none
       | Some b ->
         N.div
           [ N.label
               ~attrs:[ A.class_ "check" ]
               [ N.input
                   ~attrs:
                     [ A.type_ "checkbox"
                     ; A.checked_prop include_builder_fee
                     ; A.on_click (fun _ ->
                         set_include_builder_fee (not include_builder_fee))
                     ]
                   ()
               ; N.textf
                   " Also approve a builder fee of up to %s for %s"
                   b.max_fee_rate
                   (Address.short b.builder)
               ]
           ; (if include_builder_fee
              then
                typed_data_view
                  ~title:"approveBuilderFee typed data (EIP-712)"
                  (Approve_builder_fee.typed_data b)
              else N.none)
           ])
    ; N.p
        ~attrs:[ A.class_ "muted" ]
        [ N.text
            "The domain chain id is replaced by your wallet's current chain when you \
             sign."
        ]
    ; N.div
        ~attrs:[ A.class_ "actions" ]
        [ Widgets.button
            ~primary:true
            ~disabled:(busy || not valid)
            ~on_click:submit
            "Sign and follow"
        ; Widgets.button ~disabled:busy ~on_click:(set_offer None) "Back to settings"
        ]
    ]
;;

let view
  ~(backend : Backend.t)
  ~leader_detail
  ~agent
  ~session
  ~form
  ~set_form
  ~offer
  ~set_offer
  ~status
  ~set_status
  ~include_builder_fee
  ~set_include_builder_fee
  =
  let open Effect.Let_syntax in
  let validated = Follow_form.validate form in
  let errors =
    match validated with
    | Ok _ -> []
    | Error errors -> errors
  in
  let busy =
    match (status : Status.t) with
    | Busy _ -> true
    | Idle | Failed _ -> false
  in
  let body (detail : Leader_detail.t) =
    let leader = detail.leader.address in
    match session with
    | None ->
      N.div
        [ Widgets.notice "Connect your wallet to follow a leader."
        ; N.div
            ~attrs:[ A.class_ "actions" ]
            [ Widgets.link
                ~attrs:[ A.classes [ "btn"; "primary" ] ]
                Login
                [ N.text "Connect wallet" ]
            ]
        ]
    | Some ((wallet : Wallet.t), (session : Auth.Session.t)) ->
      let valid = Result.is_ok validated in
      let follow ~offer =
        follow_effect
          ~backend
          ~wallet
          ~session
          ~leader
          ~validated
          ~offer
          ~include_builder_fee
          ~set_status
      in
      (match offer with
       | Some o ->
         approval_view
           ~offer:o
           ~include_builder_fee
           ~set_include_builder_fee
           ~submit:(follow ~offer:(Some o))
           ~set_offer
           ~busy
           ~valid
       | None ->
         let review =
           let%bind () = set_status (Status.Busy "Requesting an agent key...") in
           match%bind
             Effect.of_deferred_thunk (fun () -> backend.agent_new ~token:session.token)
           with
           | Ok o ->
             let%bind () = set_status Idle in
             set_offer (Some o)
           | Error e -> set_status (Failed e)
         in
         let button =
           match agent with
           | Remote.Loaded check when not (Agent_check.needs_approval check) ->
             Widgets.button
               ~primary:true
               ~disabled:(busy || not valid)
               ~on_click:(follow ~offer:None)
               "Follow"
           | Remote.Loaded _ ->
             Widgets.button
               ~primary:true
               ~disabled:(busy || not valid)
               ~on_click:review
               "Review agent approval"
           | Idle | Loading | Failed _ -> N.none
         in
         N.div
           [ form_view ~form ~set_form ~errors
           ; (match validated with
              | Ok (v : Follow_form.Valid.t) ->
                N.p
                  ~attrs:[ A.class_ "muted" ]
                  [ N.text
                      (sprintf
                         "Target size: %s. Execution: %s."
                         (Scale_mode.to_string_hum v.scale)
                         (Algo_choice.describe v.algo))
                  ]
              | Error _ -> N.none)
           ; (match agent with
              | Remote.Loaded check -> Widgets.notice (Agent_check.describe check)
              | other -> Widgets.remote other ~f:(fun _ -> N.none))
           ; N.div ~attrs:[ A.class_ "actions" ] [ button ]
           ])
  in
  N.div
    [ (match leader_detail with
       | Remote.Loaded (d : Leader_detail.t) ->
         Widgets.link (Leader d.leader.address) [ N.text "\u{2190} Back to leader" ]
       | _ -> Widgets.link Leaders [ N.text "\u{2190} All leaders" ])
    ; Widgets.section
        "Follow"
        [ Widgets.remote leader_detail ~f:(fun (d : Leader_detail.t) ->
            N.div [ Page_leader.summary d.leader; body d ])
        ; (match status with
           | Idle -> N.none
           | Busy text -> N.div ~attrs:[ A.class_ "loading" ] [ N.text text ]
           | Failed e -> Widgets.error_box e)
        ]
    ]
;;

let component ~(backend : Backend.t) ~route ~session (local_ graph) =
  let open Bonsai.Let_syntax in
  let key =
    let%map route in
    match (route : Route.t) with
    | Follow a -> Some a
    | _ -> None
  in
  let leader_detail = Remote.fetch ~equal:Address.equal ~load:backend.leader key graph in
  (* The agent's status decides whether following needs an approval first. *)
  let me_key =
    let%map key and session in
    match key, session with
    | Some leader, Some (_, (s : Auth.Session.t)) -> Some (leader, s.token)
    | _ -> None
  in
  let agent =
    let%map me =
      Remote.fetch
        ~equal:(Tuple2.equal ~eq1:Address.equal ~eq2:String.equal)
        ~load:(fun (_, token) -> backend.me ~token)
        me_key
        graph
    in
    match (me : Me.t Remote.t) with
    | Loaded me -> Remote.Loaded (Agent_check.of_status me.agent ~now:(Backend.now_ms ()))
    | Idle -> Idle
    | Loading -> Loading
    | Failed e -> Failed e
  in
  let form, set_form = Bonsai.state Follow_form.default graph in
  let offer, set_offer = Bonsai.state_opt graph in
  let status, set_status = Bonsai.state Status.Idle graph in
  let include_builder_fee, set_include_builder_fee = Bonsai.state true graph in
  (* An agent offer belongs to one visit of the page; start over for another leader. *)
  Bonsai.Edge.on_change
    ~equal:(Option.equal Address.equal)
    key
    ~callback:
      (let%map set_offer and set_status in
       fun _ -> Effect.Many [ set_offer None; set_status Status.Idle ])
    graph;
  let%map leader_detail
  and agent
  and session
  and form
  and set_form
  and offer
  and set_offer
  and status
  and set_status
  and include_builder_fee
  and set_include_builder_fee in
  view
    ~backend
    ~leader_detail
    ~agent
    ~session
    ~form
    ~set_form
    ~offer
    ~set_offer
    ~status
    ~set_status
    ~include_builder_fee
    ~set_include_builder_fee
;;
