# api/ (AGENTS.md)

`Api_types`, the wire contract shared with `hl-copy-api`: request and reply records, the
`Ws_push` frames, `Api_error`, endpoint paths, and the EIP-712 typed data for `approveAgent` and
`approveBuilderFee` in the field order of the Python SDK.

Build from the repository root with `opam exec --switch 5.2.0+ox -- dune build --root .. @hl-copy-web/all`.

Rules that matter here:

- Optional fields accept `null`; records accept unknown fields. Keep both.
- Typed data field lists are a contract with the signer. A change needs a vector check against the
  reference SDK, not only a local expect test.
- Changing a type here is a server change too; see the root `AGENTS.md`.
