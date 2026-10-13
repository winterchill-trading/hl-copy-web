(** The follow form: raw input strings, and validation into a scale mode and caps. *)

open! Core
open Api_types

module Scale_kind : sig
  type t =
    | Equity_ratio
    | Multiplier
    | Fixed_notional
  [@@deriving compare, enumerate, equal, sexp]

  val label : t -> string

  (** Stable identifier for [<select>] values. *)
  val to_string : t -> string

  val of_string : string -> t option
end

module Field : sig
  type t =
    | Scale_value
    | Max_leverage
    | Max_notional_per_symbol
    | Max_daily_loss
    | Allowlist
    | Min_order_notional
  [@@deriving compare, enumerate, equal, sexp]

  val label : t -> string
end

type t =
  { scale_kind : Scale_kind.t
  ; scale_value : string (** ignored for [Equity_ratio] *)
  ; max_leverage : string
  ; max_notional_per_symbol : string
  ; max_daily_loss : string
  ; allowlist : string (** coins separated by commas or spaces *)
  ; min_order_notional : string
  }
[@@deriving compare, equal, sexp]

(** Equity ratio with {!Api_types.Caps.default}. *)
val default : t

val get : t -> Field.t -> string
val set : t -> Field.t -> string -> t

(** Uppercased, deduplicated, in input order. *)
val parse_allowlist : string -> string list

(** Every invalid field with a message, or the parsed values. *)
val validate : t -> (Scale_mode.t * Caps.t, (Field.t * string) list) Result.t
