(** Wallet login: connect the wallet ([eth_requestAccounts]), sign the server's challenge
    with [personal_sign], exchange the signature for a session. With mock data a demo
    signer is offered too, so the flow works without a wallet extension. *)

open! Core
open! Bonsai_web
open Api_types

val component
  :  backend:Backend.t
  -> login:(Wallet.t -> Auth.Session.t -> unit Effect.t) Bonsai.t
  -> session:(Wallet.t * Auth.Session.t) option Bonsai.t
  -> local_ Bonsai.graph
  -> Vdom.Node.t Bonsai.t
