open! Core
open Api_types

let address = Address.of_string "0xABCDEF0123456789abcdef0123456789ABCDEF01"
let agent = Address.of_string "0x1111111111111111111111111111111111111111"
let print_json json = print_endline (Yojson.Safe.pretty_to_string json)

module type Json = sig
  type t [@@deriving equal, sexp_of]

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t
end

let round_trip (type a) (module M : Json with type t = a) (x : a) =
  let s = Yojson.Safe.to_string (M.yojson_of_t x) in
  let back = M.t_of_yojson (Yojson.Safe.from_string s) in
  print_endline s;
  if not (M.equal x back) then print_s [%message "round trip changed" (back : M.t)]
;;

let%expect_test "addresses are validated and lowercased" =
  print_endline (Address.to_string address);
  print_endline (Address.short address);
  print_s [%sexp (Address.of_string_opt "0x12" : Address.t option)];
  print_s [%sexp (Address.of_string_opt ("0x" ^ String.make 40 'g') : Address.t option)];
  [%expect
    {|
    0xabcdef0123456789abcdef0123456789abcdef01
    0xabcd...ef01
    ()
    ()
    |}]
;;

let%expect_test "timestamps encode as JSON integers and accept floats" =
  round_trip (module Time_ms) 1_760_000_000_123.;
  print_s
    [%sexp (Time_ms.t_of_yojson (Yojson.Safe.from_string "1760000000123.0") : Time_ms.t)];
  [%expect {|
    1760000000123
    1760000000123
    |}]
;;

let%expect_test "scale modes" =
  List.iter
    Scale_mode.[ Equity_ratio; Multiplier 0.5; Fixed_notional 1000. ]
    ~f:(fun mode ->
      round_trip (module Scale_mode) mode;
      print_endline (Scale_mode.to_string_hum mode));
  [%expect
    {|
    {"kind":"equity_ratio"}
    equity ratio
    {"kind":"multiplier","value":0.5}
    0.5x leader size
    {"kind":"fixed_notional","value":1000.0}
    1000 USD per position
    |}]
;;

let%expect_test "optional fields accept null and are dropped when absent" =
  let leader =
    { Leader.address
    ; display_name = None
    ; rank = 1
    ; score = 87.5
    ; breakdown =
        { pnl = 125_000.
        ; roi = 0.42
        ; max_drawdown = 0.12
        ; win_rate = 0.61
        ; trade_count = 340
        ; avg_hold_secs = 5400.
        ; consistency = 0.75
        }
    ; account_value = 410_000.
    ; window_pnl = { day = 1200.; week = 8000.; month = 31_000.; all_time = 125_000. }
    ; followers = 3
    }
  in
  round_trip (module Leader) leader;
  let with_null =
    match Leader.yojson_of_t leader with
    | `Assoc fields -> `Assoc (("display_name", `Null) :: ("unknown", `Int 1) :: fields)
    | json -> json
  in
  print_s [%sexp (Leader.t_of_yojson with_null |> Leader.equal leader : bool)];
  [%expect
    {|
    {"address":"0xabcdef0123456789abcdef0123456789abcdef01","rank":1,"score":87.5,"breakdown":{"pnl":125000.0,"roi":0.42,"max_drawdown":0.12,"win_rate":0.61,"trade_count":340,"avg_hold_secs":5400.0,"consistency":0.75},"account_value":410000.0,"window_pnl":{"day":1200.0,"week":8000.0,"month":31000.0,"all_time":125000.0},"followers":3}
    true
    |}]
;;

let%expect_test "approveAgent typed data" =
  let action =
    { Approve_agent.hyperliquid_chain = Testnet
    ; signature_chain_id = "0x66eee"
    ; agent_address = agent
    ; agent_name = "copy"
    ; nonce = 1_760_000_000_123.
    }
  in
  round_trip (module Approve_agent) action;
  print_json (Approve_agent.typed_data action);
  [%expect
    {|
    {"hyperliquid_chain":"Testnet","signature_chain_id":"0x66eee","agent_address":"0x1111111111111111111111111111111111111111","agent_name":"copy","nonce":1760000000123}
    {
      "domain": {
        "name": "HyperliquidSignTransaction",
        "version": "1",
        "chainId": 421614,
        "verifyingContract": "0x0000000000000000000000000000000000000000"
      },
      "types": {
        "EIP712Domain": [
          { "name": "name", "type": "string" },
          { "name": "version", "type": "string" },
          { "name": "chainId", "type": "uint256" },
          { "name": "verifyingContract", "type": "address" }
        ],
        "HyperliquidTransaction:ApproveAgent": [
          { "name": "hyperliquidChain", "type": "string" },
          { "name": "agentAddress", "type": "address" },
          { "name": "agentName", "type": "string" },
          { "name": "nonce", "type": "uint64" }
        ]
      },
      "primaryType": "HyperliquidTransaction:ApproveAgent",
      "message": {
        "hyperliquidChain": "Testnet",
        "agentAddress": "0x1111111111111111111111111111111111111111",
        "agentName": "copy",
        "nonce": 1760000000123
      }
    }
    |}]
;;

let%expect_test "approveBuilderFee typed data message" =
  let action =
    { Approve_builder_fee.hyperliquid_chain = Testnet
    ; signature_chain_id = "0x66eee"
    ; max_fee_rate = "0.01%"
    ; builder = agent
    ; nonce = 1_760_000_000_124.
    }
  in
  (match Approve_builder_fee.typed_data action with
   | `Assoc fields ->
     print_json (List.Assoc.find_exn fields ~equal:String.equal "message");
     print_json (List.Assoc.find_exn fields ~equal:String.equal "primaryType")
   | _ -> assert false);
  [%expect
    {|
    {
      "hyperliquidChain": "Testnet",
      "maxFeeRate": "0.01%",
      "builder": "0x1111111111111111111111111111111111111111",
      "nonce": 1760000000124
    }
    "HyperliquidTransaction:ApproveBuilderFee"
    |}]
;;

let%expect_test "follow states, commands and endpoints" =
  List.iter Follow_state.all ~f:(fun s -> round_trip (module Follow_state) s);
  List.iter Follow_command.all ~f:(fun c ->
    print_endline (Endpoint.follow_command ~id:"f-1" c);
    assert (
      Option.equal
        Follow_command.equal
        (Follow_command.of_string (Follow_command.to_string c))
        (Some c)));
  print_endline (Endpoint.leader address);
  [%expect
    {|
    "running"
    "paused"
    "stopped"
    /follows/f-1/pause
    /follows/f-1/resume
    /follows/f-1/stop
    /leaders/0xabcdef0123456789abcdef0123456789abcdef01
    |}]
;;
