(** One leader: score breakdown, equity curve, open positions and recent fills, with a
    button to follow. *)

open! Core
open! Bonsai_web

(** Loads while the route is [Leader address]. *)
val component
  :  backend:Backend.t
  -> route:Copy_web_model.Route.t Bonsai.t
  -> local_ Bonsai.graph
  -> Vdom.Node.t Bonsai.t

(** Name, address and headline numbers; the follow page reuses it. *)
val summary : Api_types.Leader.t -> Vdom.Node.t
