open! Core
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr

let link ?(attrs = []) route children =
  N.a ~attrs:(A.href (Route.to_hash route) :: attrs) children
;;

let button ?(primary = false) ?(disabled = false) ~on_click label =
  N.button
    ~attrs:
      [ A.classes (if primary then [ "btn"; "primary" ] else [ "btn" ])
      ; A.disabled' disabled
      ; A.on_click (fun _ -> on_click)
      ]
    [ N.text label ]
;;

let error_box e = N.div ~attrs:[ A.class_ "error" ] [ N.text (Error.to_string_hum e) ]
let notice text = N.div ~attrs:[ A.class_ "notice" ] [ N.text text ]
let loading = N.div ~attrs:[ A.class_ "loading" ] [ N.text "Loading..." ]

let remote (r : _ Remote.t) ~f =
  match r with
  | Idle -> N.none
  | Loading -> loading
  | Failed e -> error_box e
  | Loaded a -> f a
;;

let stat ~label value =
  N.div
    ~attrs:[ A.class_ "stat" ]
    [ N.div ~attrs:[ A.class_ "stat-label" ] [ N.text label ]
    ; N.div ~attrs:[ A.class_ "stat-value" ] [ value ]
    ]
;;

let stats children = N.div ~attrs:[ A.class_ "stats" ] children

let signed x text =
  let cls = if Float.(x > 0.) then "pos" else if Float.(x < 0.) then "neg" else "flat" in
  N.span ~attrs:[ A.class_ cls ] [ N.text text ]
;;

let usd_pnl x = signed x (Format.signed_usd x)

let table ?(attrs = []) ~header ~numeric rows =
  let cell_attrs i =
    if List.mem numeric i ~equal:Int.equal then [ A.class_ "num" ] else []
  in
  N.table
    ~attrs:(A.class_ "grid" :: attrs)
    [ N.thead [ N.tr (List.mapi header ~f:(fun i h -> N.th ~attrs:(cell_attrs i) [ h ])) ]
    ; N.tbody
        (List.map rows ~f:(fun cells ->
           N.tr (List.mapi cells ~f:(fun i c -> N.td ~attrs:(cell_attrs i) [ c ]))))
    ]
;;

let positions_table (positions : Position.t list) =
  match positions with
  | [] -> notice "No open positions."
  | _ ->
    table
      ~header:
        (List.map [ "Coin"; "Side"; "Size"; "Entry"; "Leverage"; "Unrealized" ] ~f:N.text)
      ~numeric:[ 2; 3; 4; 5 ]
      (List.map positions ~f:(fun p ->
         [ N.text p.coin
         ; (if Float.(p.size >= 0.) then signed 1. "Long" else signed (-1.) "Short")
         ; N.text (Format.number (Float.abs p.size))
         ; N.text (Format.number ~decimals:2 p.entry_px)
         ; N.textf "%gx" p.leverage
         ; usd_pnl p.unrealized_pnl
         ]))
;;

let section title children =
  N.section ~attrs:[ A.class_ "card" ] (N.h2 [ N.text title ] :: children)
;;
