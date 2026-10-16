(** The execution algorithms the follow form offers, and their wire form: the short
    strings execution-algos' [Algo.of_string] reads (["twap:60s:6"], ["adaptive:20s"],
    ["passive:30s"]), sent as [Follow_request.algo]. [Immediate] is the default and is
    sent as no algorithm at all, so a default follow's request is the same as before. *)

open! Core

module Kind : sig
  type t =
    | Immediate (** one IOC order per leader change *)
    | Twap (** equal slices over a duration *)
    | Adaptive (** passive while small and on time, then takes liquidity *)
    | Passive (** post-only at the touch, the rest as IOC after a timeout *)
  [@@deriving compare, enumerate, equal, sexp]

  val label : t -> string

  (** One sentence for the form. *)
  val help : t -> string

  (** Stable identifier for [<select>] values. *)
  val to_string : t -> string

  val of_string : string -> t option

  (** What the seconds field means for this kind: TWAP's duration, a timeout otherwise;
      [None] for [Immediate]. *)
  val seconds_label : t -> string option

  (** TWAP 60 s, adaptive 20 s, passive 30 s (execution-algos' defaults). *)
  val default_seconds : t -> int
end

(** 6, execution-algos' TWAP default. *)
val default_slices : int

(** [None] for [Immediate]. [seconds] in 1 to 3600, [slices] in 1 to 100 (TWAP only). *)
val to_wire : Kind.t -> seconds:int -> slices:int -> string option

(** Reads the forms {!to_wire} writes (and ["immediate"]); [None] for anything else. *)
val of_wire : string -> (Kind.t * int * int) option

(** For a follow card: ["Immediate"] for [None], ["TWAP 60 s in 6 slices"],
    ["Adaptive, 20 s timeout"], ..., or the raw string when it is another form. *)
val describe : string option -> string
