open! Core
open! Bonsai_web
open Copy_web_model
module S = Virtual_dom_svg.Node
module A = Vdom.Attr

let attr name value = A.create name value
let num name x = attr name (sprintf "%.2f" x)

let view ?(width = 720.) ?(height = 240.) capacity =
  match Scoring_view.Capacity_chart.of_capacity capacity ~width ~height with
  | None -> Widgets.notice "Not enough points to draw a capacity curve."
  | Some c ->
    let label ~x ~y ~anchor text =
      S.text
        ~attrs:[ num "x" x; num "y" y; attr "text-anchor" anchor; attr "class" "axis-label" ]
        [ Vdom.Node.text text ]
    in
    let grid =
      List.concat_map c.y_ticks ~f:(fun t ->
        [ S.line
            ~attrs:
              [ num "x1" c.plot_left
              ; num "x2" c.plot_right
              ; num "y1" t.at
              ; num "y2" t.at
              ; attr "class" "grid-line"
              ]
            []
        ; label ~x:(c.plot_left -. 8.) ~y:(t.at +. 4.) ~anchor:"end" t.label
        ])
    in
    let sizes =
      List.mapi c.x_ticks ~f:(fun i t ->
        let anchor =
          if i = 0 then "start" else if i = List.length c.x_ticks - 1 then "end" else "middle"
        in
        label ~x:t.at ~y:(c.plot_bottom +. 18.) ~anchor t.label)
    in
    let threshold =
      Option.to_list c.threshold_y
      |> List.map ~f:(fun y ->
        S.line
          ~attrs:
            [ num "x1" c.plot_left
            ; num "x2" c.plot_right
            ; num "y1" y
            ; num "y2" y
            ; attr "class" "threshold"
            ]
          [])
    in
    let capacity_line =
      Option.to_list c.capacity_x
      |> List.map ~f:(fun x ->
        S.line
          ~attrs:
            [ num "x1" x
            ; num "x2" x
            ; num "y1" c.plot_top
            ; num "y2" c.plot_bottom
            ; attr "class" "capacity"
            ]
          [])
    in
    let line =
      S.polyline
        ~attrs:
          [ attr
              "points"
              (List.map c.line ~f:(fun (x, y) -> sprintf "%.2f,%.2f" x y)
               |> String.concat ~sep:" ")
          ; attr "class" "cost"
          ]
        []
    in
    let dots =
      List.map c.line ~f:(fun (x, y) ->
        S.circle ~attrs:[ num "cx" x; num "cy" y; attr "r" "3"; attr "class" "dot" ] [])
    in
    S.svg
      ~attrs:
        [ attr "viewBox" (sprintf "0 0 %g %g" width height)
        ; attr "class" "capacity-chart"
        ; attr "id" "capacity-chart"
        ; attr "role" "img"
        ; attr "aria-label" "Estimated copy cost by follower size"
        ]
      (grid @ sizes @ threshold @ capacity_line @ (line :: dots))
;;
