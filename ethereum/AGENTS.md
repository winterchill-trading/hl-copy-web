# ethereum/ (AGENTS.md)

`Eip1193`, the generated binding of the EIP-1193 provider (`window.ethereum`), and `Ethereum`, the
deferred wrappers the app calls (`eth_requestAccounts`, `personal_sign`, `eth_signTypedData_v4`,
`eth_chainId`).

- The binding is declared in `eip1193.mli` for gen_js_api; change the declaration there.
- The app replaces the offer's chain id with the wallet's `eth_chainId` before signing, because
  wallets refuse typed data for another chain. Keep that step.
