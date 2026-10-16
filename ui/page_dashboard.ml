open! Core
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr

let caps_text (c : Caps.t) =
  let cap label x fmt = if Float.(x = 0.) then None else Some (label ^ " " ^ fmt x) in
  List.filter_opt
    [ cap "leverage" c.max_leverage (sprintf "%gx")
    ; cap "per symbol" c.max_notional_per_symbol Format.usd
    ; cap "daily loss" c.max_daily_loss Format.usd
    ; cap "min order" c.min_order_notional Format.usd
    ; (match c.allowlist with
       | [] -> None
       | coins -> Some ("coins " ^ String.concat ~sep:", " coins))
    ]
  |> function
  | [] -> "no caps"
  | parts -> String.concat ~sep:"; " parts
;;

let state_badge (s : Follow_state.t) =
  N.span
    ~attrs:[ A.classes [ "badge"; Follow_state.to_string s ] ]
    [ N.text (Follow_state.to_string s) ]
;;

module Command = struct
  type t =
    | Pause
    | Resume
    | Stop
end

(* The engine's cost report for this follow: totals over the finished parent orders and
   the latest few, when the engine reports them. *)
let execution_view (e : Execution.t) =
  N.div
    ~attrs:[ A.class_ "execution" ]
    [ Widgets.stats
        [ Widgets.stat ~label:"Parents" (N.textf "%d (%d active)" e.parents e.active)
        ; Widgets.stat ~label:"Fill rate" (N.text (Format.pct e.fill_rate))
        ; Widgets.stat
            ~label:"Shortfall"
            (N.textf "%s bps" (Format.number ~decimals:1 e.shortfall_bps))
        ; Widgets.stat
            ~label:"Slippage"
            (N.textf "%s bps" (Format.number ~decimals:1 e.slippage_bps))
        ; Widgets.stat ~label:"Fees" (N.text (Format.usd e.fees))
        ]
    ; (match List.take e.recent 5 with
       | [] -> N.none
       | recent ->
         Widgets.table
           ~header:
             (List.map
                [ "Time (UTC)"; "Algo"; "Outcome"; "Side"; "Filled"; "Shortfall (bps)" ]
                ~f:N.text)
           ~numeric:[ 4; 5 ]
           (List.map recent ~f:(fun (r : Execution_report.t) ->
              [ N.text (Option.value_map r.time ~default:"-" ~f:Format.time_ms)
              ; N.text r.algo
              ; N.text r.outcome
              ; N.text
                  (match r.side with
                   | Buy -> "buy"
                   | Sell -> "sell")
              ; N.textf "%s / %s" (Format.number r.filled) (Format.number r.target)
              ; N.text (Format.number ~decimals:1 r.shortfall_bps)
              ])))
    ]
;;

let follow_card ~run (f : Follow.t) =
  let command c label = Widgets.button ~on_click:(run f.id c) label in
  let buttons =
    match f.state with
    | Running -> [ command Command.Pause "Pause"; command Stop "Stop" ]
    | Paused -> [ command Resume "Resume"; command Stop "Stop" ]
    | Stopped -> []
  in
  N.div
    ~attrs:[ A.class_ "follow"; A.id ("follow-" ^ f.id) ]
    [ N.div
        ~attrs:[ A.class_ "follow-head" ]
        [ Widgets.link (Leader f.leader) [ N.text (Address.short f.leader) ]
        ; state_badge f.state
        ; N.span
            ~attrs:[ A.class_ "muted" ]
            [ N.text ("since " ^ Format.time_ms f.created_at) ]
        ]
    ; Widgets.stats
        [ Widgets.stat ~label:"PnL" (Widgets.usd_pnl f.pnl)
        ; Widgets.stat ~label:"Scale" (N.text (Scale_mode.to_string_hum f.scale))
        ; Widgets.stat ~label:"Caps" (N.text (caps_text f.caps))
        ; Widgets.stat ~label:"Execution" (N.text (Algo_choice.describe f.algo))
        ]
    ; Option.value_map f.execution ~default:N.none ~f:execution_view
    ; Widgets.positions_table f.positions
    ; N.div ~attrs:[ A.class_ "actions" ] buttons
    ]
;;

let view ~(dashboard : Me.t) ~run =
  let running =
    List.count dashboard.follows ~f:(fun f -> Follow_state.equal f.state Running)
  in
  N.div
    [ Widgets.stats
        [ Widgets.stat ~label:"Account" (N.text (Address.short dashboard.address))
        ; Widgets.stat ~label:"Equity" (N.text (Format.usd dashboard.account_value))
        ; Widgets.stat ~label:"Copy PnL" (Widgets.usd_pnl dashboard.total_pnl)
        ; Widgets.stat
            ~label:"Follows"
            (N.textf "%d running of %d" running (List.length dashboard.follows))
        ]
    ; (let check = Agent_check.of_status dashboard.agent ~now:(Backend.now_ms ()) in
       match check with
       | Active -> N.none
       | Missing | Not_approved | Expired _ -> Widgets.notice (Agent_check.describe check))
    ; (match dashboard.follows with
       | [] ->
         N.div
           [ Widgets.notice "You are not following anyone yet."
           ; Widgets.link Leaders [ N.text "Browse leaders" ]
           ]
       | follows -> N.div (List.map follows ~f:(follow_card ~run)))
    ]
;;

module Key = struct
  type t =
    { token : string
    ; generation : int
    }
  [@@deriving equal]
end

let component ~(backend : Backend.t) ~route ~session (local_ graph) =
  let open Bonsai.Let_syntax in
  let generation, set_generation = Bonsai.state 0 graph in
  let command_error, set_command_error = Bonsai.state_opt graph in
  let key =
    let%map route and session and generation in
    match (route : Route.t), session with
    | Dashboard, Some (_, (s : Auth.Session.t)) ->
      Some { Key.token = s.token; generation }
    | _ -> None
  in
  let dashboard =
    Remote.fetch
      ~equal:Key.equal
      ~load:(fun (k : Key.t) -> backend.me ~token:k.token)
      key
      graph
  in
  let%map dashboard
  and session
  and generation
  and set_generation
  and command_error
  and set_command_error in
  let run id command =
    match session with
    | None -> Effect.Ignore
    | Some (_, (s : Auth.Session.t)) ->
      let open Effect.Let_syntax in
      (match%bind
         Effect.of_deferred_thunk (fun () ->
           match (command : Command.t) with
           | Pause ->
             backend.update_follow ~token:s.token ~id { state = Some Paused; algo = None }
           | Resume ->
             backend.update_follow
               ~token:s.token
               ~id
               { state = Some Running; algo = None }
           | Stop -> backend.stop_follow ~token:s.token ~id)
       with
       | Ok (_ : Follow.t) ->
         let%bind () = set_command_error None in
         set_generation (generation + 1)
       | Error e -> set_command_error (Some e))
  in
  Widgets.section
    "Dashboard"
    [ (match session with
       | None ->
         N.div
           [ Widgets.notice "Connect your wallet to see your follows."
           ; Widgets.link
               ~attrs:[ A.classes [ "btn"; "primary" ] ]
               Login
               [ N.text "Connect wallet" ]
           ]
       | Some _ -> Widgets.remote dashboard ~f:(fun dashboard -> view ~dashboard ~run))
    ; Option.value_map command_error ~default:N.none ~f:Widgets.error_box
    ]
;;
