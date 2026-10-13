open! Core
open Api_types

let dev path = Yojson.Safe.from_file ("../dev/" ^ path)
let leaders () = (Leaders_response.t_of_yojson (dev "leaders.json")).leaders

let detail address =
  Leader_detail.t_of_yojson (dev ("leaders/" ^ Address.to_string address ^ ".json"))
;;
