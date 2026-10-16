open! Core
open Api_types
open Copy_web_model

let show form =
  print_s
    [%sexp
      (Follow_form.validate form
       : (Follow_form.Valid.t, (Follow_form.Field.t * string) list) Result.t)]
;;

let%expect_test "defaults validate to Caps.default" =
  print_s [%sexp (Follow_form.default : Follow_form.t)];
  (match Follow_form.validate Follow_form.default with
   | Ok { scale = Equity_ratio; caps; algo = None } ->
     assert (Caps.equal caps Caps.default)
   | _ -> assert false);
  [%expect
    {|
    ((scale_kind Equity_ratio) (scale_value 1) (max_leverage 3)
     (max_notional_per_symbol 5000) (max_daily_loss 500) (allowlist "")
     (min_order_notional 10) (algo Immediate) (algo_seconds "") (algo_slices ""))
    |}]
;;

let%expect_test "multiplier, allowlist and errors" =
  show
    { Follow_form.default with
      scale_kind = Multiplier
    ; scale_value = " 0.25 "
    ; allowlist = "btc, eth  sol,BTC"
    };
  show
    { Follow_form.default with
      scale_kind = Fixed_notional
    ; scale_value = "0"
    ; max_leverage = "x"
    ; max_daily_loss = "-1"
    ; allowlist = "BTC, $$$"
    };
  [%expect
    {|
    (Ok
     ((scale (Multiplier 0.25))
      (caps
       ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
        (allowlist (BTC ETH SOL)) (min_order_notional 10)))
      (algo ())))
    (Error
     ((Scale_value "must be between 1 and 1,000,000")
      (Max_leverage "must be a number")
      (Max_daily_loss "must be between 0 and 1,000,000,000")
      (Allowlist "not a coin: $$$")))
    |}]
;;

let%expect_test "execution algorithms: wire form, defaults and bounds" =
  List.iter Algo_choice.Kind.all ~f:(fun kind ->
    show (Follow_form.with_algo Follow_form.default kind));
  show
    { (Follow_form.with_algo Follow_form.default Twap) with
      algo_seconds = "0"
    ; algo_slices = "x"
    };
  List.iter
    [ None; Some "twap:300s:10"; Some "adaptive:20s"; Some "passive:30s"; Some "pov" ]
    ~f:(fun a -> print_endline (Algo_choice.describe a));
  [%expect
    {|
    (Ok
     ((scale Equity_ratio)
      (caps
       ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
        (allowlist ()) (min_order_notional 10)))
      (algo ())))
    (Ok
     ((scale Equity_ratio)
      (caps
       ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
        (allowlist ()) (min_order_notional 10)))
      (algo (twap:60s:6))))
    (Ok
     ((scale Equity_ratio)
      (caps
       ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
        (allowlist ()) (min_order_notional 10)))
      (algo (adaptive:20s))))
    (Ok
     ((scale Equity_ratio)
      (caps
       ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
        (allowlist ()) (min_order_notional 10)))
      (algo (passive:30s))))
    (Error
     ((Algo_seconds "must be between 1 and 3,600")
      (Algo_slices "must be a number")))
    Immediate
    TWAP 300 s in 10 slices
    Adaptive, 20 s timeout
    Passive, 30 s timeout
    pov
    |}]
;;
