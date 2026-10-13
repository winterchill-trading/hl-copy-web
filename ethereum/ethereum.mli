(** The browser wallet, over the EIP-1193 provider that extensions inject as
    [window.ethereum]. Every call returns an error rather than raising; a user rejecting a
    prompt is an error with code 4001 in its message. *)

open! Core
open! Async_kernel

type t

(** [None] when no wallet extension is installed. *)
val detect : unit -> t option

(** [eth_requestAccounts]: prompts the user to connect, returns the selected accounts. *)
val request_accounts : t -> string list Or_error.t Deferred.t

(** [eth_chainId], e.g. ["0x66eee"]. *)
val chain_id : t -> string Or_error.t Deferred.t

(** [personal_sign] (EIP-191) of a UTF-8 message; the message is sent hex-encoded. *)
val personal_sign : t -> address:string -> message:string -> string Or_error.t Deferred.t

(** [eth_signTypedData_v4] of EIP-712 typed data given as a JSON string. *)
val sign_typed_data_v4
  :  t
  -> address:string
  -> typed_data:string
  -> string Or_error.t Deferred.t

(** [0x] followed by the bytes of the string in lowercase hex. *)
val hex_of_utf8 : string -> string

(** Waits for a JS promise. A rejection becomes an error carrying the rejection's [code]
    and [message] fields when it has them. *)
val of_promise : Ojs.t -> Ojs.t Or_error.t Deferred.t
