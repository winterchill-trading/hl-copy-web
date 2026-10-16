open! Core

module Kind = struct
  type t =
    | Immediate
    | Twap
    | Adaptive
    | Passive
  [@@deriving compare, enumerate, equal, sexp]

  let label = function
    | Immediate -> "Immediate"
    | Twap -> "TWAP"
    | Adaptive -> "Adaptive"
    | Passive -> "Passive"
  ;;

  let help = function
    | Immediate -> "One IOC order per leader change: fastest, pays the spread."
    | Twap -> "Splits each change into equal IOC slices over the duration."
    | Adaptive ->
      "Rests at the touch while the order is small and the follow is close behind, then \
       takes liquidity; the copy default for larger accounts."
    | Passive ->
      "Posts at the best price on its side, sends what is left as IOC after the timeout."
  ;;

  let to_string = function
    | Immediate -> "immediate"
    | Twap -> "twap"
    | Adaptive -> "adaptive"
    | Passive -> "passive"
  ;;

  let of_string s = List.find all ~f:(fun t -> String.equal (to_string t) s)

  let seconds_label = function
    | Immediate -> None
    | Twap -> Some "Duration (seconds)"
    | Adaptive | Passive -> Some "Timeout (seconds)"
  ;;

  let default_seconds = function
    | Immediate -> 0
    | Twap -> 60
    | Adaptive -> 20
    | Passive -> 30
  ;;
end

let default_slices = 6

let to_wire (kind : Kind.t) ~seconds ~slices =
  match kind with
  | Immediate -> None
  | Twap -> Some (sprintf "twap:%ds:%d" seconds slices)
  | Adaptive -> Some (sprintf "adaptive:%ds" seconds)
  | Passive -> Some (sprintf "passive:%ds" seconds)
;;

let seconds s =
  match String.chop_suffix s ~suffix:"s" with
  | Some n -> Int.of_string_opt n
  | None -> None
;;

let of_wire s =
  match String.split s ~on:':' with
  | [ "immediate" ] -> Some (Kind.Immediate, 0, 0)
  | [ "twap"; d; n ] ->
    (match seconds d, Int.of_string_opt n with
     | Some d, Some n -> Some (Twap, d, n)
     | _ -> None)
  | [ "adaptive"; d ] -> Option.map (seconds d) ~f:(fun d -> Kind.Adaptive, d, 0)
  | [ "passive"; d ] -> Option.map (seconds d) ~f:(fun d -> Kind.Passive, d, 0)
  | _ -> None
;;

let describe = function
  | None -> "Immediate"
  | Some s ->
    (match of_wire s with
     | Some (Immediate, _, _) -> "Immediate"
     | Some (Twap, d, n) -> sprintf "TWAP %d s in %d slices" d n
     | Some (Adaptive, d, _) -> sprintf "Adaptive, %d s timeout" d
     | Some (Passive, d, _) -> sprintf "Passive, %d s timeout" d
     | None -> s)
;;
