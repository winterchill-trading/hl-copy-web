open! Core
open! Async_kernel
open Api_types

type kind =
  | Injected of Ethereum.t
  | Demo

type t =
  { address : Address.t
  ; kind : kind
  }

let connect provider =
  match%map Ethereum.request_accounts provider with
  | Error _ as e -> e
  | Ok [] -> Or_error.error_string "the wallet returned no accounts"
  | Ok (account :: _) ->
    (match Address.of_string_opt account with
     | Some address -> Ok { address; kind = Injected provider }
     | None -> Or_error.error_s [%message "the wallet returned a malformed address" account])
;;

let demo =
  { address = Address.of_string "0x000000000000000000000000000000000000dead"; kind = Demo }
;;

let is_demo t =
  match t.kind with
  | Demo -> true
  | Injected _ -> false
;;

let demo_signature = "0x" ^ String.make 130 '0'

let personal_sign t ~message =
  match t.kind with
  | Demo -> return (Ok demo_signature)
  | Injected provider ->
    Ethereum.personal_sign provider ~address:(Address.to_string t.address) ~message
;;

let sign_typed_data t typed_data =
  match t.kind with
  | Demo -> return (Ok demo_signature)
  | Injected provider ->
    Ethereum.sign_typed_data_v4
      provider
      ~address:(Address.to_string t.address)
      ~typed_data:(Yojson.Safe.to_string typed_data)
;;

let chain_id t =
  match t.kind with
  | Demo -> return (Ok None)
  | Injected provider -> Deferred.Or_error.map (Ethereum.chain_id provider) ~f:Option.some
;;
