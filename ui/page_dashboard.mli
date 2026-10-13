(** The signed-in user's follows: state, scale, caps, attributed pnl and positions, with
    pause, resume and stop. *)

open! Core
open! Bonsai_web
open Api_types

(** Loads each time the route becomes [Dashboard] while signed in. *)
val component
  :  backend:Backend.t
  -> route:Copy_web_model.Route.t Bonsai.t
  -> session:(Wallet.t * Auth.Session.t) option Bonsai.t
  -> local_ Bonsai.graph
  -> Vdom.Node.t Bonsai.t
