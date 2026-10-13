(** Small view helpers shared by the pages. Class names refer to the stylesheet in
    [static/index.html]. *)

open! Core
open! Bonsai_web
open Api_types

val link
  :  ?attrs:Vdom.Attr.t list
  -> Copy_web_model.Route.t
  -> Vdom.Node.t list
  -> Vdom.Node.t

val button
  :  ?primary:bool
  -> ?disabled:bool
  -> on_click:unit Effect.t
  -> string
  -> Vdom.Node.t

val error_box : Error.t -> Vdom.Node.t
val notice : string -> Vdom.Node.t
val loading : Vdom.Node.t

(** [Idle] renders nothing, [Loading] a spinner line, [Failed] an error box. *)
val remote : 'a Remote.t -> f:('a -> Vdom.Node.t) -> Vdom.Node.t

(** A labelled figure in a card row. *)
val stat : label:string -> Vdom.Node.t -> Vdom.Node.t

val stats : Vdom.Node.t list -> Vdom.Node.t

(** Green when positive, red when negative. *)
val signed : float -> string -> Vdom.Node.t

val usd_pnl : float -> Vdom.Node.t

(** Header cells and rows of cells; [numeric] columns are right-aligned. *)
val table
  :  ?attrs:Vdom.Attr.t list
  -> header:Vdom.Node.t list
  -> numeric:int list
  -> Vdom.Node.t list list
  -> Vdom.Node.t

val positions_table : Position.t list -> Vdom.Node.t
val section : string -> Vdom.Node.t list -> Vdom.Node.t
