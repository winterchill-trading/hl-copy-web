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
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Leaders_response = struct
  type t =
    { as_of : Time_ms.t
    ; leaders : Leader.t list
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

  module Login_request = struct
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

module Follow_request = struct
  type t =
    { leader : Address.t
    ; scale : Scale_mode.t
    ; caps : Caps.t
    ; approve_agent : Approve_agent.t
    ; agent_signature : string
    ; approve_builder_fee : Approve_builder_fee.t option
         [@default None] [@yojson_drop_if Option.is_none]
    ; builder_fee_signature : string option
         [@default None] [@yojson_drop_if Option.is_none]
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
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Dashboard = struct
  type t =
    { address : Address.t
    ; account_value : float
    ; total_pnl : float
    ; follows : Follow.t list
    }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Follow_command = struct
  type t =
    | Pause
    | Resume
    | Stop
  [@@deriving compare, enumerate, equal, sexp]

  let to_string = function
    | Pause -> "pause"
    | Resume -> "resume"
    | Stop -> "stop"
  ;;

  let of_string s = List.find all ~f:(fun t -> String.equal (to_string t) s)
end

module Api_error = struct
  type t = { error : string }
  [@@deriving compare, equal, sexp, yojson] [@@yojson.allow_extra_fields]
end

module Endpoint = struct
  let leaders = "/leaders"
  let leader address = "/leaders/" ^ Address.to_string address
  let auth_challenge = "/auth/challenge"
  let auth_login = "/auth/login"
  let agent = "/agent"
  let follows = "/follows"

  let follow_command ~id command =
    sprintf "/follows/%s/%s" id (Follow_command.to_string command)
  ;;
end
