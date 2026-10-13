(lang dune 3.17)

(name hl-copy-web)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/hl-copy-web))

(package
 (name hl-copy-api-types)
 (synopsis "Request and response types shared by the copy-trading API and web app")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  ppx_jane
  ppx_yojson_conv
  yojson))

(package
 (name hl-copy-web)
 (synopsis "Bonsai web frontend for the Hyperliquid copy-trading platform")
 (depends
  (ocaml
   (>= 5.2))
  ; bonsai_web runs ppx_css's css_inliner on %{deps}. Upstream dune 3.24.2, which the
  ; solver otherwise picks on a fresh switch, expands that to "./app.css", the inliner
  ; then writes "include ./app__generated" and bonsai_web fails with "Syntax error".
  ; The ox repository's dune 3.22.2+ox expands it to "app.css".
  (dune
   (< 3.23))
  core
  (hl-copy-api-types
   (= :version))
  bonsai_web
  virtual_dom
  async_kernel
  js_of_ocaml
  js_of_ocaml-ppx
  gen_js_api
  ojs
  ppx_jane
  ppx_yojson_conv
  yojson))
