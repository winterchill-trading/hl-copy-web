open! Core
open Api_types
open Copy_web_model
open Leader_table

let show leaders =
  List.iter leaders ~f:(fun (l : Leader.t) ->
    printf
      "%d %-14s score=%5.1f roi=%7s dd=%6s trades=%d\n"
      l.rank
      (Option.value l.display_name ~default:(Address.short l.address))
      l.score
      (Format.pct l.breakdown.roi)
      (Format.pct l.breakdown.max_drawdown)
      l.breakdown.trade_count)
;;

let%expect_test "default sort is rank order" =
  show (apply (Fixtures.leaders ()) ~sort:Sort.default ~filter:Filter.empty);
  [%expect
    {|
    1 meanrev        score= 69.2 roi=  52.2% dd= 13.8% trades=684
    2 trend-desk     score= 60.8 roi=  59.0% dd= 25.2% trades=782
    3 scalper-07     score= 58.5 roi=   7.9% dd=  6.8% trades=28
    4 0xfb03...ec6c  score= 56.3 roi=  13.9% dd= 10.9% trades=226
    5 0x4d57...e478  score= 51.5 roi=  21.0% dd=  8.6% trades=273
    6 slow-carry     score= 39.6 roi=  -4.0% dd= 27.7% trades=450
    7 0xe7e7...1f41  score= 33.9 roi=  -5.7% dd= 21.6% trades=543
    8 basis-hunter   score= 25.7 roi= -24.2% dd= 30.0% trades=165
    |}]
;;

let%expect_test "clicking a column sorts best first, clicking again flips" =
  let roi = Sort.click Sort.default Roi in
  print_s [%sexp (roi : Sort.t)];
  show (apply (Fixtures.leaders ()) ~sort:roi ~filter:Filter.empty |> Fn.flip List.take 3);
  let dd = Sort.click roi Max_drawdown in
  print_s [%sexp (dd : Sort.t), (Sort.click dd Max_drawdown : Sort.t)];
  show (apply (Fixtures.leaders ()) ~sort:dd ~filter:Filter.empty |> Fn.flip List.take 3);
  [%expect
    {|
    ((column Roi) (direction Descending))
    2 trend-desk     score= 60.8 roi=  59.0% dd= 25.2% trades=782
    1 meanrev        score= 69.2 roi=  52.2% dd= 13.8% trades=684
    5 0x4d57...e478  score= 51.5 roi=  21.0% dd=  8.6% trades=273
    (((column Max_drawdown) (direction Ascending))
     ((column Max_drawdown) (direction Descending)))
    3 scalper-07     score= 58.5 roi=   7.9% dd=  6.8% trades=28
    5 0x4d57...e478  score= 51.5 roi=  21.0% dd=  8.6% trades=273
    4 0xfb03...ec6c  score= 56.3 roi=  13.9% dd= 10.9% trades=226
    |}]
;;

let%expect_test "filters combine" =
  let filter = { Filter.empty with max_drawdown = Some 0.2; min_trades = Some 200 } in
  show (apply (Fixtures.leaders ()) ~sort:Sort.default ~filter);
  print_endline "--";
  show
    (apply
       (Fixtures.leaders ())
       ~sort:Sort.default
       ~filter:{ Filter.empty with query = " MEAN" });
  show
    (apply
       (Fixtures.leaders ())
       ~sort:Sort.default
       ~filter:{ Filter.empty with query = "0xe7" });
  print_endline "--";
  show
    (apply
       (Fixtures.leaders ())
       ~sort:Sort.default
       ~filter:{ Filter.empty with min_score = Some 60. });
  [%expect
    {|
    1 meanrev        score= 69.2 roi=  52.2% dd= 13.8% trades=684
    4 0xfb03...ec6c  score= 56.3 roi=  13.9% dd= 10.9% trades=226
    5 0x4d57...e478  score= 51.5 roi=  21.0% dd=  8.6% trades=273
    --
    1 meanrev        score= 69.2 roi=  52.2% dd= 13.8% trades=684
    7 0xe7e7...1f41  score= 33.9 roi=  -5.7% dd= 21.6% trades=543
    8 basis-hunter   score= 25.7 roi= -24.2% dd= 30.0% trades=165
    --
    1 meanrev        score= 69.2 roi=  52.2% dd= 13.8% trades=684
    2 trend-desk     score= 60.8 roi=  59.0% dd= 25.2% trades=782
    |}]
;;
