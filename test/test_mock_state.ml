open! Core
open Api_types
open Copy_web_model

let dashboard () = Dashboard.t_of_yojson (Fixtures.dev "dashboard.json")

let states (d : Dashboard.t) =
  List.map d.follows ~f:(fun f -> f.id ^ ":" ^ Follow_state.to_string f.state)
  |> String.concat ~sep:" "
  |> print_endline
;;

let%expect_test "commands walk the state machine" =
  let d = ref (dashboard ()) in
  states !d;
  List.iter
    [ "f-1", Follow_command.Pause
    ; "f-1", Pause
    ; "f-2", Resume
    ; "f-1", Stop
    ; "f-1", Resume
    ; "f-9", Stop
    ]
    ~f:(fun (id, command) ->
      match Mock_state.apply_command !d ~id command with
      | Ok (d', _) ->
        d := d';
        states !d
      | Error e -> print_s [%sexp (e : Error.t)]);
  [%expect {|
    f-1:running f-2:paused
    f-1:paused f-2:paused
    ("follow cannot do that now" (state paused) (command pause))
    f-1:paused f-2:running
    f-1:stopped f-2:running
    ("follow cannot do that now" (state stopped) (command resume))
    ("no such follow" f-9)
    |}]
;;

let%expect_test "a new follow is appended running" =
  let offer = Agent_offer.t_of_yojson (Fixtures.dev "agent-offer.json") in
  let leader = (List.hd_exn (Fixtures.leaders ())).address in
  let request =
    { Follow_request.leader
    ; scale = Multiplier 0.5
    ; caps = Caps.default
    ; approve_agent = offer.approve_agent
    ; agent_signature = "0xsig"
    ; approve_builder_fee = None
    ; builder_fee_signature = None
    }
  in
  let d, follow = Mock_state.add_follow (dashboard ()) request ~now:1_760_300_000_000. in
  states d;
  print_s [%sexp (follow.id : string), (follow.scale : Scale_mode.t)];
  [%expect {|
    f-1:running f-2:paused f-3:running
    (f-3 (Multiplier 0.5))
    |}]
;;
