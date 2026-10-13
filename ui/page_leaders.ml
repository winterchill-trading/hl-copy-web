open! Core
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr
module Column = Leader_table.Column

let header_cell ~(sort : Leader_table.Sort.t) ~set_sort column =
  let arrow =
    if Column.equal sort.column column
    then (
      match sort.direction with
      | Ascending -> " \u{25B2}"
      | Descending -> " \u{25BC}")
    else ""
  in
  N.span
    ~attrs:
      [ A.class_ "sortable"
      ; A.on_click (fun _ -> set_sort (Leader_table.Sort.click sort column))
      ]
    [ N.text (Column.label column ^ arrow) ]
;;

let score_bar score =
  N.div
    ~attrs:[ A.class_ "score" ]
    [ N.div
        ~attrs:
          [ A.class_ "score-fill"
          ; A.style (Css_gen.width (`Percent (Percent.of_mult (score /. 100.))))
          ]
        []
    ; N.span [ N.textf "%.1f" score ]
    ]
;;

let cells (l : Leader.t) : Column.t -> N.t = function
  | Rank -> N.textf "%d" l.rank
  | Score -> score_bar l.score
  | Pnl -> Widgets.usd_pnl l.breakdown.pnl
  | Roi -> Widgets.signed l.breakdown.roi (Format.pct l.breakdown.roi)
  | Max_drawdown -> N.text (Format.pct l.breakdown.max_drawdown)
  | Win_rate -> N.text (Format.pct l.breakdown.win_rate)
  | Trades -> N.textf "%d" l.breakdown.trade_count
  | Avg_hold -> N.text (Format.duration ~secs:l.breakdown.avg_hold_secs)
  | Consistency -> N.text (Format.pct l.breakdown.consistency)
  | Account_value -> N.text (Format.usd l.account_value)
;;

let trader_cell (l : Leader.t) =
  Widgets.link
    (Leader l.address)
    [ N.div [ N.text (Option.value l.display_name ~default:(Address.short l.address)) ]
    ; N.div ~attrs:[ A.class_ "muted mono" ] [ N.text (Address.short l.address) ]
    ]
;;

let parse_float s = Float.of_string_opt (String.strip s)
let parse_pct s = Option.map (parse_float s) ~f:(fun x -> x /. 100.)
let parse_int s = Int.of_string_opt (String.strip s)

let filter_input ~label ~placeholder ~on_input =
  N.label
    ~attrs:[ A.class_ "field" ]
    [ N.span [ N.text label ]
    ; N.input
        ~attrs:
          [ A.type_ "text"
          ; A.placeholder placeholder
          ; A.on_input (fun _ value -> on_input value)
          ]
        ()
    ]
;;

let filters ~(filter : Leader_table.Filter.t) ~set_filter =
  N.div
    ~attrs:[ A.class_ "filters" ]
    [ filter_input ~label:"Search" ~placeholder:"name or 0x address" ~on_input:(fun v ->
        set_filter { filter with query = v })
    ; filter_input ~label:"Min score" ~placeholder:"0-100" ~on_input:(fun v ->
        set_filter { filter with min_score = parse_float v })
    ; filter_input ~label:"Max drawdown %" ~placeholder:"e.g. 25" ~on_input:(fun v ->
        set_filter { filter with max_drawdown = parse_pct v })
    ; filter_input ~label:"Min trades" ~placeholder:"e.g. 50" ~on_input:(fun v ->
        set_filter { filter with min_trades = parse_int v })
    ]
;;

let view (response : Leaders_response.t) ~sort ~set_sort ~filter ~set_filter =
  let rows = Leader_table.apply response.leaders ~sort ~filter in
  (* Rank first, then the trader, then the score components. *)
  let columns = List.filter Column.all ~f:(Fn.non (Column.equal Rank)) in
  let header =
    header_cell ~sort ~set_sort Rank
    :: N.text "Trader"
    :: List.map columns ~f:(header_cell ~sort ~set_sort)
  in
  let body =
    List.map rows ~f:(fun l ->
      cells l Rank :: trader_cell l :: List.map columns ~f:(cells l))
  in
  N.div
    [ filters ~filter ~set_filter
    ; N.p
        ~attrs:[ A.class_ "muted" ]
        [ N.textf
            "%d of %d leaders, ranked at %s UTC. Click a column to sort."
            (List.length rows)
            (List.length response.leaders)
            (Format.time_ms response.as_of)
        ]
    ; (match rows with
       | [] -> Widgets.notice "No leader matches these filters."
       | _ ->
         Widgets.table
           ~attrs:[ A.id "leaders-table" ]
           ~header
           ~numeric:(List.init 10 ~f:(fun i -> i + 2))
           body)
    ]
;;

let component ~(backend : Backend.t) ~active (local_ graph) =
  let open Bonsai.Let_syntax in
  let sort, set_sort = Bonsai.state Leader_table.Sort.default graph in
  let filter, set_filter = Bonsai.state Leader_table.Filter.empty graph in
  let key =
    let%map active in
    Option.some_if active ()
  in
  let leaders = Remote.fetch ~equal:Unit.equal ~load:backend.leaders key graph in
  let%map leaders and sort and set_sort and filter and set_filter in
  Widgets.section
    "Leaders"
    [ Widgets.remote leaders ~f:(view ~sort ~set_sort ~filter ~set_filter) ]
;;
