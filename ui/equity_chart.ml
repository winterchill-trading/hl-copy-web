open! Core
open! Bonsai_web
open Copy_web_model
module S = Virtual_dom_svg.Node
module A = Vdom.Attr

let attr name value = A.create name value
let num name x = attr name (sprintf "%.2f" x)

let view ?(width = 720.) ?(height = 260.) points =
  match Chart.equity_curve points ~width ~height with
  | None -> Widgets.notice "Not enough history to draw an equity curve."
  | Some c ->
    let grid =
      List.concat_map c.y_ticks ~f:(fun tick ->
        [ S.line
            ~attrs:
              [ num "x1" c.plot_left
              ; num "x2" c.plot_right
              ; num "y1" tick.at
              ; num "y2" tick.at
              ; attr "class" "grid-line"
              ]
            []
        ; S.text
            ~attrs:
              [ num "x" (c.plot_left -. 8.)
              ; num "y" (tick.at +. 4.)
              ; attr "text-anchor" "end"
              ; attr "class" "axis-label"
              ]
            [ Vdom.Node.text tick.label ]
        ])
    in
    let dates =
      List.mapi c.x_ticks ~f:(fun i tick ->
        let anchor =
          if i = 0 then "start" else if i = List.length c.x_ticks - 1 then "end" else "middle"
        in
        S.text
          ~attrs:
            [ num "x" tick.at
            ; num "y" (c.plot_bottom +. 18.)
            ; attr "text-anchor" anchor
            ; attr "class" "axis-label"
            ]
          [ Vdom.Node.text tick.label ])
    in
    let start_line =
      S.line
        ~attrs:
          [ num "x1" c.plot_left
          ; num "x2" c.plot_right
          ; num "y1" c.start_y
          ; num "y2" c.start_y
          ; attr "class" "start-line"
          ]
        []
    in
    let curve =
      S.polyline
        ~attrs:
          [ attr
              "points"
              (List.map c.line ~f:(fun (x, y) -> sprintf "%.2f,%.2f" x y)
               |> String.concat ~sep:" ")
          ; attr "class" (if c.ending_above_start then "curve up" else "curve down")
          ]
        []
    in
    S.svg
      ~attrs:
        [ attr "viewBox" (sprintf "0 0 %g %g" width height)
        ; attr "class" "equity-chart"
        ; attr "role" "img"
        ; attr "aria-label" "Equity curve"
        ]
      (grid @ dates @ [ start_line; curve ])
;;
