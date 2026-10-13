(** Geometry for the equity-curve chart, in SVG user units (y grows downwards). The view
    turns this into a [<polyline>] plus axis labels. *)

open! Core
open Api_types

module Tick : sig
  type t =
    { at : float (** x or y coordinate *)
    ; label : string
    }
  [@@deriving equal, sexp_of]
end

type t =
  { width : float
  ; height : float
  ; plot_left : float
  ; plot_right : float
  ; plot_top : float
  ; plot_bottom : float
  ; line : (float * float) list (** one vertex per equity point, oldest first *)
  ; y_ticks : Tick.t list (** round USD values covering the range *)
  ; x_ticks : Tick.t list (** first, middle and last dates *)
  ; start_y : float (** y of the first point's equity, for a reference line *)
  ; ending_above_start : bool
  }
[@@deriving sexp_of]

(** [None] for fewer than two points. A flat curve gets a band of 1% around its value. *)
val equity_curve : Equity_point.t list -> width:float -> height:float -> t option

(** The smallest of 1, 2 or 5 times a power of ten that is at least [x]; the y axis uses
    [nice_step (range / 5)], which gives three to six labels. *)
val nice_step : float -> float
