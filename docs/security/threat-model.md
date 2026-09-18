# DEUSS Threat Model

This document is the current-state in-repo threat model for the DEUSS
bond-contract suite. It documents trust assumptions, privileged actor blast
radii, current on-chain bounds, and required operational controls. The
[operational model](operational-model.md) builds from this baseline.

## Methodology

The model uses **actor-capability analysis** as its spine, cross-checked against an
**invariant-violation matrix**. Actor analysis is the right primary lens because
DEUSS is a closed, permissioned securities system: there is no AMM, no price oracle,
no flash-loan-callable mint path, and no public liquidity pool. The dominant risk is
therefore not on-chain market primitives but a rich set of **privileged role-holders**
plus a handful of **irreversible, one-shot state transitions**.

Threats are tagged with the informal STRIDE categories that apply to a public-ledger
permissioned protocol: **Spoofing**, **Tampering**, **Elevation of privilege**, and
**Denial of service**. Repudiation and information disclosure are largely not
applicable and are not enumerated.

## Assets

Ranked roughly by impact:

1. **Bond ledger integrity** — the per-`tokenId` ERC-6909 balance/supply ledger in
   `DEUSSToken` is the on-chain register of securities holders. Any mint/burn out of
   step with `BondRegistry` accounting, or any unauthorised reassignment of a
   holder's bonds, corrupts the legal record.
2. **Mint authority over bonds** — `DEUSSToken.mint` is `onlyBondRegistry`. Issuing
   supply against an ISIN beyond `maxSupply`, or against a sham issuer, is equivalent
   to printing unbacked securities.
3. **Escrowed bonds in custody** — bonds parked in `EscrowManager`, drainable only
   through the freeze-then-seize ceremony or by compromise of an authorised module.
4. **Upgrade authority** — in-scope protocol contracts are deployed behind local
   OpenZeppelin `UpgradeableBeacon` / `BeaconProxy` pairs. EBSI `ProxyFactory` deploys
   wallet proxies from registered templates, including the registered `CompanyWallet`
   beacon; each kernel implementation sits behind its own `UpgradeableBeacon`.
5. **End-user account control (kernel)** — the root validator/passkey on each
   `Kernel` account controls that user's assets.
6. **Lifecycle reachability and liveness** — reaching terminal `Redeemed`, publishing
   successors, settling or withdrawing escrow. Several irreversible one-shot latches
   can strand these permanently.
7. **Entity/KYC gating integrity** — `EntityRegistry` enable/disable state gates
   issuer, participant, beneficiary, and wallet-scoped flows; corrupting it silently
   opens or closes core eligibility paths.

## Trust boundaries

- **On-chain → off-chain (dominant boundary).** The contracts enforce the *state
  machine*, not the *truth* of payment or eligibility. The off-chain KYC workflow,
  executed on-chain through `ONBOARDING` for entity creation and metadata and through
  `GUARD` for entity/account status, decides who is eligible; the off-chain payment
  rail is only attested on-chain by `PAYMENT_HANDLER`. There is no settlement-currency
  transfer on-chain. This single boundary concentrates most of the protocol's trust.
- **Owner → contract.** Each in-scope bond contract has a single Solady `OwnableRoles`
  owner with batched `grantRoles`/`revokeRoles` (and, on `DEUSSToken`, `pause` and the
  irreversible `protectAddress`). Owner compromise equals total compromise of that
  contract; one address holding every contract's owner is total system compromise.
- **`EntityRegistry` → eligibility-gated flows.** `isAccountEnabled` is read fresh
  where authority depends on a registered entity account, including issuer-authorized
  issuance, marketplace participant settlement/withdrawal paths, seizure beneficiary
  validation, token forced-transfer callers, and wallet/entity-manager authorization.
  Role-only operator actions are contained through role ownership and signer controls,
  not by disabling the operator in `EntityRegistry`.
- **`EscrowManager` → authorised modules.** Only authorised modules may
  `createEscrow`/`withdraw`/`claim`; compromise of a module's type slot moves all
  escrows under that type.
- **`_protectedAddress` (`DEUSSToken`).** An irreversible per-address latch (no
  `unprotectAddress`) that blocks every privileged transfer-out or freeze for that
  address.
- **Wallet ownership epoch (`CompanyWallet`).** Every owner change advances
  `_ownershipEpoch`, instantly invalidating every `PolicyRegistry` mapping keyed by
  the old epoch. A deliberate kill-switch that also creates a race window between an
  admin's grant and an operator's call.
- **One-shot wiring latches.** `DependenciesBase` setters and
  `BondRegistry.setMultiToken` revert if already set; a wrong address at deployment
  strands the contract with no recovery but redeployment.
- **Kernel beacon owner → all accounts.** A single deployer-owned key owns every
  kernel `UpgradeableBeacon`; `upgradeTo` is `onlyOwner`, single-step, and instant.

## Threat actors (blast radius if compromised)

| Actor | Honest capability | If compromised | On-chain bound |
|---|---|---|---|
| External KYC-bound investor/buyer | Act through a `CompanyWallet`; create/accept marketplace offers/deals within entity-type allowlists | Bounded to permissionless marketplace surface and own wallet policy; can strand a seller's deposit via register-then-suspend race; counter-offer entity-type drift | Cannot mint, move another holder's bonds, or reach role-gated functions without an additional role |
| Enabled issuer / `PUBLISHER` actor | Publish, update, issue, and close issuance for bond versions through `BondRegistry` when authorized; issuer path can issue or close issuance for its own stored bond while enabled | Can mint issued supply up to `remainingIssuableSupply`; can prematurely close future issuance for an exact version; a compromised `PUBLISHER` can publish/update/issue within registry constraints | Cannot exceed immutable `maxSupply`; mint path is only through `BondRegistry`; `closeIssuance` only blocks future tranches for the exact version and does not change status or existing supply; issuer account must remain enabled for issuer-authorized paths |
| Permissionless caller | Settle a deal after its dispute window; `Multicall3` | Permissionless "unpaid" resolution after deadline; surplus donation becomes `ADMIN`-sweepable | Reserved escrow stays protected; `PAID` always needs the role |
| Other bond lifecycle roles (`CANCEL`/`CLOSE`/`SUSPEND`/`UNSUSPEND`) | Gate single lifecycle edges | Cancel unpublished versions, suspend/unsuspend issued versions, or close a zero-supply version as `Redeemed` | Bounded to the target lifecycle transition; **no timelock between grant and use** |
| Compliance/custody roles (`BURNER`/`FORCE_TRANSFER_ROLE`/`TOKEN_FREEZER_ROLE`) | Regulatory burns, forced transfers, partial freezes | Burn/reassign/freeze any non-protected holder's bonds | Protected-address check shields `EscrowManager` and any protected address; `FORCE_TRANSFER_ROLE` should be held by `TimelockController` |
| Marketplace seizure pair (`FREEZE_ROLE` + `SEIZURE_ROLE`) | Incident response: freeze then seize escrowed bonds to a beneficiary | **Highest-impact runtime compound** — full escrow drain for any `tokenId` | Two-flag gate; **neither role alone suffices** — the entire defence |
| Payment/dispute roles (`PAYMENT_HANDLER`/`ARBITRATOR`) | Resolve `PENDING` deals to `PAID`/`UNPAID`; decide disputes | Spoof off-chain truth: pass-settle unpaid, fail-settle paid, decide any dispute | Act only within the deal state machine and dispute windows |
| Entity registry operator (`ONBOARDING`/`GUARD`/`WALLET_TRANSFER`/`ENTITY_TYPE_MANAGER`) | Run the KYC lifecycle, emergency eligibility stops, and account relinking | Enable a sham entity (→ mint authority); disable or re-enable entities/accounts incorrectly; relink/remove accounts incorrectly; entity-authority can self-perpetuate its managers | `isAccountEnabled` re-read fresh on every consuming call; current `GUARD` role controls both disable and re-enable; `WALLET_TRANSFER` should be multisig-controlled and timelocked where viable |
| Per-contract owner/deployer (intended `TimelockController`) | Hold owner across contracts; grant/revoke roles; `pause`; `protectAddress` | **Total.** Owner grants every role; EBSI beacon control replaces contract logic | Weak unless production ownership is handed to multisig-governed timelock execution; operational functions are role/owner-gated and default testnet bootstrap settings are not launch-ready |
| Kernel deployer-owner (beacon owner) | Deploy/upgrade every kernel implementation | **Total over every end-user account** — one key upgrades every beacon instantly | **None on-chain** — the upgrade authority is itself the trust assumption |
| Kernel account owner / guardians / recovery key | Sign UserOps; guardian approvals; recovery replaces a lost passkey | Bounded by signature-verification correctness | Guardian/recovery storage keyed by `msg.sender`; timelock-enforcer hook delays admin actions |
| EBSI infrastructure & off-chain backend | Atomic proxy deploy/initialise; honest onboarding/payment/bundler | Contracts cannot detect a malicious factory/backend | **None on-chain** — irreducible external-infrastructure trust surface |

## Invariant-violation matrix (selected)

| Invariant | Violation action | Actor | On-chain mitigation |
|---|---|---|---|
| `supply = minted − burned` | Mint/burn out of step with registry | Code bug; only via `BondRegistry` | `mint`/`burn` are `onlyBondRegistry`; ERC-6909 supply checkpoints |
| `maxSupply` immutable after first issuance | Inflate the cap to over-mint | `PUBLISHER`, code bug | `maxSupply` fixed after first issuance |
| `_frozenTokens ≤ balanceOf` | Report transferred tokens as frozen | Code bug | `_beforeTransfer` enforces `amount ≤ balance − frozen` |
| Offer conservation across buckets | Desync buckets to overdraw/strand | Code bug; dispute/seizure paths | Equal-and-opposite updates; conservation deliberately relaxes where units physically exit escrow |
| Seizure needs both offer and deal frozen | Drain escrow to attacker beneficiary | `FREEZE_ROLE` + `SEIZURE_ROLE` | **Two-flag gate; neither role alone suffices** |
| `_protectedAddress` irreversible | Prevent `closeBond` from burning a protected holder's balance | Future `protectAddress` on a bond-holding address | No `unprotect`; only `EscrowManager` retains a freeze+seize+sweep escape |
| Mint only to an enabled issuer | Mint to a disabled/sham issuer | `EntityRegistry` `GUARD`/`ONBOARDING` | Fresh `isAccountEnabled` read on every `issueBond` |
| Delegated authority is epoch-scoped | Use stale wallet permissions after an owner change | Code bug | `_ownershipEpoch` advances on `_setOwner`, wiping all mappings |
| Payment resolution direction (design) | Mark a paid-pending deal `UNPAID` to deny the buyer | Permissionless caller | `PAID` requires `PAYMENT_HANDLER`; **`UNPAID` is permissionless** |
| Kernel beacon upgrade authority | Replace every account/module implementation | Kernel deployer-owner | `onlyOwner`, instant; **no timelock or two-step** |

## Critical risks

The model surfaces five risks whose blast radius is catastrophic and which **no
internal contract invariant bounds without the production ownership, timelock, and
signer controls**. The first should be a hard launch gate. Mitigations are
operationalised in the [operational model](operational-model.md).

1. **Admin and upgrade authority (no on-chain delay inside role checks).** Operational
   functions are immediate role/owner checks; the delay is supplied only by assigning
   owners to `TimelockController`. Upgrade authority lives in local protocol beacons,
   the `CompanyWallet` beacon registered through EBSI templates, relevant EBSI
   admin/template roles or upgrade owners, and kernel beacons, so any single-owner
   instant-upgrade beacon remains a launch blocker. → Hand every state-changing
   protocol owner and protocol/CompanyWallet/kernel beacon owner to a multisig behind a
   **non-zero `TimelockController` delay** before launch, and cover the EBSI
   administration surface in the same governance model.
2. **Compliance and custody single-keys.** `FREEZE_ROLE` + `SEIZURE_ROLE` (escrow
   drain), `BURNER`, and `TOKEN_FREEZER_ROLE` can act instantly if assigned to a single
   operator key, while `FORCE_TRANSFER_ROLE` can reassign holder balances. → Keep
   emergency freeze/disable paths fast, but **split freeze from seizure across separate
   signers/services**, put seizure and `FORCE_TRANSFER_ROLE` under governance/timelock,
   and require reviewed approval for unfreeze/re-enable because the current roles do not
   split those directions in code.
3. **Entity/KYC operator integrity.** `ONBOARDING`/`GUARD` can enable a sham entity,
   disable legitimate ones, or re-enable a sanctioned/compromised account; the
   entity-authority address can self-perpetuate its managers. → Keep `ONBOARDING`
   isolated behind the approved off-chain KYC workflow, keep `GUARD` available for fast
   containment, keep `WALLET_TRANSFER` multisig-controlled and timelocked where viable,
   reconcile against the KYC source, and define an authority-rotation procedure a single
   revocation cannot be circumvented by.
4. **Payment-handler integrity (on-chain ↔ off-chain bridge).** `PAYMENT_HANDLER`
   translates off-chain outcomes into settlement; mis-attestation moves bonds without
   payment or strands a paid buyer, and the "unpaid" direction is reachable
   permissionlessly. → Isolate and harden the payment signer/service, reconcile every
   resolution, consider gating the permissionless "unpaid" path behind the role.
5. **Kernel beacon owner (global account takeover).** A single key can instantly
   replace the code of every end-user account. → Same multisig + non-zero-timelock
   launch gate, applied to every kernel beacon.

## Residual risk and accepted assumptions

The contracts can preserve their internal accounting/lifecycle invariants but cannot,
by design, defend boundaries explicitly delegated to off-chain actors. These are
**accepted assumptions**, not defects:

- **KYC and eligibility truth** — which entities exist and are enabled is decided
  off-chain; the chain enforces the gate, not the vetting.
- **Off-chain payment settlement** — payment is settled off-chain and only attested
  on-chain via `PAYMENT_HANDLER`; there is no settlement-currency transfer to verify.
- **EBSI infrastructure and bundler correctness** — proxy deployment, DID/template
  resolution, and bundler liveness are external dependencies.
- **Upstream ZeroDev Kernel and P-256 verifier** — pinned Kernel v3.3 internals and
  the Daimo/EIP-7212 P-256 paths are trusted as-is.

Residual risks the protocol **can** reduce and that this model recommends addressing
before mainnet:

- **Centralised, instant upgrade and role authority** — the `TimelockController`
  handoff with a non-zero delay and a multisig signer set should be a launch gate.
- **Chain-fork view divergence** — the vendored `Multicall3` environment-dependent
  views should be re-validated on the deployed BESU/EBSI chain.

## Related documentation

- [Operational model](operational-model.md) — production governance, role matrix,
  monitoring, incident response, and launch gates.
- [Roles overview](../roles.md)
- [Deployment guide](../deployment.md)
- [`TimelockController`](../governance/TimelockController.md)
