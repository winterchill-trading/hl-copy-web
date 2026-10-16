open! Core
open Api_types
open Copy_web_model

let metric unit value : Scoring.Metric.t =
  { name = "m"; label = "M"; value; unit; better = "higher" }
;;

let%expect_test "metric values in their units" =
  List.iter
    [ "ratio", Some 0.1234
    ; "number", Some 1.5234
    ; "count", Some 42.
    ; "days", Some 3.46
    ; "hours", Some 7.5
    ; "per_day", Some 0.6667
    ; "multiple", Some 2.125
    ; "ratio", None
    ]
    ~f:(fun (unit, value) ->
      printf "%-8s %s\n" unit (Scoring_view.format_metric (metric unit value)));
  [%expect
    {|
    ratio    12.3%
    number   1.52
    count    42
    days     3.5 d
    hours    7h 30m
    per_day  0.67 / day
    multiple 2.12x
    ratio    -
    |}]
;;

let%expect_test "labels and sizes" =
  List.iter [ "drawdown_breach"; "leverage_spike"; "liquidation" ] ~f:(fun k ->
    printf "%s / %s\n" (Scoring_view.kind_label k) (Scoring_view.severity_class "warning"));
  List.iter [ 900.; 1_000.; 250_000.; 1_200_000.; 3e9 ] ~f:(fun x ->
    printf "%s\n" (Scoring_view.compact_usd x));
  [%expect
    {|
    Drawdown breach / badge warning
    Leverage spike / badge warning
    Liquidation / badge warning
    $900
    $1k
    $250k
    $1.2M
    $3B
    |}]
;;

let%expect_test "capacity chart geometry" =
  let point follower_equity mean_cost_bps : Scoring.Capacity_point.t =
    { follower_equity
    ; orders = 10
    ; mean_cost_bps
    ; median_cost_bps = mean_cost_bps
    ; p90_cost_bps = mean_cost_bps
    ; unfilled_share = 0.
    }
  in
  let capacity : Scoring.Capacity.t =
    { max_cost_bps = 10.
    ; capacity_usd = Some 100_000.
    ; curve = [ point 1e3 1.; point 1e4 2.; point 1e5 10.; point 1e6 40. ]
    ; coins_without_book = []
    }
  in
  let c =
    Option.value_exn
      (Scoring_view.Capacity_chart.of_capacity capacity ~width:400. ~height:200.)
  in
  print_s
    [%message
      ""
        ~line:
          (* rounded: the x axis goes through log10, whose last bits differ between
             platform maths libraries *)
          (List.map c.line ~f:(fun (x, y) ->
             ( Float.round_decimal x ~decimal_digits:2
             , Float.round_decimal y ~decimal_digits:2 ))
           : (float * float) list)
        ~x_ticks:(List.map c.x_ticks ~f:(fun t -> t.label) : string list)
        ~y_ticks:(List.map c.y_ticks ~f:(fun t -> t.label) : string list)
        ~threshold_y:
          (Option.map c.threshold_y ~f:(Float.round_decimal ~decimal_digits:2)
           : float option)
        ~capacity_x:
          (Option.map c.capacity_x ~f:(Float.round_decimal ~decimal_digits:2)
           : float option)];
  [%expect
    {|
    ((line ((60 171.85) (168 167.7) (276 134.5) (384 10)))
     (x_ticks ($1k $10k $100k $1M))
     (y_ticks ("0 bps" "10 bps" "20 bps" "30 bps" "40 bps"))
     (threshold_y (134.5)) (capacity_x (276)))
    |}]
;;

let%expect_test "every mock leader detail carries scoring that formats" =
  let dir = "../dev/leaders" in
  Sys_unix.readdir dir
  |> Array.to_list
  |> List.sort ~compare:String.compare
  |> List.iter ~f:(fun file ->
    let d = Leader_detail.t_of_yojson (Yojson.Safe.from_file (dir ^/ file)) in
    let s = Option.value_exn d.scoring in
    printf
      "%s score=%.1f metrics=%d capacity=%b alerts=%d\n"
      (String.prefix file 8)
      s.score
      (List.length s.metrics)
      (Option.is_some
         (Option.bind
            s.capacity
            ~f:(Scoring_view.Capacity_chart.of_capacity ~width:400. ~height:200.)))
      (List.length s.alerts));
  [%expect
    {|
    0x288a5b score=64.3 metrics=14 capacity=true alerts=2
    0x3b0472 score=41.4 metrics=14 capacity=true alerts=1
    0x4d57c7 score=69.3 metrics=14 capacity=true alerts=0
    0x620a6c score=75.7 metrics=14 capacity=true alerts=0
    0x6efd2d score=70.0 metrics=14 capacity=true alerts=0
    0xe72583 score=7.1 metrics=14 capacity=true alerts=2
    0xe7e797 score=20.7 metrics=14 capacity=true alerts=0
    0xfb0349 score=51.4 metrics=14 capacity=true alerts=0
    |}]
;;

let universe : Scoring.Universe.t =
  { persistent = false
  ; fading = false
  ; formation = "sharpe"
  ; window_days = Some 30.
  ; periods = 10
  ; rank_correlation = Some 0.051
  ; rank_correlation_lower = Some (-0.025)
  ; rank_correlation_upper = Some 0.12
  ; top_stays_top_half = Some 0.49
  ; decay = [ Some 0.05; Some 0.04; None ]
  ; transition = []
  ; top_k = Some 10
  ; top_k_return = Some 0.337
  ; random_mean = Some 0.338
  ; baseline_percentile = Some 0.48
  ; baseline_p_value = Some 0.52
  ; leaders_with_stats = 282
  ; trials = Some 282
  ; pbo = Some 0.14
  ; spa_p_value = Some 0.2
  ; accepted = 2
  ; flagged = 3
  ; excluded = 1
  }
;;

let%expect_test "persistence verdicts and the statistical gate" =
  print_endline (Scoring_view.persistence_verdict universe);
  print_endline
    (Scoring_view.persistence_verdict
       { universe with persistent = true; rank_correlation_lower = Some 0.03 });
  print_endline
    (Scoring_view.persistence_verdict
       { universe with rank_correlation = None; top_k = None });
  print_s
    [%message
      ""
        ~meaningful:
          (List.map
             [ None; Some universe; Some { universe with persistent = true } ]
             ~f:Scoring_view.ranking_is_meaningful
           : bool list)];
  let stats : Scoring.Stats.t =
    { periods = 120
    ; periods_per_year = 365.25
    ; sharpe_annualized = Some 1.9
    ; psr = Some 0.991
    ; dsr = Some 0.12
    ; min_track_record_periods = Some 73.
    ; pbo = Some 0.14
    ; spa_p_value = Some 0.2
    ; accepted = Some false
    ; reasons = [ "deflated Sharpe ratio 0.12 below 0.95" ]
    }
  in
  print_endline (Scoring_view.stats_verdict stats);
  print_endline (Scoring_view.stats_verdict { stats with accepted = Some true; reasons = [] });
  print_endline (Scoring_view.probability stats.psr);
  List.iter
    [ "wash_trade"; "co_trading"; "off_book_price"; "something_new" ]
    ~f:(fun k -> print_endline (Scoring_view.integrity_label k));
  [%expect {|
    Rank correlation from one window to the next (30-day windows): 0.05 (95% interval -0.03 to 0.12) over 10 periods. The top 10 returned 33.7% in the next window against 33.8% for random picks (better than 48% of random draws). The ranking does not persist: treat the order as noise, not as a list of the best leaders.
    Rank correlation from one window to the next (30-day windows): 0.05 (95% interval 0.03 to 0.12) over 10 periods. The top 10 returned 33.7% in the next window against 33.8% for random picks (better than 48% of random draws). The ranking persists: past leaders tend to stay ahead.
    Not enough history to test the ranking (30-day windows). The ranking does not persist: treat the order as noise, not as a list of the best leaders.
    (meaningful (false false true))
    Fails the statistical gate: deflated Sharpe ratio 0.12 below 0.95.
    Passes the statistical gate (PSR and DSR at least 0.95, PBO at most 0.5).
    0.99
    Wash trades
    Trades in step with other accounts
    Fills away from the market
    Something new
    |}]
;;
