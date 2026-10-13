open! Core
open! Async_kernel

type t = Eip1193.t

let detect = Eip1193.get

let error_of_js (e : Ojs.t) =
  let field name = Ojs.option_of_js Fn.id (Ojs.get_prop_ascii e name) in
  let message =
    match field "message" with
    | Some m -> Ojs.string_of_js m
    | None -> "wallet request failed"
  in
  match field "code" with
  | Some code -> Error.of_string (sprintf "%s (code %g)" message (Ojs.float_of_js code))
  | None -> Error.of_string message
;;

let of_promise promise =
  let ivar = Ivar.create () in
  let on_ok = Ojs.fun_to_js 1 (fun v -> Ivar.fill_if_empty ivar (Ok v)) in
  let on_error = Ojs.fun_to_js 1 (fun e -> Ivar.fill_if_empty ivar (Error (error_of_js e))) in
  ignore (Ojs.call promise "then" [| on_ok; on_error |] : Ojs.t);
  Ivar.read ivar
;;

let request t ~method_ ~params =
  match Or_error.try_with (fun () -> Eip1193.request t { method_; params }) with
  | Error _ as e -> return e
  | Ok promise -> of_promise promise
;;

let string_result d = Deferred.Or_error.map d ~f:Ojs.string_of_js

let request_accounts t =
  request t ~method_:"eth_requestAccounts" ~params:[]
  |> Deferred.Or_error.map ~f:(Ojs.list_of_js Ojs.string_of_js)
;;

let chain_id t = request t ~method_:"eth_chainId" ~params:[] |> string_result

let hex_of_utf8 s = "0x" ^ String.concat_map s ~f:(fun c -> sprintf "%02x" (Char.to_int c))

let personal_sign t ~address ~message =
  request
    t
    ~method_:"personal_sign"
    ~params:[ Ojs.string_to_js (hex_of_utf8 message); Ojs.string_to_js address ]
  |> string_result
;;

let sign_typed_data_v4 t ~address ~typed_data =
  request
    t
    ~method_:"eth_signTypedData_v4"
    ~params:[ Ojs.string_to_js address; Ojs.string_to_js typed_data ]
  |> string_result
;;
