(** The follow form: raw input strings, and validation into a scale mode, caps and an
    execution algorithm. *)

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
    | Algo_seconds
    | Algo_slices
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
  ; algo : Algo_choice.Kind.t
  ; algo_seconds : string (** ignored for [Immediate] *)
  ; algo_slices : string (** TWAP only *)
  }
[@@deriving compare, equal, sexp]

(** Equity ratio with {!Api_types.Caps.default}, immediate execution. *)
val default : t

(** Switches the algorithm and resets its fields to that algorithm's defaults. *)
val with_algo : t -> Algo_choice.Kind.t -> t

module Valid : sig
  type t =
    { scale : Scale_mode.t
    ; caps : Caps.t
    ; algo : string option (** {!Algo_choice.to_wire}; [None] for immediate *)
    }
  [@@deriving compare, equal, sexp]
end

val get : t -> Field.t -> string
val set : t -> Field.t -> string -> t

(** Uppercased, deduplicated, in input order. *)
val parse_allowlist : string -> string list

(** Every invalid field with a message, or the parsed values. *)
val validate : t -> (Valid.t, (Field.t * string) list) Result.t

(** The [POST /follows] body for [leader]. *)
val request : Valid.t -> leader:Address.t -> Follow_request.t
