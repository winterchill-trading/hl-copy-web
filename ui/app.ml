open! Core
open! Bonsai_web
open Api_types
open Copy_web_model
module N = Vdom.Node
module A = Vdom.Attr

let nav_link ~current route label =
  let active =
    match (current : Route.t), (route : Route.t) with
    | Leaders, Leaders | (Leader _ | Follow _), Leaders | Dashboard, Dashboard -> true
    | _ -> false
  in
  Widgets.link ~attrs:(if active then [ A.class_ "active" ] else []) route [ N.text label ]
;;

let header ~(backend : Backend.t) ~route ~session ~logout =
  N.header
    ~attrs:[ A.class_ "top" ]
    [ N.div ~attrs:[ A.class_ "brand" ] [ N.text "hl-copy" ]
    ; N.nav [ nav_link ~current:route Leaders "Leaders"; nav_link ~current:route Dashboard "Dashboard" ]
    ; N.span
        ~attrs:[ A.classes [ "badge"; (if backend.is_mock then "mock" else "live") ] ]
        [ N.text backend.description ]
    ; (match session with
       | None ->
         Widgets.link ~attrs:[ A.classes [ "btn"; "primary" ] ] Login [ N.text "Connect wallet" ]
       | Some ((wallet : Wallet.t), (s : Auth.Session.t)) ->
         N.div
           ~attrs:[ A.class_ "account" ]
           [ N.span
               ~attrs:[ A.class_ "mono" ]
               [ N.text
                   (Address.short s.address ^ if Wallet.is_demo wallet then " (demo)" else "")
               ]
           ; Widgets.button ~on_click:logout "Sign out"
           ])
    ]
;;

let component ~(backend : Backend.t) ~route (local_ graph) =
  let open Bonsai.Let_syntax in
  let session, set_session = Bonsai.state_opt graph in
  let login =
    let%map set_session in
    fun wallet s -> set_session (Some (wallet, s))
  in
  let is route_is =
    let%map route in
    route_is route
  in
  let leaders =
    Page_leaders.component
      ~backend
      ~active:
        (is (function
          | Route.Leaders -> true
          | _ -> false))
      graph
  in
  let leader = Page_leader.component ~backend ~route graph in
  let follow = Page_follow.component ~backend ~route ~session graph in
  let dashboard = Page_dashboard.component ~backend ~route ~session graph in
  let login_page = Page_login.component ~backend ~login ~session graph in
  let%map route
  and session
  and set_session
  and leaders
  and leader
  and follow
  and dashboard
  and login_page in
  let page =
    match (route : Route.t) with
    | Leaders -> leaders
    | Leader _ -> leader
    | Follow _ -> follow
    | Dashboard -> dashboard
    | Login -> login_page
  in
  N.div
    ~attrs:[ A.class_ "app" ]
    [ header ~backend ~route ~session ~logout:(set_session None); N.main [ page ] ]
;;
