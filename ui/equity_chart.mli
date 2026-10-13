(** The equity curve as an inline SVG drawn with virtual_dom: a polyline over a grid of
    round USD values, a dashed line at the starting equity, and three date labels. *)

open! Core
open! Bonsai_web

val view : ?width:float -> ?height:float -> Api_types.Equity_point.t list -> Vdom.Node.t
