(** Raw binding to the injected wallet provider, [window.ethereum] (EIP-1193). Use
    {!Ethereum} instead; it turns the promises into deferreds and the values into OCaml
    types. *)

type t

val t_of_js : Ojs.t -> t
val t_to_js : t -> Ojs.t

(** [None] when no wallet extension injected a provider. *)
val get : unit -> t option
[@@js.get "ethereum"]

type request_args =
  { method_ : string [@js "method"]
  ; params : Ojs.t list
  }

(** Returns a JS [Promise]. *)
val request : t -> request_args -> Ojs.t
[@@js.call]
