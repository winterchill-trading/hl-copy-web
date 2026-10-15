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

let score_section (s : Scoring.Detail.t) =
  let pct_label =
    Option.value_map s.percentile ~default:"-" ~f:(fun p -> sprintf "top %.0f%%" (100. *. (1. -. p)))
  in
  N.div
    ~attrs:[ A.id "leader-score" ]
    ([ Widgets.stats
         [ Widgets.stat ~label:"Composite score" (N.textf "%.1f / 100" s.score)
         ; Widgets.stat
             ~label:"Rank"
             (N.text (Option.value_map s.rank ~default:"unranked" ~f:(sprintf "#%d")))
         ; Widgets.stat ~label:"Percentile" (N.text pct_label)
         ; Widgets.stat
             ~label:"Forecast (30d Sharpe)"
             (match s.predicted_forward_sharpe with
              | None -> N.text "-"
              | Some p -> Widgets.signed p (sprintf "%+.2f" p))
         ]
     ]
     @ (match s.reasons with
        | [] -> []
        | reasons -> [ Widgets.notice ("Not ranked: " ^ String.concat ~sep:"; " reasons) ])
     @ [ Widgets.table
           ~attrs:[ A.id "score-components" ]
           ~header:(List.map [ "Component"; "Value"; "Percentile"; "Weight"; "Points" ] ~f:N.text)
           ~numeric:[ 1; 2; 3; 4 ]
           (List.map s.components ~f:(fun c ->
              let metric =
                List.find s.metrics ~f:(fun m -> String.equal m.name c.metric)
                |> Option.value
                     ~default:
                       { Scoring.Metric.name = c.metric
                       ; label = c.label
                       ; value = c.value
                       ; unit = "number"
                       ; better = ""
                       }
              in
              [ N.text c.label
              ; N.text (Scoring_view.format_metric { metric with value = c.value })
              ; N.text (Format.pct c.percentile)
              ; N.text (Format.pct c.weight)
              ; N.text (Format.number ~decimals:1 c.contribution)
              ]))
       ])
;;

let metrics_table (s : Scoring.Detail.t) =
  Widgets.table
    ~attrs:[ A.id "leader-metrics" ]
    ~header:(List.map [ "Metric"; "Value"; "" ] ~f:N.text)
    ~numeric:[ 1 ]
    (List.map s.metrics ~f:(fun m ->
       [ N.text m.label
       ; N.text (Scoring_view.format_metric m)
       ; N.span ~attrs:[ A.class_ "metric-hint" ] [ N.text (Scoring_view.direction_hint m) ]
       ]))
;;

let capacity_section (s : Scoring.Detail.t) =
  match s.capacity with
  | None -> Widgets.notice "No order books were collected for this leader's coins."
  | Some c ->
    N.div
      ~attrs:[ A.id "leader-capacity" ]
      ([ N.p
           [ N.text
               (match c.capacity_usd with
                | Some cap ->
                  sprintf
                    "A follower up to about %s copies these orders at %s bps or less on                      average (book depth now, fees not included)."
                    (Scoring_view.compact_usd cap)
                    (Format.number ~decimals:1 c.max_cost_bps)
                | None -> "No order of this leader could be costed.")
           ]
       ; Capacity_chart.view c
       ; Widgets.table
           ~header:
             (List.map
                [ "Follower equity"; "Mean cost"; "Median"; "p90"; "Unfilled" ]
                ~f:N.text)
           ~numeric:[ 0; 1; 2; 3; 4 ]
           (List.map c.curve ~f:(fun p ->
              [ N.text (Format.usd p.follower_equity)
              ; N.textf "%s bps" (Format.number ~decimals:2 p.mean_cost_bps)
              ; N.textf "%s bps" (Format.number ~decimals:2 p.median_cost_bps)
              ; N.textf "%s bps" (Format.number ~decimals:2 p.p90_cost_bps)
              ; N.text (Format.pct p.unfilled_share)
              ]))
       ]
       @
       match c.coins_without_book with
       | [] -> []
       | coins -> [ Widgets.notice ("No book for " ^ String.concat ~sep:", " coins) ])
;;

let alerts_section (s : Scoring.Detail.t) =
  match s.alerts with
  | [] -> Widgets.notice "No behaviour changes detected."
  | alerts ->
    N.ul
      ~attrs:[ A.class_ "alerts"; A.id "leader-alerts" ]
      (List.rev alerts
       |> List.map ~f:(fun (a : Scoring.Alert.t) ->
         N.li
           [ N.span ~attrs:[ A.class_ (Scoring_view.severity_class a.severity) ] [ N.text a.severity ]
           ; N.strong [ N.text (Scoring_view.kind_label a.kind) ]
           ; N.span ~attrs:[ A.class_ "muted" ] [ N.text (Format.time_ms a.time) ]
           ; N.span [ N.text a.message ]
           ]))
;;

let scoring_sections (d : Leader_detail.t) =
  match d.scoring with
  | None -> []
  | Some s ->
    [ Widgets.section "Leader score" [ score_section s ]
    ; Widgets.section "Metrics" [ metrics_table s ]
    ; Widgets.section "Capacity" [ capacity_section s ]
    ; Widgets.section "Alerts" [ alerts_section s ]
    ]
;;

let view (d : Leader_detail.t) =
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
        [ window_pnl d.leader.window_pnl
        ; Equity_chart.view
            (* leader-scoring's series is the one its metrics use *)
            (match d.scoring with
             | Some s when List.length s.equity_curve >= 2 -> s.equity_curve
             | _ -> d.equity_curve)
        ]
    ]
    @ scoring_sections d
    @ [ Widgets.section "Open positions" [ Widgets.positions_table d.positions ]
      ; Widgets.section
          (sprintf "Recent fills (latest %d)" (Int.min max_fills (List.length d.fills)))
          [ fills_table d.fills ]
      ]
    |> N.div
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
    [ Widgets.link Leaders [ N.text "\u{2190} All leaders" ]
    ; Widgets.remote detail ~f:view
    ]
;;
