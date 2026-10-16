open! Core
open Api_types
open Copy_web_model

let me () = Me.t_of_yojson (Fixtures.dev "me.json")
let offer () = Agent_offer.t_of_yojson (Fixtures.dev "agent-offer.json")

(* The fixture snapshot is 2025-10-12 08:30 UTC; its agent is valid for one more day. *)
let snapshot = 1_760_257_800_000.
let a_week_later = snapshot +. (7. *. 86_400_000.)

let states (me : Me.t) =
  List.map me.follows ~f:(fun f -> f.id ^ ":" ^ Follow_state.to_string f.state)
  |> String.concat ~sep:" "
  |> print_endline
;;

let%expect_test "agent check" =
  let agent = (me ()).agent in
  List.iter [ snapshot; a_week_later ] ~f:(fun now ->
    let check = Agent_check.of_status agent ~now in
    print_s [%sexp (check : Agent_check.t), (Agent_check.needs_approval check : bool)];
    print_endline (Agent_check.describe check));
  print_s [%sexp (Agent_check.of_status None ~now:snapshot : Agent_check.t)];
  [%expect
    {|
    (Active false)
    Your trading agent is approved.
    ((Expired 1760344200000) true)
    Your trading agent's approval expired on 2025-10-13 08:30 UTC. Approve a new agent to keep copying.
    Missing
    |}]
;;

let%expect_test "pause, resume and stop" =
  let me = ref (me ()) in
  states !me;
  let show = function
    | Ok (me', (_ : Follow.t)) ->
      me := me';
      states !me
    | Error e -> print_s [%sexp (e : Error.t)]
  in
  show (Mock_state.update_follow !me ~id:"f-1" { state = Some Paused; algo = None });
  show (Mock_state.update_follow !me ~id:"f-1" { state = Some Paused; algo = None });
  show (Mock_state.update_follow !me ~id:"f-2" { state = Some Running; algo = None });
  show (Mock_state.stop_follow !me ~id:"f-1");
  show (Mock_state.update_follow !me ~id:"f-1" { state = Some Running; algo = None });
  show (Mock_state.stop_follow !me ~id:"f-9");
  [%expect
    {|
    f-1:running f-2:paused
    f-1:paused f-2:paused
    ("follow cannot change state" (from paused) (to_ paused))
    f-1:paused f-2:running
    f-1:stopped f-2:running
    ("follow is stopped" f-1)
    ("no such follow" f-9)
    |}]
;;

let%expect_test "following needs an active agent" =
  let leader = (List.hd_exn (Fixtures.leaders ())).address in
  let request = { Follow_request.leader; scale = Multiplier 0.5; caps = Caps.default; algo = None } in
  (match Mock_state.add_follow (me ()) request ~now:a_week_later with
   | Ok _ -> print_endline "followed without an agent"
   | Error e -> print_s [%sexp (e : Error.t)]);
  let offer = offer () in
  let me, status =
    Mock_state.approve_agent
      (me ())
      { approve_agent = offer.approve_agent; signature = "0xsig" }
      ~now:a_week_later
  in
  print_s [%sexp (status : Agent_status.t)];
  let me, follow =
    Mock_state.add_follow me request ~now:a_week_later |> Or_error.ok_exn
  in
  states me;
  print_s [%sexp (follow.id : string), (follow.scale : Scale_mode.t)];
  [%expect
    {|
    ("approve an agent first" (check (Expired 1760344200000)))
    ((agent_address 0xe139fba95d43a8acd9d4f58e7bcedc60e7dab4ee)
     (agent_name hl-copy) (approved true) (valid_until (1776414600000))
     (builder_fee (0.01%)))
    f-1:running f-2:paused f-3:running
    (f-3 (Multiplier 0.5))
    |}]
;;
