(** Display logic for the leader-scoring parts of the leader page: metric values in their
    units, alert badges and the geometry of the capacity chart (follower size on a log
    axis against the estimated cost in basis points). *)

open! Core
open Api_types

(** A metric's value in its unit: ["12.3%"] for ratios, ["1.52"] for numbers, ["42"] for
    counts, ["3.5 d"], ["7h 30m"], ["0.67 / day"], ["2.1x"]; ["-"] when undefined. *)
val format_metric : Scoring.Metric.t -> string

(** ["higher is better"], ["lower is better"] or [""]. *)
val direction_hint : Scoring.Metric.t -> string

(** CSS class of an alert severity: ["badge critical"], ["badge warning"], ["badge info"]. *)
val severity_class : string -> string

(** ["Drawdown breach"] from ["drawdown_breach"]. *)
val kind_label : string -> string

(** ["$1.2M"], ["$250k"], ["$900"]: follower sizes on the capacity axis. *)
val compact_usd : float -> string

module Capacity_chart : sig
  type t =
    { width : float
    ; height : float
    ; plot_left : float
    ; plot_right : float
    ; plot_top : float
    ; plot_bottom : float
    ; line : (float * float) list (** mean cost per follower size, smallest first *)
    ; x_ticks : Chart.Tick.t list (** one per follower size *)
    ; y_ticks : Chart.Tick.t list (** basis points *)
    ; threshold_y : float option (** the capacity cost line, when inside the plot *)
    ; capacity_x : float option (** where the capacity falls on the size axis *)
    }
  [@@deriving sexp_of]

  (** [None] with fewer than two points. *)
  val of_capacity : Scoring.Capacity.t -> width:float -> height:float -> t option
end
