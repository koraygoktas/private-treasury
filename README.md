# Private Treasury — Signature-Based Compliance for Tokenized RWAs

A tokenized treasury bond (RWA) where compliance is **proven, not stored**.

**Live on Sepolia:** [`0xCC1A66e266b563F498dffe1031B0D56Cd6a704A1`](https://sepolia.etherscan.io/address/0xCC1A66e266b563F498dffe1031B0D56Cd6a704A1#code) — source verified on Etherscan.

## The idea

Most "compliant" security tokens keep a permanent on-chain whitelist:
`mapping(address => bool) public isWhitelisted`. It works, but it means
anyone can read the chain and see exactly who passed KYC — a permanent,
public list of verified identities tied to wallet addresses forever.

`PrivateTreasury` does it differently. There is **no whitelist mapping at
all**. Standard `transfer`/`transferFrom` are disabled outright. To
mint or receive tokens, you present a signed, time-boxed **attestation**
from a trusted off-chain compliance authority (the `attestor`) alongside
your transaction:

```solidity
function transferWithAttestation(
    address to,
    uint256 amount,
    Attestation calldata att,
    bytes calldata signature
) external returns (bool);
```

The contract checks the signature and the expiry on the spot, then
forgets it. Nothing about who is compliant is ever written to storage —
only a hash of *revoked* attestations is kept, so a specific credential
can be pulled if needed. The `attestor` never touches the chain to
"add" someone: issuing a credential is just signing a message off-chain
(EIP-712), for free, in milliseconds.

## Why this matters

- **No public identity graph.** A whitelist mapping is a permanent,
  queryable list of "who is KYC'd" tied to real wallets. This design
  never writes that list on-chain.
- **Attestations expire.** A credential is only valid for the window it
  was issued for — no stale, forever-valid compliance status.
- **Instant revocation without cleanup.** Revoking one credential is one
  `mapping` write (`revokedAttestations[hash] = true`), not rewriting a
  whitelist.
- **The attestor is gas-free and has no write access.** Compliance
  issuance is an off-chain signing service, not an on-chain admin
  function — it can't be front-run, and a compromised attestor key
  can't mint funds, only sign attestations that still require a real
  `owner`-triggered `issue()` or a real transfer to matter.

## How compliance verification works (EIP-712)

```solidity
struct Attestation {
    address investor;
    uint64  expiry;
    bytes32 jurisdiction;
    uint256 nonce;
}
```

1. The attestor signs `Attestation` off-chain using EIP-712 typed data
   (domain-separated, so a signature can't be replayed against a
   different contract or chain).
2. The caller submits the attestation + signature alongside their
   `issue()` / `transferWithAttestation()` call.
3. The contract recomputes the EIP-712 digest, recovers the signer via
   `ecrecover`, and checks: signer == current `attestor`, `investor`
   matches the actual recipient, `block.timestamp <= expiry`, and the
   attestation hash isn't in `revokedAttestations`.

No OpenZeppelin dependency — the EIP-712 domain separator, struct hash,
and signature recovery (via inline assembly reading `r`/`s`/`v` from
`bytes calldata`) are all hand-rolled in `src/PrivateTreasury.sol`.

## Contract surface

| Function | Access | Purpose |
|---|---|---|
| `issue(investor, amount, attestation, signature)` | `onlyOwner` | Mint new bonds to a compliant investor |
| `transferWithAttestation(to, amount, attestation, signature)` | anyone holding a balance | Compliance-gated transfer |
| `revokeAttestation(hash)` | `onlyAttestor` | Kill a specific credential before its expiry |
| `setAttestor(address)` | `onlyOwner` | Rotate the compliance signer |
| `transferOwnership(address)` | `onlyOwner` | Rotate the issuer |
| `transfer` / `transferFrom` | — | Disabled, always revert (`DirectTransferDisabled`) |

## Web demo

`web/index.html` is a single-file, dependency-light (ethers.js via CDN)
interactive demo — no build step, just open it in a browser with
MetaMask installed. It walks through the entire compliance flow:

1. **Connect** your wallet and load the deployed contract by address.
2. **Sign an attestation** — simulates the off-chain attestor issuing a
   time-boxed credential for a specific investor address, entirely
   client-side via EIP-712 typed-data signing.
3. **Issue (mint)** new bonds to that investor as the contract owner.
4. **Transfer with attestation** to move tokens to a compliant
   recipient — and watch it get live-decoded, human-readable revert
   reasons (`AttestationExpired`, `AttestationInvestorMismatch`,
   `InvalidSignature`, etc.) when the attestation doesn't check out.

### Running it locally

```bash
# terminal 1
anvil

# terminal 2 — deploy (see "Deploy" below), then serve the demo, e.g.:
npx http-server web -p 5500
```

In MetaMask, add a network pointing at `http://127.0.0.1:8545`
(chain ID `31337`) and import one of anvil's printed test accounts.
Paste the deployed contract address into the page and go.

### Security note

The "attestor private key" field in the demo exists purely to simulate
off-chain signing in a self-contained page — in a real deployment, the
attestor never runs in a browser. That signing step lives behind an
API/service backed by proper key custody (HSM, cloud KMS, etc. — see
this author's companion project,
[`secure-key-managment`](https://github.com/koraygoktas/secure-key-managment),
for exactly that problem). Only ever paste a local/testnet throwaway
key into this demo — the input is masked, but it is still a demo tool,
not a wallet.

## Project structure

```
private-treasury/
├── src/
│   └── PrivateTreasury.sol       # the contract
├── test/
│   └── PrivateTreasury.t.sol     # 14 tests: issuance, transfer, revocation, admin
├── script/
│   └── Deploy.s.sol              # deploy script (reads OWNER_ADDRESS / ATTESTOR_ADDRESS)
├── web/
│   └── index.html                # interactive demo (ethers.js, no build step)
├── .env.example
└── README.md
```

## Setup

```bash
git clone https://github.com/koraygoktas/private-treasury.git
cd private-treasury
forge install
cp .env.example .env   # fill in OWNER_ADDRESS / ATTESTOR_ADDRESS / SEPOLIA_RPC_URL
```

## Test

```bash
forge test -vv
```

14 tests covering: valid/invalid issuance, expired/revoked/mismatched
attestations, bad signatures, attestor rotation invalidating old
signatures, transfer with a fresh attestation, insufficient balance,
and confirming direct `transfer`/`transferFrom` are hard-disabled.

## Deploy (local)

```bash
# terminal 1
anvil

# terminal 2
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <anvil-account-0-private-key> \
  --sender <anvil-account-0-address> \
  --broadcast -vvvv
```

## Known limitations (by design, for a demo)

- The web demo signs attestations client-side for simplicity — a real
  system moves that behind an authenticated backend service.
- No per-attestation "used" flag: the same signed attestation can be
  reused for multiple calls until it expires or is explicitly revoked.
  Add a nonce-consumption mapping if single-use semantics are required.
- Single `attestor` role — production systems would likely support
  multiple attestors/jurisdictions and role-based revocation.

## License

MIT