open! Core
open Api_types

let transition (state : Follow_state.t) (command : Follow_command.t) =
  match state, command with
  | Running, Pause -> Ok Follow_state.Paused
  | Paused, Resume -> Ok Running
  | (Running | Paused), Stop -> Ok Stopped
  | _ ->
    Or_error.error_s
      [%message
        "follow cannot do that now"
          ~state:(Follow_state.to_string state)
          ~command:(Follow_command.to_string command)]
;;

let apply_command (d : Dashboard.t) ~id command =
  match List.find d.follows ~f:(fun f -> String.equal f.id id) with
  | None -> Or_error.error_s [%message "no such follow" id]
  | Some follow ->
    let%map.Or_error state = transition follow.state command in
    let follow = { follow with state } in
    let follows =
      List.map d.follows ~f:(fun f -> if String.equal f.id id then follow else f)
    in
    { d with follows }, follow
;;

let add_follow (d : Dashboard.t) (r : Follow_request.t) ~now =
  let follow =
    { Follow.id = sprintf "f-%d" (List.length d.follows + 1)
    ; leader = r.leader
    ; scale = r.scale
    ; caps = r.caps
    ; state = Running
    ; created_at = now
    ; pnl = 0.
    ; positions = []
    }
  in
  { d with follows = d.follows @ [ follow ] }, follow
;;
