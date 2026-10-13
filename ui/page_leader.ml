open! Core
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr

let max_fills = 25

let summary (l : Leader.t) =
  let b = l.breakdown in
  N.div
    [ N.div
        ~attrs:[ A.class_ "leader-head" ]
        [ N.h3 [ N.text (Option.value l.display_name ~default:(Address.short l.address)) ]
        ; N.span ~attrs:[ A.class_ "muted mono" ] [ N.text (Address.to_string l.address) ]
        ]
    ; Widgets.stats
        [ Widgets.stat ~label:"Rank" (N.textf "#%d" l.rank)
        ; Widgets.stat ~label:"Score" (N.textf "%.1f / 100" l.score)
        ; Widgets.stat ~label:"Equity" (N.text (Format.usd l.account_value))
        ; Widgets.stat ~label:"PnL" (Widgets.usd_pnl b.pnl)
        ; Widgets.stat ~label:"ROI" (Widgets.signed b.roi (Format.pct b.roi))
        ; Widgets.stat ~label:"Max drawdown" (N.text (Format.pct b.max_drawdown))
        ; Widgets.stat ~label:"Win rate" (N.text (Format.pct b.win_rate))
        ; Widgets.stat ~label:"Trades" (N.textf "%d" b.trade_count)
        ; Widgets.stat ~label:"Avg hold" (N.text (Format.duration ~secs:b.avg_hold_secs))
        ; Widgets.stat ~label:"Consistency" (N.text (Format.pct b.consistency))
        ; Widgets.stat ~label:"Followers" (N.textf "%d" l.followers)
        ]
    ]
;;

let window_pnl (w : Window_pnl.t) =
  Widgets.stats
    [ Widgets.stat ~label:"24h" (Widgets.usd_pnl w.day)
    ; Widgets.stat ~label:"7d" (Widgets.usd_pnl w.week)
    ; Widgets.stat ~label:"30d" (Widgets.usd_pnl w.month)
    ; Widgets.stat ~label:"All time" (Widgets.usd_pnl w.all_time)
    ]
;;

let fills_table (fills : Fill.t list) =
  match fills with
  | [] -> Widgets.notice "No fills."
  | _ ->
    Widgets.table
      ~header:
        (List.map
           [ "Time (UTC)"; "Coin"; "Direction"; "Price"; "Size"; "Closed PnL"; "Fee" ]
           ~f:N.text)
      ~numeric:[ 3; 4; 5; 6 ]
      (List.map (List.take fills max_fills) ~f:(fun f ->
         [ N.text (Format.time_ms f.time)
         ; N.text f.coin
         ; (match f.side with
            | Buy -> Widgets.signed 1. f.dir
            | Sell -> Widgets.signed (-1.) f.dir)
         ; N.text (Format.number ~decimals:2 f.px)
         ; N.text (Format.number f.sz)
         ; (if Float.(f.closed_pnl = 0.) then N.text "" else Widgets.usd_pnl f.closed_pnl)
         ; N.text (Format.usd f.fee)
         ]))
;;

let view (d : Leader_detail.t) =
  N.div
    [ Widgets.section
        "Leader"
        [ summary d.leader
        ; N.div
            ~attrs:[ A.class_ "actions" ]
            [ Widgets.link
                ~attrs:[ A.classes [ "btn"; "primary" ]; A.id "follow-button" ]
                (Follow d.leader.address)
                [ N.text "Follow this leader" ]
            ]
        ]
    ; Widgets.section
        "Equity"
        [ window_pnl d.leader.window_pnl; Equity_chart.view d.equity_curve ]
    ; Widgets.section "Open positions" [ Widgets.positions_table d.positions ]
    ; Widgets.section
        (sprintf "Recent fills (latest %d)" (Int.min max_fills (List.length d.fills)))
        [ fills_table d.fills ]
    ]
;;

let component ~(backend : Backend.t) ~route (local_ graph) =
  let open Bonsai.Let_syntax in
  let key =
    let%map route in
    match (route : Route.t) with
    | Leader a -> Some a
    | _ -> None
  in
  let detail = Remote.fetch ~equal:Address.equal ~load:backend.leader key graph in
  let%map detail in
  N.div
    [ Widgets.link Leaders [ N.text "\u{2190} All leaders" ]; Widgets.remote detail ~f:view ]
;;
