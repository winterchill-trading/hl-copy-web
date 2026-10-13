(** Where the app's data comes from: the copy-trading API over HTTP, or the fixtures under
    [dev/] with an in-memory account so every page works without a server. *)

open! Core
open! Async_kernel
open Api_types

type 'a result := 'a Or_error.t Deferred.t

type t =
  { description : string (** shown in the header: ["mock data"] or the API URL *)
  ; is_mock : bool
  ; leaders : unit -> Leaders_response.t result
  ; leader : Address.t -> Leader_detail.t result
  ; challenge : Auth.Challenge_request.t -> Auth.Challenge.t result
  ; verify : Auth.Verify_request.t -> Auth.Session.t result
  ; me : token:string -> Me.t result
  ; agent_new : token:string -> Agent_offer.t result
  ; agent_approved : token:string -> Agent_approval.t -> Agent_status.t result
  ; builder_fee : token:string -> Builder_fee_approval.t -> Agent_status.t result
  ; follow : token:string -> Follow_request.t -> Follow.t result
  ; update_follow : token:string -> id:string -> Follow_update.t -> Follow.t result
  ; stop_follow : token:string -> id:string -> Follow.t result
  }

(** [base_url] without a trailing slash, e.g. ["http://localhost:8080"]. *)
val live : base_url:string -> t

(** [fixtures] is the URL prefix of the fixture files, e.g. ["dev/"]. The mock signs in
    any address and checks no signatures. *)
val mock : fixtures:string -> t

(** The browser clock in milliseconds since the epoch. *)
val now_ms : unit -> Time_ms.t

(** [?api=<url>] in the page's query string selects {!live}; otherwise {!mock} on
    ["dev/"]. *)
val of_query : (string * string) list -> t
