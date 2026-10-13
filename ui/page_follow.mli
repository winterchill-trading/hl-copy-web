(** Following a leader: the scale mode, caps and coin allowlist, then the Hyperliquid
    [approveAgent] typed data (and the optional [approveBuilderFee]) shown in full before
    the wallet signs it, then the follow request. *)

open! Core
open! Bonsai_web
open Api_types

(** Loads while the route is [Follow address]. *)
val component
  :  backend:Backend.t
  -> route:Copy_web_model.Route.t Bonsai.t
  -> session:(Wallet.t * Auth.Session.t) option Bonsai.t
  -> local_ Bonsai.graph
  -> Vdom.Node.t Bonsai.t
