(** Sorting and filtering for the leaderboard table. *)

open! Core
open Api_types

module Column : sig
  type t =
    | Rank
    | Score
    | Pnl
    | Roi
    | Max_drawdown
    | Win_rate
    | Trades
    | Avg_hold
    | Consistency
    | Account_value
  [@@deriving compare, enumerate, equal, sexp]

  val label : t -> string
end

module Direction : sig
  type t =
    | Ascending
    | Descending
  [@@deriving compare, equal, sexp]
end

module Sort : sig
  type t =
    { column : Column.t
    ; direction : Direction.t
    }
  [@@deriving compare, equal, sexp]

  (** Rank, ascending. *)
  val default : t

  (** Clicking the sorted column flips the direction; another column starts at its natural
      direction (best first: ascending for rank and drawdown, descending otherwise). *)
  val click : t -> Column.t -> t
end

module Filter : sig
  type t =
    { query : string (** case-insensitive substring of the address or display name *)
    ; min_score : float option
    ; max_drawdown : float option (** fraction, [0.2] is 20% *)
    ; min_trades : int option
    }
  [@@deriving compare, equal, sexp]

  val empty : t
  val matches : t -> Leader.t -> bool
end

(** Filtered then sorted; ties keep rank order. *)
val apply : Leader.t list -> sort:Sort.t -> filter:Filter.t -> Leader.t list
