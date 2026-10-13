open! Core
open Api_types

let%expect_test "every mock response decodes and round trips" =
  let check (type a) name of_yojson yojson_of equal =
    let json = Fixtures.dev name in
    let (x : a) = of_yojson json in
    if not (equal x (of_yojson (yojson_of x))) then print_endline ("changed: " ^ name)
  in
  check
    "leaders.json"
    Leaders_response.t_of_yojson
    Leaders_response.yojson_of_t
    Leaders_response.equal;
  check
    "auth-challenge.json"
    Auth.Challenge.t_of_yojson
    Auth.Challenge.yojson_of_t
    Auth.Challenge.equal;
  check
    "session.json"
    Auth.Session.t_of_yojson
    Auth.Session.yojson_of_t
    Auth.Session.equal;
  check
    "agent-offer.json"
    Agent_offer.t_of_yojson
    Agent_offer.yojson_of_t
    Agent_offer.equal;
  check "dashboard.json" Dashboard.t_of_yojson Dashboard.yojson_of_t Dashboard.equal;
  let leaders = Fixtures.leaders () in
  List.iter leaders ~f:(fun (l : Leader.t) ->
    let d = Fixtures.detail l.address in
    assert (Leader.equal d.leader l);
    printf
      "%d %s %5.1f curve=%d fills=%d positions=%d\n"
      l.rank
      (Address.short l.address)
      l.score
      (List.length d.equity_curve)
      (List.length d.fills)
      (List.length d.positions));
  [%expect
    {|
    1 0x620a...97ac  69.2 curve=91 fills=40 positions=2
    2 0x288a...be1b  60.8 curve=91 fills=40 positions=2
    3 0x6efd...12b9  58.5 curve=91 fills=40 positions=2
    4 0xfb03...ec6c  56.3 curve=91 fills=40 positions=1
    5 0x4d57...e478  51.5 curve=91 fills=40 positions=3
    6 0x3b04...8fbf  39.6 curve=91 fills=40 positions=1
    7 0xe7e7...1f41  33.9 curve=91 fills=40 positions=3
    8 0xe725...9a91  25.7 curve=91 fills=40 positions=1
    |}]
;;
