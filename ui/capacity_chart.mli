(** The capacity curve as SVG: mean estimated cost (basis points) of copying the leader's
    orders against follower size on a log axis, the capacity threshold as a dashed line
    and the capacity itself as a vertical mark. *)

open! Core
open! Bonsai_web

val view : ?width:float -> ?height:float -> Api_types.Scoring.Capacity.t -> Vdom.Node.t
