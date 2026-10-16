open! Core
open Ppx_yojson_conv_lib.Yojson_conv.Primitives

let json_error what json =
  Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error ("Api_types: expected " ^ what) json
;;

module Address = struct
  type t = string [@@deriving compare, equal, hash, sexp_of]

  let is_hex_digit = function
    | '0' .. '9' | 'a' .. 'f' -> true
    | _ -> false
  ;;

  let of_string_opt s =
    let s = String.lowercase s in
    if String.length s = 42
       && String.is_prefix s ~prefix:"0x"
       && String.for_alli s ~f:(fun i c -> i < 2 || is_hex_digit c)
    then Some s
    else None
  ;;

  let of_string s =
    match of_string_opt s with
    | Some t -> t
    | None -> raise_s [%message "Api_types.Address.of_string: malformed address" s]
  ;;

  let to_string t = t
  let t_of_sexp sexp = of_string (String.t_of_sexp sexp)
  let yojson_of_t t = `String t

  let t_of_yojson = function
    | `String s as json ->
      (match of_string_opt s with
       | Some t -> t
       | None -> json_error "a 0x-prefixed 40 digit hex address" json)
    | json -> json_error "an address string" json
  ;;

  let short t = String.prefix t 6 ^ "..." ^ String.suffix t 4
end

module Time_ms = struct
  type t = float [@@deriving compare, equal, sexp]

  (* Integral milliseconds print without a fraction, so the JSON stays an integer for
     servers and for EIP-712 [uint64] fields. *)
  let yojson_of_t t =
    if Float.is_integer t then `Intlit (Printf.sprintf "%.0f" t) else `Float t
  ;;

  let t_of_yojson = function
    | `Int i -> Float.of_int i
    | `Intlit s -> Float.of_string s
    | `Float f -> f
    | json -> json_error "a millisecond timestamp" json
  ;;
end

module Side = struct
  type t =
    | Buy
    | Sell
  [@@deriving compare, enumerate, equal, sexp]

  let yojson_of_t = function
    | Buy -> `String "buy"
    | Sell -> `String "sell"
  ;;

  let t_of_yojson = function
    | `String "buy" -> Buy
    | `String "sell" -> Sell
    | json -> json_error "\"buy\" or \"sell\"" json
  ;;
end

module Score_breakdown = struct
  type t =
    { pnl : float
    ; roi : float
    ; max_drawdown : float
    ; win_rate : float
    ; trade_count : int
    ; avg_hold_secs : float
    ; consistency : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Window_pnl = struct
  type t =
    { day : float
    ; week : float
    ; month : float
    ; all_time : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Equity_point = struct
  type t =
    { time : Time_ms.t
    ; equity : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Scoring = struct
  module Metric = struct
    type t =
      { name : string
      ; label : string
      ; value : float option [@default None]
      ; unit : string
      ; better : string
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Component = struct
    type t =
      { metric : string
      ; label : string
      ; value : float option [@default None]
      ; percentile : float
      ; weight : float
      ; contribution : float
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Capacity_point = struct
    type t =
      { follower_equity : float
      ; orders : int
      ; mean_cost_bps : float
      ; median_cost_bps : float
      ; p90_cost_bps : float
      ; unfilled_share : float
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Capacity = struct
    type t =
      { max_cost_bps : float
      ; capacity_usd : float option [@default None]
      ; curve : Capacity_point.t list
      ; coins_without_book : string list [@default []]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Alert = struct
    type t =
      { kind : string
      ; severity : string
      ; time : Time_ms.t
      ; message : string
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Summary = struct
    type t =
      { score : float
      ; rank : int option [@default None]
      ; percentile : float option [@default None]
      ; eligible : bool
      ; predicted_forward_sharpe : float option [@default None]
      ; capacity_usd : float option [@default None]
      ; alerts : int
      ; worst_alert : string option [@default None]
      ; sharpe : float option [@default None]
      ; max_drawdown : float option [@default None]
      ; leverage_p95 : float option [@default None]
      ; integrity_flags : string list
           [@yojson.default []] [@yojson_drop_if List.is_empty] [@sexp.list]
      ; excluded : bool [@yojson.default false] [@yojson_drop_if not] [@sexp.bool]
      ; persistence_percentile : float option
           [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
      ; psr : float option
           [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
      ; dsr : float option
           [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Integrity_flag = struct
    type t =
      { kind : string
      ; severity : string
      ; message : string
      ; accounts : string list
           [@yojson.default []] [@yojson_drop_if List.is_empty] [@sexp.list]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Persistence_point = struct
    type t =
      { time : Time_ms.t
      ; percentile : float
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Persistence = struct
    type t =
      { windows : int
      ; mean_percentile : float option [@default None]
      ; top_quantile_windows : int
      ; percentiles : Persistence_point.t list [@default []]
      ; universe_persistent : bool
      ; universe_rank_correlation : float option [@default None]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Stats = struct
    type t =
      { periods : int
      ; periods_per_year : float
      ; sharpe_annualized : float option [@default None]
      ; psr : float option [@default None]
      ; dsr : float option [@default None]
      ; min_track_record_periods : float option [@default None]
      ; pbo : float option [@default None]
      ; spa_p_value : float option [@default None]
      ; accepted : bool option [@default None]
      ; reasons : string list [@default []]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Universe = struct
    type t =
      { persistent : bool
      ; fading : bool
      ; formation : string
      ; window_days : float option [@default None]
      ; periods : int
      ; rank_correlation : float option [@default None]
      ; rank_correlation_lower : float option [@default None]
      ; rank_correlation_upper : float option [@default None]
      ; top_stays_top_half : float option [@default None]
      ; decay : float option list [@default []]
      ; transition : float list list [@default []]
      ; top_k : int option [@default None]
      ; top_k_return : float option [@default None]
      ; random_mean : float option [@default None]
      ; baseline_percentile : float option [@default None]
      ; baseline_p_value : float option [@default None]
      ; leaders_with_stats : int
      ; trials : int option [@default None]
      ; pbo : float option [@default None]
      ; spa_p_value : float option [@default None]
      ; accepted : int
      ; flagged : int
      ; excluded : int
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Detail = struct
    type t =
      { score : float
      ; rank : int option [@default None]
      ; percentile : float option [@default None]
      ; eligible : bool
      ; reasons : string list [@default []]
      ; components : Component.t list
      ; predicted_forward_sharpe : float option [@default None]
      ; metrics : Metric.t list
      ; equity_source : string
      ; bar_seconds : float
      ; equity_curve : Equity_point.t list
      ; capacity : Capacity.t option [@default None]
      ; alerts : Alert.t list [@default []]
      ; persistence : Persistence.t option
           [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
      ; stats : Stats.t option
           [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
      ; integrity : Integrity_flag.t list
           [@yojson.default []] [@yojson_drop_if List.is_empty] [@sexp.list]
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end
end

module Leader = struct
  type t =
    { address : Address.t
    ; display_name : string option [@default None] [@yojson_drop_if Option.is_none]
    ; rank : int
    ; score : float
    ; breakdown : Score_breakdown.t
    ; account_value : float
    ; window_pnl : Window_pnl.t
    ; followers : int
    ; scoring : Scoring.Summary.t option [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Leaders_response = struct
  type t =
    { as_of : Time_ms.t
    ; leaders : Leader.t list
    ; universe : Scoring.Universe.t option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Fill = struct
  type t =
    { time : Time_ms.t
    ; coin : string
    ; side : Side.t
    ; px : float
    ; sz : float
    ; closed_pnl : float
    ; fee : float
    ; dir : string
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Position = struct
  type t =
    { coin : string
    ; size : float
    ; entry_px : float
    ; unrealized_pnl : float
    ; leverage : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Leader_detail = struct
  type t =
    { leader : Leader.t
    ; equity_curve : Equity_point.t list
    ; fills : Fill.t list
    ; positions : Position.t list
    ; scoring : Scoring.Detail.t option [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Scale_mode = struct
  type t =
    | Equity_ratio
    | Multiplier of float
    | Fixed_notional of float
  [@@deriving compare, equal, sexp]

  let yojson_of_t = function
    | Equity_ratio -> `Assoc [ "kind", `String "equity_ratio" ]
    | Multiplier x -> `Assoc [ "kind", `String "multiplier"; "value", yojson_of_float x ]
    | Fixed_notional x ->
      `Assoc [ "kind", `String "fixed_notional"; "value", yojson_of_float x ]
  ;;

  let t_of_yojson json =
    match json with
    | `Assoc fields ->
      let value () =
        match List.Assoc.find fields ~equal:String.equal "value" with
        | Some v -> float_of_yojson v
        | None -> json_error "a \"value\" field" json
      in
      (match List.Assoc.find fields ~equal:String.equal "kind" with
       | Some (`String "equity_ratio") -> Equity_ratio
       | Some (`String "multiplier") -> Multiplier (value ())
       | Some (`String "fixed_notional") -> Fixed_notional (value ())
       | _ -> json_error "kind equity_ratio, multiplier or fixed_notional" json)
    | _ -> json_error "a scale mode object" json
  ;;

  let to_string_hum = function
    | Equity_ratio -> "equity ratio"
    | Multiplier x -> sprintf "%gx leader size" x
    | Fixed_notional x -> sprintf "%g USD per position" x
  ;;
end

module Caps = struct
  type t =
    { max_leverage : float
    ; max_notional_per_symbol : float
    ; max_daily_loss : float
    ; allowlist : string list
    ; min_order_notional : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]

  let default =
    { max_leverage = 3.
    ; max_notional_per_symbol = 5000.
    ; max_daily_loss = 500.
    ; allowlist = []
    ; min_order_notional = 10.
    }
  ;;
end

module Auth = struct
  module Challenge_request = struct
    type t = { address : Address.t }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Challenge = struct
    type t =
      { message : string
      ; nonce : string
      ; expires_at : Time_ms.t
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Verify_request = struct
    type t =
      { address : Address.t
      ; nonce : string
      ; signature : string
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end

  module Session = struct
    type t =
      { token : string
      ; address : Address.t
      ; expires_at : Time_ms.t
      }
    [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
  end
end

module Hyperliquid_chain = struct
  type t =
    | Mainnet
    | Testnet
  [@@deriving compare, equal, sexp]

  let to_string = function
    | Mainnet -> "Mainnet"
    | Testnet -> "Testnet"
  ;;

  let yojson_of_t t = `String (to_string t)

  let t_of_yojson = function
    | `String "Mainnet" -> Mainnet
    | `String "Testnet" -> Testnet
    | json -> json_error "\"Mainnet\" or \"Testnet\"" json
  ;;
end

(* EIP-712 envelope shared by Hyperliquid's user-signed actions; the field order of
   [fields] is part of the signed type hash. *)
let user_signed_typed_data ~primary_type ~signature_chain_id ~fields ~message =
  let field (name, type_) = `Assoc [ "name", `String name; "type", `String type_ ] in
  `Assoc
    [ ( "domain"
      , `Assoc
          [ "name", `String "HyperliquidSignTransaction"
          ; "version", `String "1"
          ; "chainId", `Int (Int.of_string signature_chain_id)
          ; "verifyingContract", `String "0x0000000000000000000000000000000000000000"
          ] )
    ; ( "types"
      , `Assoc
          [ ( "EIP712Domain"
            , `List
                (List.map
                   ~f:field
                   [ "name", "string"
                   ; "version", "string"
                   ; "chainId", "uint256"
                   ; "verifyingContract", "address"
                   ]) )
          ; primary_type, `List (List.map ~f:field fields)
          ] )
    ; "primaryType", `String primary_type
    ; "message", `Assoc message
    ]
;;

module Approve_agent = struct
  type t =
    { hyperliquid_chain : Hyperliquid_chain.t
    ; signature_chain_id : string
    ; agent_address : Address.t
    ; agent_name : string
    ; nonce : Time_ms.t
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]

  let typed_data t =
    user_signed_typed_data
      ~primary_type:"HyperliquidTransaction:ApproveAgent"
      ~signature_chain_id:t.signature_chain_id
      ~fields:
        [ "hyperliquidChain", "string"
        ; "agentAddress", "address"
        ; "agentName", "string"
        ; "nonce", "uint64"
        ]
      ~message:
        [ "hyperliquidChain", Hyperliquid_chain.yojson_of_t t.hyperliquid_chain
        ; "agentAddress", Address.yojson_of_t t.agent_address
        ; "agentName", `String t.agent_name
        ; "nonce", Time_ms.yojson_of_t t.nonce
        ]
  ;;
end

module Approve_builder_fee = struct
  type t =
    { hyperliquid_chain : Hyperliquid_chain.t
    ; signature_chain_id : string
    ; max_fee_rate : string
    ; builder : Address.t
    ; nonce : Time_ms.t
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]

  let typed_data t =
    user_signed_typed_data
      ~primary_type:"HyperliquidTransaction:ApproveBuilderFee"
      ~signature_chain_id:t.signature_chain_id
      ~fields:
        [ "hyperliquidChain", "string"
        ; "maxFeeRate", "string"
        ; "builder", "address"
        ; "nonce", "uint64"
        ]
      ~message:
        [ "hyperliquidChain", Hyperliquid_chain.yojson_of_t t.hyperliquid_chain
        ; "maxFeeRate", `String t.max_fee_rate
        ; "builder", Address.yojson_of_t t.builder
        ; "nonce", Time_ms.yojson_of_t t.nonce
        ]
  ;;
end

module Agent_offer = struct
  type t =
    { approve_agent : Approve_agent.t
    ; approve_builder_fee : Approve_builder_fee.t option
         [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Agent_approval = struct
  type t =
    { approve_agent : Approve_agent.t
    ; signature : string
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Builder_fee_approval = struct
  type t =
    { approve_builder_fee : Approve_builder_fee.t
    ; signature : string
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Agent_status = struct
  type t =
    { agent_address : Address.t
    ; agent_name : string
    ; approved : bool
    ; valid_until : Time_ms.t option [@default None] [@yojson_drop_if Option.is_none]
    ; builder_fee : string option [@default None] [@yojson_drop_if Option.is_none]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Follow_request = struct
  type t =
    { leader : Address.t
    ; scale : Scale_mode.t
    ; caps : Caps.t
    ; algo : string option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Follow_state = struct
  type t =
    | Running
    | Paused
    | Stopped
  [@@deriving compare, enumerate, equal, sexp]

  let to_string = function
    | Running -> "running"
    | Paused -> "paused"
    | Stopped -> "stopped"
  ;;

  let yojson_of_t t = `String (to_string t)

  let t_of_yojson json =
    match json with
    | `String s ->
      (match List.find all ~f:(fun t -> String.equal (to_string t) s) with
       | Some t -> t
       | None -> json_error "running, paused or stopped" json)
    | _ -> json_error "a follow state string" json
  ;;
end

module Execution_report = struct
  type t =
    { time : Time_ms.t option [@default None]
    ; algo : string
    ; outcome : string
    ; side : Side.t
    ; target : float
    ; filled : float
    ; avg_px : float
    ; arrival_px : float
    ; children : int
    ; fees : float
    ; arrival_slippage_bps : float
    ; shortfall_bps : float
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Execution = struct
  type t =
    { algo : string
    ; parents : int
    ; filled_parents : int
    ; fill_rate : float
    ; shortfall_bps : float
    ; slippage_bps : float
    ; fees : float
    ; active : int
    ; recent : Execution_report.t list [@default []]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Follow = struct
  type t =
    { id : string
    ; leader : Address.t
    ; scale : Scale_mode.t
    ; caps : Caps.t
    ; state : Follow_state.t
    ; created_at : Time_ms.t
    ; pnl : float
    ; positions : Position.t list
    ; algo : string option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    ; execution : Execution.t option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Follow_update = struct
  type t =
    { state : Follow_state.t option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    ; algo : string option
         [@yojson.default None] [@yojson_drop_if Option.is_none] [@sexp.option]
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Me = struct
  type t =
    { address : Address.t
    ; account_value : float
    ; total_pnl : float
    ; agent : Agent_status.t option [@default None] [@yojson_drop_if Option.is_none]
    ; follows : Follow.t list
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Ws_push = struct
  type t =
    | Me of Me.t
    | Follow of Follow.t
    | Fill of Fill.t
    | Error of string
  [@@deriving compare, equal, sexp]

  let yojson_of_t = function
    | Me me -> `Assoc [ "type", `String "me"; "me", Me.yojson_of_t me ]
    | Follow f -> `Assoc [ "type", `String "follow"; "follow", Follow.yojson_of_t f ]
    | Fill f -> `Assoc [ "type", `String "fill"; "fill", Fill.yojson_of_t f ]
    | Error e -> `Assoc [ "type", `String "error"; "error", `String e ]
  ;;

  let t_of_yojson json =
    let field name =
      match json with
      | `Assoc fields ->
        (match List.Assoc.find fields ~equal:String.equal name with
         | Some v -> v
         | None ->
           Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
             ("Ws_push: missing field " ^ name)
             json)
      | _ -> Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error "Ws_push: not an object" json
    in
    match field "type" with
    | `String "me" -> Me (Me.t_of_yojson (field "me"))
    | `String "follow" -> Follow (Follow.t_of_yojson (field "follow"))
    | `String "fill" -> Fill (Fill.t_of_yojson (field "fill"))
    | `String "error" ->
      (match field "error" with
       | `String e -> Error e
       | other ->
         Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error
           "Ws_push: error is not a string"
           other)
    | other ->
      Ppx_yojson_conv_lib.Yojson_conv.of_yojson_error "Ws_push: unknown type" other
  ;;

  let to_string t = Yojson.Safe.to_string (yojson_of_t t)
  let of_string s = t_of_yojson (Yojson.Safe.from_string s)
end

module Api_error = struct
  type t = { error : string }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Endpoint = struct
  let leaders = "/leaders"
  let leader address = "/leaders/" ^ Address.to_string address
  let auth_challenge = "/auth/challenge"
  let auth_verify = "/auth/verify"
  let agent_new = "/agent/new"
  let agent_approved = "/agent/approved"
  let builder_fee = "/builder-fee"
  let follows = "/follows"
  let follow ~id = "/follows/" ^ id
  let me = "/me"
end
