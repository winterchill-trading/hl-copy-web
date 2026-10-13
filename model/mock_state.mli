(** The in-memory account the mock backend serves, so commands and new follows show up on
    the dashboard without a server. *)

open! Core
open Api_types

(** Pause needs [Running], resume needs [Paused], stop needs anything but [Stopped]. *)
val transition : Follow_state.t -> Follow_command.t -> Follow_state.t Or_error.t

val apply_command
  :  Dashboard.t
  -> id:string
  -> Follow_command.t
  -> (Dashboard.t * Follow.t) Or_error.t

(** Appends a running follow with id [f-<n>] and no positions yet. *)
val add_follow
  :  Dashboard.t
  -> Follow_request.t
  -> now:Time_ms.t
  -> Dashboard.t * Follow.t
