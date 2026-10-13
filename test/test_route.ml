open! Core
open Copy_web_model

let%expect_test "fragments round trip and fall back to the leaderboard" =
  List.iter
    [ ""
    ; "#"
    ; "#/leaders"
    ; "#/dashboard"
    ; "/login"
    ; "#/leader/0xABCDEF0123456789abcdef0123456789ABCDEF01"
    ; "#/follow/0xabcdef0123456789abcdef0123456789abcdef01/"
    ; "#/leader/not-an-address"
    ; "#/nowhere"
    ]
    ~f:(fun hash ->
      let route = Route.of_hash hash in
      assert (Route.equal route (Route.of_hash (Route.to_hash route)));
      printf "%-50s %s\n" hash (Route.to_hash route));
  [%expect
    {|
                                                       #/leaders
    #                                                  #/leaders
    #/leaders                                          #/leaders
    #/dashboard                                        #/dashboard
    /login                                             #/login
    #/leader/0xABCDEF0123456789abcdef0123456789ABCDEF01 #/leader/0xabcdef0123456789abcdef0123456789abcdef01
    #/follow/0xabcdef0123456789abcdef0123456789abcdef01/ #/follow/0xabcdef0123456789abcdef0123456789abcdef01
    #/leader/not-an-address                            #/leaders
    #/nowhere                                          #/leaders
    |}]
;;
