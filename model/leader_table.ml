open! Core
open Api_types

module Column = struct
  type t =
    | Rank
    | Score
    | Pnl
    | Roi
    | Max_drawdown
    | Win_rate
    | Trades
    | Avg_hold
    | Consistency
    | Account_value
  [@@deriving compare, enumerate, equal, sexp]

  let label = function
    | Rank -> "#"
    | Score -> "Score"
    | Pnl -> "PnL"
    | Roi -> "ROI"
    | Max_drawdown -> "Max DD"
    | Win_rate -> "Win rate"
    | Trades -> "Trades"
    | Avg_hold -> "Avg hold"
    | Consistency -> "Consistency"
    | Account_value -> "Equity"
  ;;

  let key t (l : Leader.t) =
    match t with
    | Rank -> Float.of_int l.rank
    | Score -> l.score
    | Pnl -> l.breakdown.pnl
    | Roi -> l.breakdown.roi
    | Max_drawdown -> l.breakdown.max_drawdown
    | Win_rate -> l.breakdown.win_rate
    | Trades -> Float.of_int l.breakdown.trade_count
    | Avg_hold -> l.breakdown.avg_hold_secs
    | Consistency -> l.breakdown.consistency
    | Account_value -> l.account_value
  ;;
end

module Direction = struct
  type t =
    | Ascending
    | Descending
  [@@deriving compare, equal, sexp]

  let flip = function
    | Ascending -> Descending
    | Descending -> Ascending
  ;;
end

module Sort = struct
  type t =
    { column : Column.t
    ; direction : Direction.t
    }
  [@@deriving compare, equal, sexp]

  let natural_direction : Column.t -> Direction.t = function
    | Rank | Max_drawdown -> Ascending
    | Score | Pnl | Roi | Win_rate | Trades | Avg_hold | Consistency | Account_value ->
      Descending
  ;;

  let default = { column = Rank; direction = Ascending }

  let click t column =
    if Column.equal t.column column
    then { t with direction = Direction.flip t.direction }
    else { column; direction = natural_direction column }
  ;;
end

module Filter = struct
  type t =
    { query : string
    ; min_score : float option
    ; max_drawdown : float option
    ; min_trades : int option
    }
  [@@deriving compare, equal, sexp]

  let empty = { query = ""; min_score = None; max_drawdown = None; min_trades = None }

  let matches t (l : Leader.t) =
    let query = String.lowercase (String.strip t.query) in
    let text_ok =
      String.is_empty query
      || String.is_substring (Address.to_string l.address) ~substring:query
      || Option.exists l.display_name ~f:(fun name ->
        String.is_substring (String.lowercase name) ~substring:query)
    in
    text_ok
    && Option.for_all t.min_score ~f:(fun lo -> Float.(l.score >= lo))
    && Option.for_all t.max_drawdown ~f:(fun hi -> Float.(l.breakdown.max_drawdown <= hi))
    && Option.for_all t.min_trades ~f:(fun min -> l.breakdown.trade_count >= min)
  ;;
end

let apply leaders ~(sort : Sort.t) ~filter =
  let compare_key a b =
    let c = Float.compare (Column.key sort.column a) (Column.key sort.column b) in
    match sort.direction with
    | Ascending -> c
    | Descending -> -c
  in
  List.filter leaders ~f:(Filter.matches filter)
  |> List.stable_sort ~compare:(fun (a : Leader.t) (b : Leader.t) ->
    Int.compare a.rank b.rank)
  |> List.stable_sort ~compare:compare_key
;;
