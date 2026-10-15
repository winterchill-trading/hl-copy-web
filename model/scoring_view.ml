open! Core
open Api_types

let format_metric (m : Scoring.Metric.t) =
  match m.value with
  | None -> "-"
  | Some v ->
    (match m.unit with
     | "ratio" -> Format.pct v
     | "count" -> Format.number ~decimals:0 v
     | "days" -> sprintf "%s d" (Format.number ~decimals:1 v)
     | "hours" -> Format.duration ~secs:(v *. 3600.)
     | "per_day" -> sprintf "%s / day" (Format.number ~decimals:2 v)
     | "multiple" -> sprintf "%sx" (Format.number ~decimals:2 v)
     | _ -> Format.number ~decimals:2 v)
;;

let direction_hint (m : Scoring.Metric.t) =
  match m.better with
  | "higher" -> "higher is better"
  | "lower" -> "lower is better"
  | _ -> ""
;;

let severity_class = function
  | "critical" -> "badge critical"
  | "warning" -> "badge warning"
  | _ -> "badge info"
;;

let kind_label kind =
  match String.substr_replace_all kind ~pattern:"_" ~with_:" " with
  | "" -> ""
  | s -> String.capitalize s
;;

let compact_usd x =
  let ax = Float.abs x in
  if Float.(ax >= 1e9)
  then sprintf "$%sB" (Format.number ~decimals:1 (x /. 1e9))
  else if Float.(ax >= 1e6)
  then sprintf "$%sM" (Format.number ~decimals:1 (x /. 1e6))
  else if Float.(ax >= 1e3)
  then sprintf "$%sk" (Format.number ~decimals:0 (x /. 1e3))
  else sprintf "$%s" (Format.number ~decimals:0 x)
;;

module Capacity_chart = struct
  type t =
    { width : float
    ; height : float
    ; plot_left : float
    ; plot_right : float
    ; plot_top : float
    ; plot_bottom : float
    ; line : (float * float) list
    ; x_ticks : Chart.Tick.t list
    ; y_ticks : Chart.Tick.t list
    ; threshold_y : float option
    ; capacity_x : float option
    }
  [@@deriving sexp_of]

  (* Space for "100 bps" on the left and the size labels underneath. *)
  let pad_left = 60.
  let pad_right = 16.
  let pad_top = 10.
  let pad_bottom = 24.

  let of_capacity (c : Scoring.Capacity.t) ~width ~height =
    let points =
      List.filter c.curve ~f:(fun p -> Float.(p.follower_equity > 0.))
      |> List.sort ~compare:(fun a b -> Float.compare a.follower_equity b.follower_equity)
    in
    match points with
    | [] | [ _ ] -> None
    | first :: _ ->
      let last = List.last_exn points in
      let lx x = Float.log10 x in
      let x0 = lx first.follower_equity
      and x1 = lx last.follower_equity in
      let plot_left = pad_left
      and plot_right = width -. pad_right
      and plot_top = pad_top
      and plot_bottom = height -. pad_bottom in
      let top_cost =
        List.fold points ~init:c.max_cost_bps ~f:(fun acc p -> Float.max acc p.mean_cost_bps)
      in
      let step = Chart.nice_step (top_cost /. 4.) in
      let y_max = step *. Float.round_up (top_cost /. step) in
      let x v = plot_left +. ((lx v -. x0) /. (x1 -. x0) *. (plot_right -. plot_left)) in
      let y bps = plot_bottom -. (bps /. y_max *. (plot_bottom -. plot_top)) in
      let y_ticks =
        List.init
          (Float.iround_nearest_exn (y_max /. step) + 1)
          ~f:(fun i ->
            let v = step *. Float.of_int i in
            { Chart.Tick.at = y v; label = sprintf "%s bps" (Format.number ~decimals:1 v) })
      in
      Some
        { width
      ; height
      ; plot_left
      ; plot_right
      ; plot_top
      ; plot_bottom
      ; line = List.map points ~f:(fun p -> x p.follower_equity, y p.mean_cost_bps)
      ; x_ticks =
          List.map points ~f:(fun p ->
            { Chart.Tick.at = x p.follower_equity; label = compact_usd p.follower_equity })
      ; y_ticks
      ; threshold_y = (if Float.(c.max_cost_bps <= y_max) then Some (y c.max_cost_bps) else None)
      ; capacity_x =
          Option.bind c.capacity_usd ~f:(fun cap ->
            if Float.(cap >= first.follower_equity && cap <= last.follower_equity)
            then Some (x cap)
            else None)
        }
  ;;
end
