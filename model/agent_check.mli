(** Whether the user's agent can trade, which decides if following needs a new
    [approveAgent] signature first. *)

open! Core
open Api_types

type t =
  | Missing (** no agent generated yet *)
  | Not_approved (** generated, but Hyperliquid has not accepted an approval *)
  | Expired of Time_ms.t (** approved with a [valid_until] that has passed *)
  | Active
[@@deriving compare, equal, sexp]

val of_status : Agent_status.t option -> now:Time_ms.t -> t
val needs_approval : t -> bool
val describe : t -> string
