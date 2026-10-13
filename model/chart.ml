open! Core
open Api_types

module Tick = struct
  type t =
    { at : float
    ; label : string
    }
  [@@deriving equal, sexp_of]
end

type t =
  { width : float
  ; height : float
  ; plot_left : float
  ; plot_right : float
  ; plot_top : float
  ; plot_bottom : float
  ; line : (float * float) list
  ; y_ticks : Tick.t list
  ; x_ticks : Tick.t list
  ; start_y : float
  ; ending_above_start : bool
  }
[@@deriving sexp_of]

let nice_step x =
  if Float.(x <= 0.)
  then 1.
  else (
    let power = 10. ** Float.round_down (Float.log10 x) in
    let m = x /. power in
    let base = if Float.(m <= 1.) then 1. else if Float.(m <= 2.) then 2. else if Float.(m <= 5.) then 5. else 10. in
    base *. power)
;;

(* Space for "$1,234,567" on the left and a date row at the bottom. *)
let pad_left = 72.
let pad_right = 12.
let pad_top = 10.
let pad_bottom = 24.

let date_label ms = String.prefix (Format.time_ms ms) 10

let equity_curve (points : Equity_point.t list) ~width ~height =
  match points with
  | [] | [ _ ] -> None
  | first :: _ ->
    let last = List.last_exn points in
    let lo, hi =
      List.fold points ~init:(Float.infinity, Float.neg_infinity) ~f:(fun (lo, hi) p ->
        Float.min lo p.equity, Float.max hi p.equity)
    in
    let lo, hi =
      if Float.(hi -. lo < 1e-9)
      then (
        let band = Float.max 1. (Float.abs lo *. 0.01) in
        lo -. band, hi +. band)
      else lo, hi
    in
    let step = nice_step ((hi -. lo) /. 5.) in
    let lo = Float.round_down (lo /. step) *. step in
    let hi = Float.round_up (hi /. step) *. step in
    let plot_left = pad_left
    and plot_right = width -. pad_right
    and plot_top = pad_top
    and plot_bottom = height -. pad_bottom in
    let t0 = first.time
    and t1 = last.time in
    let span = if Float.(t1 > t0) then t1 -. t0 else 1. in
    let x_of time = plot_left +. ((time -. t0) /. span *. (plot_right -. plot_left)) in
    let y_of equity =
      plot_bottom -. ((equity -. lo) /. (hi -. lo) *. (plot_bottom -. plot_top))
    in
    let line = List.map points ~f:(fun p -> x_of p.time, y_of p.equity) in
    let n_ticks = Float.iround_nearest_exn ((hi -. lo) /. step) in
    let y_ticks =
      List.init (n_ticks + 1) ~f:(fun i ->
        let v = lo +. (Float.of_int i *. step) in
        { Tick.at = y_of v; label = Format.usd v })
      |> List.rev
    in
    let mid = t0 +. (span /. 2.) in
    let x_ticks =
      List.map [ t0; mid; t1 ] ~f:(fun time -> { Tick.at = x_of time; label = date_label time })
    in
    Some
      { width
      ; height
      ; plot_left
      ; plot_right
      ; plot_top
      ; plot_bottom
      ; line
      ; y_ticks
      ; x_ticks
      ; start_y = y_of first.equity
      ; ending_above_start = Float.(last.equity >= first.equity)
      }
;;
