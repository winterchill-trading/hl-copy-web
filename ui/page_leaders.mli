(** The leaderboard: every ranked leader with the components of the score, sortable by
    any column and filtered by text, minimum score, maximum drawdown and trade count. *)

open! Core
open! Bonsai_web

val component
  :  backend:Backend.t
  -> active:bool Bonsai.t
  -> local_ Bonsai.graph
  -> Vdom.Node.t Bonsai.t
