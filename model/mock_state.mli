(** The in-memory account the mock backend serves, so approvals, new follows and state
    changes show up on the dashboard without a server. *)

open! Core
open Api_types

(** [PATCH /follows/<id>]: [Paused] needs [Running], [Running] needs [Paused]. A stopped
    follow cannot change. *)
val update_follow : Me.t -> id:string -> Follow_update.t -> (Me.t * Follow.t) Or_error.t

(** [DELETE /follows/<id>] *)
val stop_follow : Me.t -> id:string -> (Me.t * Follow.t) Or_error.t

(** [POST /follows]: appends a running follow with id [f-<n>] and no positions yet; fails
    without an active agent. *)
val add_follow : Me.t -> Follow_request.t -> now:Time_ms.t -> (Me.t * Follow.t) Or_error.t

(** [POST /agent/approved]: the agent becomes approved for 180 days (the longest
    Hyperliquid allows), keeping a builder fee approved before. *)
val approve_agent : Me.t -> Agent_approval.t -> now:Time_ms.t -> Me.t * Agent_status.t

(** [POST /builder-fee]: needs an agent. *)
val approve_builder_fee
  :  Me.t
  -> Builder_fee_approval.t
  -> (Me.t * Agent_status.t) Or_error.t
