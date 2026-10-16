open! Core
open Api_types

module Scale_kind = struct
  type t =
    | Equity_ratio
    | Multiplier
    | Fixed_notional
  [@@deriving compare, enumerate, equal, sexp]

  let label = function
    | Equity_ratio -> "Equity ratio (my equity / leader equity)"
    | Multiplier -> "Fixed multiplier of leader size"
    | Fixed_notional -> "Fixed USD notional per position"
  ;;

  let to_string = function
    | Equity_ratio -> "equity_ratio"
    | Multiplier -> "multiplier"
    | Fixed_notional -> "fixed_notional"
  ;;

  let of_string s = List.find all ~f:(fun t -> String.equal (to_string t) s)
end

module Field = struct
  type t =
    | Scale_value
    | Max_leverage
    | Max_notional_per_symbol
    | Max_daily_loss
    | Allowlist
    | Min_order_notional
    | Algo_seconds
    | Algo_slices
  [@@deriving compare, enumerate, equal, sexp]

  let label = function
    | Scale_value -> "Scale value"
    | Max_leverage -> "Max leverage"
    | Max_notional_per_symbol -> "Max notional per symbol (USD)"
    | Max_daily_loss -> "Max daily loss (USD)"
    | Allowlist -> "Coins to copy (empty = all)"
    | Min_order_notional -> "Min order notional (USD)"
    | Algo_seconds -> "Algorithm duration or timeout (seconds)"
    | Algo_slices -> "TWAP slices"
  ;;
end

type t =
  { scale_kind : Scale_kind.t
  ; scale_value : string
  ; max_leverage : string
  ; max_notional_per_symbol : string
  ; max_daily_loss : string
  ; allowlist : string
  ; min_order_notional : string
  ; algo : Algo_choice.Kind.t
  ; algo_seconds : string
  ; algo_slices : string
  }
[@@deriving compare, equal, sexp]

module Valid = struct
  type t =
    { scale : Scale_mode.t
    ; caps : Caps.t
    ; algo : string option
    }
  [@@deriving compare, equal, sexp]
end

let default =
  let c = Caps.default in
  { scale_kind = Equity_ratio
  ; scale_value = "1"
  ; max_leverage = sprintf "%g" c.max_leverage
  ; max_notional_per_symbol = sprintf "%g" c.max_notional_per_symbol
  ; max_daily_loss = sprintf "%g" c.max_daily_loss
  ; allowlist = String.concat ~sep:", " c.allowlist
  ; min_order_notional = sprintf "%g" c.min_order_notional
  ; algo = Immediate
  ; algo_seconds = ""
  ; algo_slices = ""
  }
;;

let with_algo t (kind : Algo_choice.Kind.t) =
  match kind with
  | Immediate -> { t with algo = kind; algo_seconds = ""; algo_slices = "" }
  | Twap | Adaptive | Passive ->
    { t with
      algo = kind
    ; algo_seconds = Int.to_string (Algo_choice.Kind.default_seconds kind)
    ; algo_slices =
        (match kind with
         | Twap -> Int.to_string Algo_choice.default_slices
         | Immediate | Adaptive | Passive -> "")
    }
;;

let get t : Field.t -> string = function
  | Scale_value -> t.scale_value
  | Max_leverage -> t.max_leverage
  | Max_notional_per_symbol -> t.max_notional_per_symbol
  | Max_daily_loss -> t.max_daily_loss
  | Allowlist -> t.allowlist
  | Min_order_notional -> t.min_order_notional
  | Algo_seconds -> t.algo_seconds
  | Algo_slices -> t.algo_slices
;;

let set t (field : Field.t) v =
  match field with
  | Scale_value -> { t with scale_value = v }
  | Max_leverage -> { t with max_leverage = v }
  | Max_notional_per_symbol -> { t with max_notional_per_symbol = v }
  | Max_daily_loss -> { t with max_daily_loss = v }
  | Allowlist -> { t with allowlist = v }
  | Min_order_notional -> { t with min_order_notional = v }
  | Algo_seconds -> { t with algo_seconds = v }
  | Algo_slices -> { t with algo_slices = v }
;;

let parse_allowlist s =
  String.split_on_chars s ~on:[ ','; ' '; '\t'; '\n' ]
  |> List.filter_map ~f:(fun c ->
    let c = String.uppercase (String.strip c) in
    Option.some_if (not (String.is_empty c)) c)
  |> List.stable_dedup ~compare:String.compare
;;

let valid_coin c =
  String.length c <= 12
  && String.for_all c ~f:(fun ch -> Char.is_alphanum ch || Char.equal ch '-')
;;

let validate t =
  let errors = ref [] in
  let fail field msg = errors := (field, msg) :: !errors in
  (* Accept thousands separators: people type "5,000". *)
  let number field ~lo ~hi =
    let raw =
      String.strip (get t field) |> String.filter ~f:(fun c -> not (Char.equal c ','))
    in
    match Float.of_string_opt raw with
    | Some x when Float.is_finite x && Float.(x >= lo && x <= hi) -> x
    | Some _ ->
      fail
        field
        (sprintf "must be between %s and %s" (Format.number lo) (Format.number hi));
      0.
    | None ->
      fail field "must be a number";
      0.
  in
  let scale : Scale_mode.t =
    match t.scale_kind with
    | Equity_ratio -> Equity_ratio
    | Multiplier -> Multiplier (number Scale_value ~lo:0.001 ~hi:10.)
    | Fixed_notional -> Fixed_notional (number Scale_value ~lo:1. ~hi:1_000_000.)
  in
  let max_leverage = number Max_leverage ~lo:0. ~hi:50. in
  let max_notional_per_symbol = number Max_notional_per_symbol ~lo:0. ~hi:1e9 in
  let max_daily_loss = number Max_daily_loss ~lo:0. ~hi:1e9 in
  let min_order_notional = number Min_order_notional ~lo:0. ~hi:1e6 in
  let allowlist = parse_allowlist t.allowlist in
  (match List.filter allowlist ~f:(Fn.non valid_coin) with
   | [] -> ()
   | bad -> fail Allowlist ("not a coin: " ^ String.concat ~sep:", " bad));
  let algo =
    match t.algo with
    | Immediate -> None
    | Twap | Adaptive | Passive as kind ->
      (* an hour bounds how long one leader change may take to copy *)
      let seconds = number Algo_seconds ~lo:1. ~hi:3600. |> Float.iround_nearest_exn in
      let slices =
        match kind with
        | Twap -> number Algo_slices ~lo:1. ~hi:100. |> Float.iround_nearest_exn
        | Immediate | Adaptive | Passive -> 0
      in
      Algo_choice.to_wire kind ~seconds ~slices
  in
  match List.rev !errors with
  | [] ->
    Ok
      { Valid.scale
      ; caps =
          { Caps.max_leverage
          ; max_notional_per_symbol
          ; max_daily_loss
          ; allowlist
          ; min_order_notional
          }
      ; algo
      }
  | errors -> Error errors
;;

let request (v : Valid.t) ~leader =
  { Follow_request.leader; scale = v.scale; caps = v.caps; algo = v.algo }
;;
