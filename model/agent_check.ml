open! Core
open Api_types

type t =
  | Missing
  | Not_approved
  | Expired of Time_ms.t
  | Active
[@@deriving compare, equal, sexp]

let of_status (status : Agent_status.t option) ~now =
  match status with
  | None -> Missing
  | Some { approved = false; _ } -> Not_approved
  | Some { valid_until = Some until; _ } when Float.(until <= now) -> Expired until
  | Some _ -> Active
;;

let needs_approval = function
  | Active -> false
  | Missing | Not_approved | Expired _ -> true
;;

let describe = function
  | Missing -> "You have no trading agent yet. Following starts by approving one."
  | Not_approved -> "Your trading agent is waiting for your approval."
  | Expired until ->
    sprintf
      "Your trading agent's approval expired on %s UTC. Approve a new agent to keep \
       copying."
      (Format.time_ms until)
  | Active -> "Your trading agent is approved."
;;
