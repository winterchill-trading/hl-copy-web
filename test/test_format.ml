open! Core
open Copy_web_model

let%expect_test "usd" =
  List.iter [ 0.; 1234.5; -12.3; 125_000.; -0.001; 1_234_567.89; 999.999 ] ~f:(fun x ->
    printf "%s %s\n" (Format.usd x) (Format.signed_usd x));
  [%expect
    {|
    $0.00 $0.00
    $1,234.50 +$1,234.50
    -$12.30 -$12.30
    $125,000 +$125,000
    $0.00 $0.00
    $1,234,568 +$1,234,568
    $1,000.00 +$1,000.00
    |}]
;;

let%expect_test "pct, number, duration" =
  print_endline (Format.pct 0.4215);
  print_endline (Format.pct (-0.05));
  List.iter [ 0.25; 1250.; -0.5; 0.000012345; 3. ] ~f:(fun x ->
    print_endline (Format.number x));
  List.iter [ 45.; 720.; 11_100.; 187_200.; -5. ] ~f:(fun secs ->
    print_endline (Format.duration ~secs));
  [%expect
    {|
    42.1%
    -5.0%
    0.25
    1,250
    -0.5
    0
    3
    45s
    12m
    3h 05m
    2d 4h
    0s
    |}]
;;

let%expect_test "timestamps are UTC" =
  List.iter [ 0.; 1_760_257_800_000.; 1_709_251_199_999. ] ~f:(fun ms ->
    print_endline (Format.time_ms ms));
  [%expect {|
    1970-01-01 00:00
    2025-10-12 08:30
    2024-02-29 23:59
    |}]
;;
