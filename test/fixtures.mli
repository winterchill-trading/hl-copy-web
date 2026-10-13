open! Core
open Api_types

(** Reads a file under [dev/] (declared as a test dependency). *)
val dev : string -> Yojson.Safe.t

val leaders : unit -> Leader.t list
val detail : Address.t -> Leader_detail.t
