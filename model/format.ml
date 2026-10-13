open! Core

let group_thousands digits =
  let n = String.length digits in
  let buf = Buffer.create (n + (n / 3)) in
  String.iteri digits ~f:(fun i c ->
    if i > 0 && (n - i) % 3 = 0 then Buffer.add_char buf ',';
    Buffer.add_char buf c);
  Buffer.contents buf
;;

(* [digits] is the integer part as printed by sprintf, so it never goes through an int. *)
let with_commas ~decimals x =
  let s = sprintf "%.*f" decimals (Float.abs x) in
  let int_part, frac =
    match String.lsplit2 s ~on:'.' with
    | Some (i, f) -> i, "." ^ f
    | None -> s, ""
  in
  group_thousands int_part ^ frac
;;

let usd x =
  let decimals = if Float.(abs x >= 10_000.) then 0 else 2 in
  let sign =
    if Float.(x < 0.) && not (String.equal (with_commas ~decimals x) "0.00")
    then "-"
    else ""
  in
  sign ^ "$" ^ with_commas ~decimals x
;;

let signed_usd x = if Float.(x > 0.) then "+" ^ usd x else usd x
let pct x = sprintf "%.1f%%" (x *. 100.)

let duration ~secs =
  let secs = Float.max 0. secs in
  let minutes = Float.iround_down_exn (secs /. 60.) in
  let hours = minutes / 60 in
  let days = hours / 24 in
  if Float.(secs < 60.)
  then sprintf "%.0fs" secs
  else if hours = 0
  then sprintf "%dm" minutes
  else if days = 0
  then sprintf "%dh %02dm" hours (minutes % 60)
  else sprintf "%dd %dh" days (hours % 24)
;;

let ms_per_day = 86_400_000.

let time_ms ms =
  let days = Float.round_down (ms /. ms_per_day) in
  let ms_of_day = ms -. (days *. ms_per_day) in
  let date =
    Date.add_days (Date.create_exn ~y:1970 ~m:Jan ~d:1) (Float.iround_down_exn days)
  in
  let minute_of_day = Float.iround_down_exn (ms_of_day /. 60_000.) in
  sprintf "%s %02d:%02d" (Date.to_string date) (minute_of_day / 60) (minute_of_day % 60)
;;

let number ?(decimals = 4) x =
  let s = with_commas ~decimals x in
  let s =
    if String.mem s '.'
    then
      String.rstrip s ~drop:(Char.equal '0') |> String.chop_suffix_if_exists ~suffix:"."
    else s
  in
  if Float.(x < 0.) && not (String.equal s "0") then "-" ^ s else s
;;
