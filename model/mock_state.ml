open! Core
open Api_types

let find_follow (me : Me.t) ~id =
  match List.find me.follows ~f:(fun f -> String.equal f.id id) with
  | Some f -> Ok f
  | None -> Or_error.error_s [%message "no such follow" id]
;;

let replace_follow (me : Me.t) (follow : Follow.t) =
  let follows =
    List.map me.follows ~f:(fun f -> if String.equal f.id follow.id then follow else f)
  in
  { me with follows }, follow
;;

let update_follow me ~id ({ state; algo } : Follow_update.t) =
  let%bind.Or_error follow = find_follow me ~id in
  let%bind.Or_error follow =
    match follow.state, state with
    | Stopped, _ -> Or_error.error_s [%message "follow is stopped" id]
    | _, None -> Ok follow
    | Running, Some (Paused as state) | Paused, Some (Running as state) ->
      Ok { follow with state }
    | from, Some to_ ->
      Or_error.error_s
        [%message
          "follow cannot change state"
            ~from:(Follow_state.to_string from)
            ~to_:(Follow_state.to_string to_)]
  in
  let follow =
    match algo with
    | None -> follow
    | Some "immediate" -> { follow with algo = None }
    | Some a -> { follow with algo = Some a }
  in
  Ok (replace_follow me follow)
;;

let stop_follow me ~id =
  let%bind.Or_error follow = find_follow me ~id in
  match follow.state with
  | Stopped -> Or_error.error_s [%message "follow already stopped" id]
  | Running | Paused -> Ok (replace_follow me { follow with state = Stopped })
;;

let add_follow (me : Me.t) (r : Follow_request.t) ~now =
  match Agent_check.of_status me.agent ~now with
  | (Missing | Not_approved | Expired _) as check ->
    Or_error.error_s [%message "approve an agent first" (check : Agent_check.t)]
  | Active ->
    let follow =
      { Follow.id = sprintf "f-%d" (List.length me.follows + 1)
      ; leader = r.leader
      ; scale = r.scale
      ; caps = r.caps
      ; state = Running
      ; created_at = now
      ; pnl = 0.
      ; positions = []
      ; algo = Option.filter r.algo ~f:(fun a -> not (String.equal a "immediate"))
      ; execution = None
      }
    in
    Ok ({ me with follows = me.follows @ [ follow ] }, follow)
;;

let max_validity_ms = 180. *. 86_400_000.

let approve_agent
  (me : Me.t)
  ({ approve_agent = a; signature = _ } : Agent_approval.t)
  ~now
  =
  let status =
    { Agent_status.agent_address = a.agent_address
    ; agent_name = a.agent_name
    ; approved = true
    ; valid_until = Some (now +. max_validity_ms)
    ; builder_fee = Option.bind me.agent ~f:(fun s -> s.builder_fee)
    }
  in
  { me with agent = Some status }, status
;;

let approve_builder_fee
  (me : Me.t)
  ({ approve_builder_fee = b; signature = _ } : Builder_fee_approval.t)
  =
  match me.agent with
  | None -> Or_error.error_string "approve an agent before a builder fee"
  | Some status ->
    let status = { status with builder_fee = Some b.max_fee_rate } in
    Ok ({ me with agent = Some status }, status)
;;
