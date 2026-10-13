open! Core
open Api_types
open Copy_web_model

let%expect_test "nice steps" =
  List.iter [ 0.; 0.37; 3.; 7.4; 12_345.; 99_999. ] ~f:(fun x ->
    printf "%g -> %g\n" x (Chart.nice_step x));
  [%expect
    {|
    0 -> 1
    0.37 -> 0.5
    3 -> 5
    7.4 -> 10
    12345 -> 20000
    99999 -> 100000
    |}]
;;

let point time equity = { Equity_point.time; equity }
let day = 86_400_000.

let%expect_test "a small curve" =
  let chart =
    Chart.equity_curve
      ~width:400.
      ~height:200.
      [ point 0. 1000.; point day 1300.; point (2. *. day) 900.; point (4. *. day) 1450. ]
  in
  print_s [%sexp (chart : Chart.t option)];
  [%expect {|
    (((width 400) (height 200) (plot_left 72) (plot_right 388) (plot_top 10)
      (plot_bottom 176) (line ((72 134.5) (151 72.25) (230 155.25) (388 41.125)))
      (y_ticks
       (((at 10) (label $1,600.00)) ((at 51.5) (label $1,400.00))
        ((at 93) (label $1,200.00)) ((at 134.5) (label $1,000.00))
        ((at 176) (label $800.00))))
      (x_ticks
       (((at 72) (label 1970-01-01)) ((at 230) (label 1970-01-03))
        ((at 388) (label 1970-01-05))))
      (start_y 134.5) (ending_above_start true)))
    |}]
;;

let%expect_test "degenerate curves" =
  print_s [%sexp (Chart.equity_curve ~width:100. ~height:50. [ point 0. 5. ] : Chart.t option)];
  let flat =
    Chart.equity_curve ~width:100. ~height:50. [ point 0. 500.; point day 500. ]
    |> Option.value_exn
  in
  print_s [%sexp (flat.y_ticks : Chart.Tick.t list), (flat.line : (float * float) list)];
  [%expect {|
    ()
    ((((at 10) (label $506.00)) ((at 12.666666666666666) (label $504.00))
      ((at 15.333333333333334) (label $502.00)) ((at 18) (label $500.00))
      ((at 20.666666666666668) (label $498.00))
      ((at 23.333333333333332) (label $496.00)) ((at 26) (label $494.00)))
     ((72 18) (88 18)))
    |}]
;;

let%expect_test "every fixture curve stays inside the plot" =
  List.iter (Fixtures.leaders ()) ~f:(fun (l : Leader.t) ->
    let d = Fixtures.detail l.address in
    let c = Chart.equity_curve d.equity_curve ~width:720. ~height:260. |> Option.value_exn in
    List.iter c.line ~f:(fun (x, y) ->
      assert (Float.(x >= c.plot_left && x <= c.plot_right));
      assert (Float.(y >= c.plot_top && y <= c.plot_bottom)));
    printf
      "%s %s\n"
      (Address.short l.address)
      (List.map c.y_ticks ~f:(fun t -> t.label) |> String.concat ~sep:" "));
  [%expect {|
    0x620a...97ac $800,000 $700,000 $600,000 $500,000 $400,000
    0x288a...be1b $1,600,000 $1,400,000 $1,200,000 $1,000,000 $800,000 $600,000
    0x6efd...12b9 $700,000 $680,000 $660,000 $640,000 $620,000 $600,000
    0xfb03...ec6c $200,000 $190,000 $180,000 $170,000 $160,000
    0x4d57...e478 $190,000 $180,000 $170,000 $160,000 $150,000 $140,000
    0x3b04...8fbf $450,000 $400,000 $350,000 $300,000 $250,000
    0xe7e7...1f41 $500,000 $450,000 $400,000 $350,000
    0xe725...9a91 $800,000 $750,000 $700,000 $650,000 $600,000 $550,000 $500,000
    |}]
;;
