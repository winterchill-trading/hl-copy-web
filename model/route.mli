(** Pages of the app, addressed by the URL fragment so links and the back button work
    without a server-side router. *)

open! Core
open Api_types

type t =
  | Leaders
  | Leader of Address.t
  | Follow of Address.t
  | Dashboard
  | Login
[@@deriving compare, equal, sexp]

(** Accepts the fragment with or without the leading [#]. Anything unrecognised, including
    the empty fragment, is [Leaders]. *)
val of_hash : string -> t

(** ["#/leaders"], ["#/leader/0x..."], ... *)
val to_hash : t -> string

val title : t -> string
