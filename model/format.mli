(** Display formatting for numbers and times. Pure arithmetic on floats, because
    js_of_ocaml ints are 32 bits wide and a millisecond timestamp does not fit in one. *)

open! Core

(** ["$1,234.56"], ["-$12.30"]; amounts of 10,000 or more drop the cents. *)
val usd : float -> string

(** Like {!usd} with an explicit ["+"] for positive amounts. *)
val signed_usd : float -> string

(** [0.4215] is ["42.1%"]. *)
val pct : float -> string

(** ["45s"], ["12m"], ["3h 05m"], ["2d 4h"]. *)
val duration : secs:float -> string

(** ["2026-10-12 08:30"], UTC. *)
val time_ms : Api_types.Time_ms.t -> string

(** ["0.25"], ["1,250"]: up to [decimals] digits, trailing zeros trimmed. *)
val number : ?decimals:int -> float -> string
