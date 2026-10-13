(** The signer behind the session: the injected browser wallet, or a demo signer that the
    mock backend accepts (it produces an all-zero signature and never prompts). *)

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

(** Prompts the wallet to connect and takes its first account. *)
val connect : Ethereum.t -> t Or_error.t Deferred.t

val demo : t
val is_demo : t -> bool
val personal_sign : t -> message:string -> string Or_error.t Deferred.t
val sign_typed_data : t -> Yojson.Safe.t -> string Or_error.t Deferred.t

(** The wallet's current chain as hex; [None] for the demo signer. Hyperliquid's
    user-signed actions carry the chain id they were signed under, and wallets refuse to
    sign typed data for another chain. *)
val chain_id : t -> string option Or_error.t Deferred.t
