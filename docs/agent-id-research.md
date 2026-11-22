# Agent ID: on-chain integration notes

Verified on 2026-11-22 against BNB Chain mainnet via public RPC.

- Registry: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` (BSC mainnet, chain 56)
- `name()` = "SPACE ID Agent ID", `symbol()` = "AI". ERC-721, soulbound (`Soulbound()` error on transfer).
- Useful reads (selector checked against a live holder):

| Function | Returns | Note |
|---|---|---|
| `balanceOf(address)` | `uint256` | `> 0` means the address holds an Agent ID |
| `handleOf(address)` | `string` | Handle **without** `.ai`; `""` if none (e.g. `wyc1981`) |
| `ownerOfHandle(string)` | `address` | Reverse lookup, `0x0` if unknown |

- Registration is signature-gated (`register(string,uint256,bytes)` + `signer()`), so the registry does not exist on testnet.
  Testnet uses `MockAgentID` with the same three reads plus open `claim(handle)`.
- Not `ERC721Enumerable`: no on-chain listing of all holders.
