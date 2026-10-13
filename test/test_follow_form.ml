open! Core
open Api_types
open Copy_web_model

let show form =
  print_s
    [%sexp
      (Follow_form.validate form
       : (Scale_mode.t * Caps.t, (Follow_form.Field.t * string) list) Result.t)]
;;

let%expect_test "defaults validate to Caps.default" =
  print_s [%sexp (Follow_form.default : Follow_form.t)];
  (match Follow_form.validate Follow_form.default with
   | Ok (Equity_ratio, caps) -> assert (Caps.equal caps Caps.default)
   | _ -> assert false);
  [%expect
    {|
    ((scale_kind Equity_ratio) (scale_value 1) (max_leverage 3)
     (max_notional_per_symbol 5000) (max_daily_loss 500) (allowlist "")
     (min_order_notional 10))
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
     ((Multiplier 0.25)
      ((max_leverage 3) (max_notional_per_symbol 5000) (max_daily_loss 500)
       (allowlist (BTC ETH SOL)) (min_order_notional 10))))
    (Error
     ((Scale_value "must be between 1 and 1,000,000")
      (Max_leverage "must be a number")
      (Max_daily_loss "must be between 0 and 1,000,000,000")
      (Allowlist "not a coin: $$$")))
    |}]
;;
