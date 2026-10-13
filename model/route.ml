open! Core
open Api_types

type t =
  | Leaders
  | Leader of Address.t
  | Follow of Address.t
  | Dashboard
  | Login
[@@deriving compare, equal, sexp]

let of_hash hash =
  let path = String.chop_prefix_if_exists hash ~prefix:"#" in
  match String.split path ~on:'/' |> List.filter ~f:(Fn.non String.is_empty) with
  | [ "dashboard" ] -> Dashboard
  | [ "login" ] -> Login
  | [ "leader"; address ] ->
    Option.value_map (Address.of_string_opt address) ~default:Leaders ~f:(fun a ->
      Leader a)
  | [ "follow"; address ] ->
    Option.value_map (Address.of_string_opt address) ~default:Leaders ~f:(fun a ->
      Follow a)
  | _ -> Leaders
;;

let to_hash = function
  | Leaders -> "#/leaders"
  | Leader a -> "#/leader/" ^ Address.to_string a
  | Follow a -> "#/follow/" ^ Address.to_string a
  | Dashboard -> "#/dashboard"
  | Login -> "#/login"
;;

let title = function
  | Leaders -> "Leaders"
  | Leader a -> "Leader " ^ Address.short a
  | Follow a -> "Follow " ^ Address.short a
  | Dashboard -> "Dashboard"
  | Login -> "Connect wallet"
;;
