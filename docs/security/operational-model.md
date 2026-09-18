# DEUSS Operational Model

This document describes the **recommended operational model** for running the DEUSS
smart contracts in production. It is operator-facing: it explains how the protocol
should be administered after deployment — ownership, governance, role assignment,
custody operations, monitoring, incident response, and launch gates.

It is the operational counterpart to the [threat model](threat-model.md), which is the
current-state risk baseline for the contracts and their operating assumptions. DEUSS is
a closed, permissioned securities system: it has no AMM, oracle, or public liquidity
pool, so its dominant risks are **operational** — privileged roles, upgrade authority,
custody controls, KYC/entity integrity, and the on-chain↔off-chain payment bridge. This
document exists to make those risks manageable in production.

> **Wallet operational modes** (Direct-Owned vs. Root-Controlled Subwallet) for broker
> and custodian `CompanyWallet` fleets are documented separately in
> [wallet operational modes](wallet-operational-modes.md). This document covers the
> protocol-wide governance and role model.

## How to read this document: control layers

Every control below belongs to exactly one of four layers. Keeping them distinct is the
core discipline of this model: a control assumed to be enforced on-chain that is in fact
an operational runbook step is a latent incident.

| Layer | Meaning | Who guarantees it |
|---|---|---|
| **Contract-enforced** | The bytecode enforces it on every call; cannot be bypassed by an operator. | The deployed contract code. |
| **Deployment-time** | Set once at deploy/bootstrap and then immutable or owner-gated (owners, wiring latches, protected addresses, timelock delay). | Deployment scripts + the launch gate. |
| **Operational / runbook** | A procedure operators must follow; the chain does **not** enforce it (separation of signers, reconciliation, multi-party ceremonies). | The operating organisation. |
| **Accepted trust assumption** | A boundary delegated to off-chain actors that the chain cannot defend by design (KYC truth, payment truth, EBSI/bundler, upstream kernel). | Explicitly accepted; not a defect. |

Each section tags its controls with these layers.

---

## 1. Governance and ownership model

### Expected ownership

- Every state-changing protocol proxy and beacon — `BondRegistry`, `EntityRegistry`,
  `PolicyRegistry`, `DEUSSToken`, `Marketplace`, `OrderbookMarketplace`,
  `AssetManager`, `EscrowManager`, `WalletFactory`, `MarketplaceLens`, and the
  `CompanyWallet` beacon — should be **owned by the `TimelockController`** after
  bootstrap. *(Deployment-time)*
- The `TimelockController`'s `PROPOSER_ROLE`/`EXECUTOR_ROLE`/`CANCELLER_ROLE` should
  be held by a **multisig**, not a single EOA. The `DEFAULT_ADMIN_ROLE` of the timelock
  is the timelock proxy itself plus the timelock admin; the admin key must be retired or
  multisig-held after setup. *(Operational/runbook)*
- The protocol contracts use local OpenZeppelin `UpgradeableBeacon` / `BeaconProxy`
  pairs. EBSI is wallet proxy/template infrastructure: its `ProxyFactory` deploys
  wallet proxies from registered templates, including the registered `CompanyWallet`
  beacon. Production governance must therefore cover the protocol beacons, the
  `CompanyWallet` beacon, relevant EBSI admin/template roles or upgrade owners, and
  every kernel `UpgradeableBeacon`. A single-owner instant-upgrade beacon is the largest
  residual risk until that handoff is complete.
  *(Deployment-time + operational)*

### Multisig + non-zero timelock — mandatory for production

> **Production warning.** `TIMELOCK_MIN_DELAY=0` makes `schedule` and `execute`
> callable in the same transaction, which **defeats the timelock entirely**. Zero delay
> is for testnet and local development only. A production deployment with a zero-delay
> timelock, or with owners still on the deployer EOA, is **not launch-ready**.

- Production default is `TIMELOCK_CONTROLLER_MIN_DELAY = 1 day` (see
  [`TimelockController`](../governance/TimelockController.md)). Choose a delay long
  enough to detect and respond to a malicious scheduled operation (review window). A
  longer delay buys more upgrade-review time at the cost of slower emergency response —
  size it against your incident-response capacity, not below it. *(Deployment-time)*
- The timelock is the **only** thing standing between an owner-key compromise and total
  contract compromise. Operational functions are role/owner-gated; they do not impose
  their own multisig delay. Wiring the timelock as owner is what closes that gap.
  *(Deployment-time)*

### Upgrade scheduling and execution

1. A proposer (multisig) **schedules** the upgrade/role change on the
   `TimelockController` with the production delay.
2. During the delay window, monitoring surfaces the scheduled operation; reviewers
   verify the target, calldata, and new implementation hash against the change request.
3. After the delay, an executor (multisig) **executes**. A `CANCELLER_ROLE` holder can
   cancel a pending operation if review fails.
4. Beacon upgrades take effect for **all** proxies/accounts behind that beacon at once —
   review the new implementation as if every instance is upgrading simultaneously,
   because it is.

---

## 2. Role assignment model

DEUSS roles are Solady `OwnableRoles` bitmaps, granted/revoked by each contract's owner
(the timelock in production). Central role warning: **a role grant is usable
immediately once it exists, and the bootstrap default grants broad role bundles to a
single admin actor for non-seizure day-to-day operations.** Bootstrap keeps seizure and
force-transfer authority on the timelock, but production must still redistribute the
remaining operational bundle.

### Principles

- **No single EOA holds all roles.** The bootstrap convenience grant (one admin actor
  receiving `ADMIN | PAYMENT_HANDLER | ARBITRATOR | ...`) is acceptable for testnet but
  must be split before launch. *(Operational/runbook)*
- **Governance / asset-moving / account-relinking roles** go through multisig/timelock
  governance. These are roles that change system structure, upgrade code, grant roles,
  seize or forcibly move assets, relink accounts between entities, or perform
  exceptional recovery.
- **Fast containment roles** such as marketplace/orderbook `FREEZE_ROLE`,
  `DEUSSToken.TOKEN_FREEZER_ROLE`, and `EntityRegistry.GUARD` must be available through a
  monitored emergency response path. They should not depend on a long timelock when the
  required action is to stop suspected abuse or sanctioned-entity activity immediately.
- **Operational service roles** such as `ONBOARDING` may be held by a secured onboarding
  signing service when the heavy approval workflow is enforced off-chain. The on-chain
  signer should be narrow, monitored, and revocable; it does not need a per-action
  multisig/timelock ceremony unless the operating organisation chooses that.
- **Signer strength follows role latency and blast radius.** Use multisig/timelock for
  governance and asset-moving actions; use hardened, monitored emergency signers/services
  for containment; use scoped service wallets for high-throughput operational writes.

### Recommended production role matrix

Layer key: **CE** contract-enforced, **DT** deployment-time, **OP** operational.

| Contract | Role | Capability | Recommended holder | Notes |
|---|---|---|---|---|
| `TimelockController` | `PROPOSER`/`EXECUTOR`/`CANCELLER` | Schedule/execute/cancel governed actions | **Governance multisig** | DT/OP. Admin key retired after setup. |
| All protocol contracts | Owner | `grantRoles`/`revokeRoles`, config, `pause`, `protectAddress` | **`TimelockController`** | DT. Owner = total contract authority. |
| `BondRegistry` | `ISSUER_RECOVERY` | Rotate a bond issuer during recovery | **Governance (timelock) only** | CE+OP. Never to operators; already bootstrap-granted to timelock. |
| `BondRegistry` | `PUBLISHER` | Publish/update/issue bonds | Issuance operator (per-org) | Bounded by `maxSupply`; issuer path also self-authorises. |
| `BondRegistry` | `CANCEL`/`CLOSE`/`SUSPEND`/`UNSUSPEND` | Single lifecycle edges | Lifecycle operator | Separate from `PUBLISHER` where feasible. |
| `BondRegistry` | `CURRENCY` | Manage allowed bond currencies | Config operator / governance | Low frequency; treat as governance-leaning. |
| `BondRegistry` | `BURNER` | Third-party `FINAL_SETTLEMENT` burns | Compliance/governance recovery signer | Asset-destructive action; CE shields protected addresses. Separate signer from custody/containment. |
| `BondRegistry` | `SCORING` | Append issuer scoring records | Scoring operator | Append-only; low blast radius. |
| `DEUSSToken` | `TOKEN_FREEZER_ROLE` | Freeze/unfreeze balances | Emergency compliance containment signer/service | Fast containment path; cannot freeze `EscrowManager` (protected). Current role also unfreezes, so unfreeze is a reviewed recovery action. |
| `DEUSSToken` | `FORCE_TRANSFER_ROLE` | Reassign non-protected holdings | **`TimelockController`** | Asset-moving recovery action. Bootstrap grants this role to the timelock and registers the timelock as an enabled `EntityRegistry` account so calls can pass. Execute through governed timelock review, not an operator key. |
| `Marketplace`/`Orderbook` | `FREEZE_ROLE` | Freeze/unfreeze offers, deals, orders, trades | Emergency custody/compliance signer/service | Fast containment path; **must differ from `SEIZURE_ROLE` holder.** Current contracts use the same role for unfreeze, so unfreeze is a runbook/governance approval, not routine first response. |
| `Marketplace`/`Orderbook` | `SEIZURE_ROLE` | Seize escrow from frozen offers/deals | **Governance / timelock** | Bootstrap grants this role to the timelock. **Must differ from `FREEZE_ROLE` holder.** Full escrow drain if combined; execute only after review. |
| `Marketplace`/`Orderbook` | `PAYMENT_HANDLER` | Attest off-chain payment outcome | Isolated payment signer/service | On-chain proxy of the payment rail; single most trust-bearing operator role. Harden and monitor heavily. |
| `Marketplace`/`Orderbook` | `ARBITRATOR` | Resolve disputes | Dispute operator / governance | Bounded to deals it resolves. |
| `Marketplace` | `INTEREST_DISCOVERY_OPERATOR` | Close expired interests when owner unavailable | Maintenance operator | Distinct from `ADMIN`; no config authority. |
| `Marketplace`/`Orderbook`/`AssetManager`/`EscrowManager`/`BondMarketFilter` | `ADMIN` | Dependency wiring, parameters, allowlists, sweep | **Governance (timelock)** | Configuration authority — governance-only. |
| `EntityRegistry` | `ADMIN_ROLE` | Override entity governance, immediate account registration | **Governance (timelock)** | Override authority — governance-only. |
| `EntityRegistry` | `ONBOARDING` | Register entities, metadata, account role flags | Secured onboarding signing service | Acceptable when off-chain KYC approval is the heavy gate. Keep narrow, monitored, reconciled, and separate from `ADMIN_ROLE`, `GUARD`, and issuance/custody roles. |
| `EntityRegistry` | `GUARD` | Set entity/account status | Emergency compliance containment signer/service | Fast disablement path for sanctions/suspected abuse. Current contracts use the same role for re-enable, so re-enable is a runbook/governance approval. |
| `EntityRegistry` | `WALLET_TRANSFER` | Relink/remove accounts | **Governance multisig (timelock preferred)** | Account-relinking authority. Use timelock where operational latency allows. Cannot move an account that is its entity's authority or manager. |
| `EntityRegistry` | `ENTITY_TYPE_MANAGER` | Define/freeze entity types | Governance / config | `freezeEntityType` is a one-way latch. |
| `CompanyWallet` | Owner | Arbitrary execution, set policy, advance epoch | Per-entity authority / broker root | See [wallet operational modes](wallet-operational-modes.md). |
| `PolicyRegistry` | Owner | Global module allowlist, role labels | **Governance (timelock)** | Wallet-level admins delegated per wallet. |

### Governance-only roles (never to an operator EOA)

`ISSUER_RECOVERY`, `DEUSSToken.FORCE_TRANSFER_ROLE`, `EntityRegistry.WALLET_TRANSFER`,
every contract `Owner`, every `ADMIN`/`ADMIN_ROLE`, `PolicyRegistry` owner, EBSI/kernel
beacon owners. These either grant other roles, move assets, relink accounts, or perform
irreversible/structural actions.

### Fast containment vs. delayed recovery *(operational — load-bearing)*

The freeze→seize ceremony is the **entire defence** against escrow drain:
`seizeOfferEscrow`/`seizeDeal`/`seizeOrder`/`seizeTrade` require the offer/deal/order/
trade to be **frozen first** *(contract-enforced)*. Neither role alone can drain escrow.

- Hold `FREEZE_ROLE` and `SEIZURE_ROLE` under **separate signers/services** with
  different operational control.
- Keep `FREEZE_ROLE` and `EntityRegistry.GUARD` reachable through a rapid-response
  emergency process for sanctions hits, fraud signals, compromised owners, or other
  off-chain monitoring alerts. First-response containment should freeze market positions
  and disable affected entity/accounts quickly.
- Put `SEIZURE_ROLE` under governance / timelock. Seizure moves assets and should not be
  available to the same actor that performs the first freeze.
- Current contracts do **not** split freeze from unfreeze, or disable from re-enable:
  `FREEZE_ROLE` can pass `false` to unfreeze, and `GUARD` can set enabled statuses. Until
  those roles are split in code, unfreeze and re-enable must be controlled by runbook
  approval, monitoring, and signer procedures around the same on-chain role.
- Require a **multi-party freeze-then-seize procedure**: a freeze is raised by one
  signer/team and the subsequent seizure approved by a different signer/team after
  review (see §3).
- Granting both roles to the same key collapses the two-flag gate into a single-key
  escrow drain — the highest-impact runtime compromise in the threat model.

---

## 3. Marketplace and custody operations

### Freeze vs. seizure workflow

`FREEZE_ROLE` and `SEIZURE_ROLE` are an intentional two-step:

1. **Freeze** (`setOfferFrozen`/`setDealFrozen`/`setOrderFrozen`/`setTradeFrozen`) —
   reversible containment. Halts market movement and is also the prerequisite for
   seizure. Use it as the first incident-response action; it buys time without moving
   assets and should be reachable fast enough for off-chain alerts such as sanctions,
   fraud, or compromised-owner detection.
2. **Seize** (`seizeOfferEscrow`/`seizeDeal`/`seizeOrder`/`seizeTrade`) — moves escrowed
   bonds to a named beneficiary via `EscrowManager.claim`. **Irreversible movement of
   custody.** Only valid while the target is frozen, and should be a governed recovery
   action.

### Entity/account disablement as containment

For sanctions hits, suspected abuse, or compromised entity owners, `EntityRegistry.GUARD`
is the fast eligibility-stop path: `setEntityStatus` and `setAccountStatus` can disable
the entity or account that downstream issuer, participant, beneficiary, and wallet flows
read through `isAccountEnabled`.

Current contracts do not split disable from re-enable. Treat disablement as emergency
containment, and treat re-enable as a reviewed recovery decision under the same runbook
discipline as unfreezing.

### Required approvals/checks before seizure *(operational)*

- A documented incident or legal/regulatory basis, recorded with the on-chain `reason`.
- Confirmation the target is correctly frozen and identified (right offer/deal id,
  right `tokenId`, right beneficiary).
- **Second-signer approval** distinct from the freezer, per §2 separation.
- Beneficiary address verified against the recovery/custody destination.
- Confirmation that any required unfreeze or entity/account re-enable step is separately
  approved and not bundled into the seizure decision.

### Stuck escrow, disabled accounts, failed payment, dispute, recovery

- **Stranded seller deposit (register-then-suspend race).** An offer registered against
  a bond that is then suspended locks the deposit; recovery is only via **freeze +
  seize** to the rightful party. Treat as a runbook case, not an automatic refund.
- **Disabled account holding escrow.** `INTEREST_DISCOVERY_OPERATOR` can close expired
  interests / cancel expired failed interest-discovery offers when the owner is
  unavailable and the owner account is enabled to receive withdrawals. For other stuck
  states, use the freeze→seize path to a verified beneficiary.
- **Failed/late payment.** After the payment deadline a `PENDING` deal can transition to
  `UNPAID`; units return from `inDeals` to `available` at `settleDeal`. See §4 for the
  permissionless `UNPAID` caveat.
- **Disputes.** `ARBITRATOR` resolves `IN_DISPUTE` deals within the dispute buffer
  window; it cannot move escrow outside the deal it is resolving *(contract-enforced)*.
- **Surplus escrow.** Permissionless `DEUSSToken` transfers into `EscrowManager` inflate
  only the `ADMIN`-sweepable surplus; reserved escrow stays capped and protected
  *(contract-enforced)*. Sweeps are an `ADMIN` (governance) action.

---

## 4. Payment-handler operational model

The marketplace settles payment **off-chain** and only attests the outcome on-chain via
`PAYMENT_HANDLER`. There is no settlement-currency transfer on-chain.

- **Accepted assumption.** `PAYMENT_HANDLER` honesty is an explicit protocol trust
  assumption. A compromised handler can pass-settle unpaid deals (buyer gets bonds with
  no payment) or fail-settle paid deals (buyer loses bonds they paid for).
- **Off-chain reconciliation is mandatory** *(operational)*. Every `PAID`/`UNPAID`
  resolution must be reconciled against the off-chain payment ledger. Mis-attestation is
  only detectable off-chain.
- **Permissionless `UNPAID` path.** `markTradeUnpaid` / unpaid resolution requires only
  that the deal be `PENDING` with its `paymentDeadline` already passed — **no role**.
  This means any caller can fail a still-`PENDING` deal after the deadline, denying a
  buyer whose off-chain payment was not yet attested. `PAID` always requires the role.
  - **Accepted today:** the permissionless `UNPAID` direction is accepted, mitigated by
    EBSI having no public mempool to front-run and by the deadline precondition.
  - **Required monitoring:** alert on every `UNPAID` resolution and reconcile against
    in-flight off-chain payments to catch a buyer denied between payment and attestation.
    Gating the `UNPAID` path behind the role is a recommended future hardening (out of
    scope here; tracked as a follow-up).
- **Custody:** hold `PAYMENT_HANDLER` in an isolated hardened signer/service account,
  separate from custody, containment, and governance signers.

---

## 5. Entity / KYC operational model

`EntityRegistry` is the cross-cutting eligibility gate for issuer, participant,
beneficiary, and wallet-scoped flows. `isAccountEnabled` is read fresh where
authority depends on a registered entity account, including issuer-authorized
bond issuance/burn paths, marketplace participant settlement/withdrawal paths,
beneficiary validation for seizures, token forced-transfer callers, and
WalletFactory/entity-manager authorization.

It is **not** a universal containment control for every privileged operator
function. Role-only paths such as payment/dispute resolution, freeze, seizure,
configuration, and lifecycle role actions are contained through role revocation,
owner/timelock control, and operational signer separation, not by disabling the
operator in `EntityRegistry`.

- **Onboarding responsibility.** `ONBOARDING` registers entities and sets onboarding
  metadata/role-flags (account registration itself is `ADMIN_ROLE`); `GUARD` sets
  entity/account status in both directions. Enabling a sham entity grants mint authority
  through the issuer path; disabling legitimate entities is a systemic DoS, while
  re-enabling a sanctioned or compromised account reopens eligibility. `ONBOARDING` may
  be operated by a secured onboarding signing service after off-chain KYC approval; keep it
  separate from `ADMIN_ROLE`, `GUARD`, `PUBLISHER`, and custody roles, reconcile every
  write against the KYC source, and maintain a ready revocation/rotation path.
- **KYC source-of-truth reconciliation** *(operational, accepted assumption upstream)*.
  Which entities exist and are enabled is decided off-chain. Periodically reconcile
  on-chain entity/account state against the off-chain KYC system; the chain enforces the
  gate, not the vetting.
- **Authority and manager rotation.** The entity-authority/entity-manager write path
  (`setEntityAuthority`, `setEntityManager`) is reachable by `ADMIN_ROLE` **and by the
  stored entity-authority address itself** (`registerAccount` is `ADMIN_ROLE`-only). The
  authority can re-grant its own managers and reset the authority — a self-perpetuation
  surface. A single role
  revocation does **not** close it. Define a rotation procedure that explicitly resets
  the authority address and audits managers, not just revokes a role.
- **Stale scoped assignments.** Entity authorities/managers may be unregistered EOAs for
  bootstrap, but once registered as an account the scoped assignment is valid only while
  the account is enabled and linked to the same entity; disabling/removing/transferring
  the account invalidates stale scoped assignments *(contract-enforced)*.
- **Monitoring** entity/account status, authority, and manager changes — see §7.

---

## 6. Deployment and launch gates

Treat the following as **non-negotiable launch gates**. A deployment failing any of
these is not production-ready. (See [deployment guide](../deployment.md) for the
bootstrap flow that sets these.)

- [ ] **Timelock delay is production-safe.** `TIMELOCK_MIN_DELAY` is **non-zero** (≥ the
      `TIMELOCK_CONTROLLER_MIN_DELAY` production default), not the testnet `0`.
- [ ] **Owners transferred to intended governance.** Every state-changing protocol
      proxy/beacon owner listed in the ownership model is the `TimelockController`, and
      the timelock's proposer/executor is the governance **multisig** — not the deployer
      EOA. The timelock admin key is retired.
- [ ] **Protocol, wallet, EBSI, and kernel upgrade surfaces are governed.** Local
      protocol beacons, the `CompanyWallet` beacon, relevant EBSI admin/template roles
      or upgrade owners, and every kernel beacon are under the same multisig + timelock
      authority (single-owner instant-upgrade beacons are not launch-ready).
- [ ] **Read-only utility ownership is accounted for.** `MarketplaceLens` is deployed as
      an upgradeable beacon proxy, but bootstrap does not currently transfer its
      proxy/beacon ownership to the timelock. Production must either transfer
      `MarketplaceLens` utility ownership to governance or explicitly accept and monitor
      the read-only/UI integrity risk.
- [ ] **No single EOA holds all roles.** The bootstrap convenience bundle is split:
      custody, compliance, payment, onboarding, containment, and governance roles live on
      distinct signers/services matched to their latency and blast radius.
- [ ] **Fast containment is operational.** Marketplace/orderbook `FREEZE_ROLE` and
      `EntityRegistry.GUARD` are assigned to monitored emergency response
      signers/services that can act promptly on sanctions or suspicious activity alerts.
- [ ] **`FREEZE_ROLE` and `SEIZURE_ROLE` are on separate signers**, and `SEIZURE_ROLE`
      is governed/timelocked.
- [ ] **`FORCE_TRANSFER_ROLE` is assigned to `TimelockController`.** Forced transfers
      are asset-moving recovery actions and must go through governed timelock review.
      The timelock/execution account is registered and enabled in `EntityRegistry` so
      the token's caller-enabled check can pass.
- [ ] **`WALLET_TRANSFER` is multisig-controlled, with timelock where operationally
      viable.** Account removal/relinking changes entity eligibility and should not be a
      routine operator-key action.
- [ ] **Onboarding signing-service controls are in place.** If `ONBOARDING` is held by a
      secured onboarding signing service, the off-chain approval workflow is enforced
      before the on-chain write, all writes are logged and reconciled, and the role is
      isolated from `ADMIN_ROLE`, `GUARD`, `PUBLISHER`, and custody roles.
- [ ] **Unfreeze and re-enable procedures are governed by runbook approval.** The current
      contracts use the same role for freeze/unfreeze and disable/re-enable, so the
      separation is operational until those roles are split in code.
- [ ] **`ISSUER_RECOVERY` and all `ADMIN`/owner roles** are governance-only.
- [ ] **Deployment manifests match the expected role/owner model.** Reconcile
      `./deployments/{chainId}_{env}_latest.json` and on-chain `owner()`/role bitmaps
      against this matrix before opening to users.
- [ ] **One-shot wiring latches verified.** `setMultiToken`, `_setBondRegistry`/
      `_setEscrowManager`/`_setEntityRegistry`, and protected-address (`EscrowManager`)
      are set to the correct addresses (these revert if re-set; a wrong value strands the
      contract permanently).

---

## 7. Monitoring and alerting

Operational detection is a required compensating control for the instant-action roles.
Alert on the following on-chain events; reconcile against the relevant off-chain source.

| Signal | What to watch | Why |
|---|---|---|
| **Role grants/revokes** | `RolesUpdated` on every protocol contract | Catch unexpected privilege changes; correlate with timelock schedule. |
| **Ownership transfers** | `OwnershipTransferred` on contracts and beacons | Owner = total authority; any transfer is critical. |
| **Beacon / implementation upgrades** | Local protocol and `CompanyWallet` beacon upgrades, relevant EBSI upgrade/admin events, kernel `UpgradeableBeacon` upgrades, and `MarketplaceLens` if retained as an upgradeable utility | Global code replacement; must match a reviewed timelock operation or an explicitly accepted utility-governance exception. |
| **Timelock operations** | `CallScheduled`/`CallExecuted`/`Cancelled` | The review window; scheduled ops must be vetted before the delay elapses. |
| **Payment resolutions** | `PAID`/`UNPAID` transitions (esp. permissionless `UNPAID`) | Reconcile against the off-chain payment ledger (§4). |
| **Freezes / unfreezes / seizures** | `setOfferFrozen`/`setDealFrozen`/orderbook freeze events, especially `frozen=false`, plus seize events + `reason` | Freeze is emergency containment; unfreeze and seizure require reviewed recovery approval. |
| **Forced transfers / burns** | `FORCE_TRANSFER_ROLE` transfers, `FINAL_SETTLEMENT` burns | Compliance actions on holder balances; forced transfers must match a reviewed timelock operation and legal basis. |
| **Token freezes** | `TOKEN_FREEZER_ROLE` freeze/unfreeze | Movement restrictions on holders. |
| **Protected addresses** | `protectAddress` | Irreversible; verify intent. |
| **Entity/account changes** | status, authority, manager, account link changes in `EntityRegistry`, especially re-enables after disablement | KYC-gate integrity; reconcile against the KYC source (§5). |
| **Wallet ownership epoch** | `CompanyWallet` owner changes / epoch advances | Silently invalidates delegated policy; see wallet operational modes. |

---

## 8. Incident response

Each scenario lists the immediate containment action and the recovery path. Maintain
hardened custody for high-blast-radius roles, ready revocation paths, and rehearsed
governance/emergency procedures.

- **Compromised role holder (operator key).** Through the timelock, `revokeRoles` from
  the compromised address and re-grant to a fresh signer. For custody/compliance roles,
  `FREEZE` affected offers/deals and use `GUARD` to disable affected entities/accounts
  first, then revoke. Note role revocation is timelock-delayed in production —
  freeze/disable containment buys the window.
- **Compromised `PAYMENT_HANDLER`.** Revoke the role via timelock; freeze affected
  deals/trades; reconcile all recent `PAID`/`UNPAID` resolutions against the payment
  ledger; reverse erroneous settlements through the freeze→seize path where assets are
  still in escrow. Rotate the payment signer/service and reconcile before restoring it.
- **Compromised entity authority.** Disable the affected entity/accounts via `GUARD`;
  rotate the authority via `setEntityAuthority` (remember the authority can
  self-perpetuate managers — audit and reset managers, do not rely on a single
  revocation); reconcile against KYC.
- **Erroneous freeze/seizure or disablement.** A freeze or disablement is reversible,
  but unfreeze/re-enable should happen only after reviewed recovery approval because the
  current contracts use the same role for both directions. A seizure is **irreversible
  movement**; recovery is an off-chain legal process plus, if the beneficiary is
  controlled, a forced transfer / re-escrow. This is why seizure requires second-signer
  approval (§3).
- **Upgrade key or multisig compromise.** If a beacon/timelock owner key is compromised:
  use `CANCELLER_ROLE` to cancel any pending malicious scheduled operation within the
  delay window; rotate the multisig signer set; if the timelock itself is compromised,
  the non-zero delay is the only window to react — this is why the delay must be sized to
  your response capacity (§1).
- **Kernel beacon / AA governance compromise.** A single kernel beacon owner can replace
  every account's code instantly. Containment depends on having moved the beacon under
  multisig + timelock (the launch gate). With the timelock in place, cancel the malicious
  scheduled upgrade and rotate signers; without it, there is **no on-chain bound** — this
  is the dominant reason §1/§6 treat the beacon handoff as a hard gate.

---

## Accepted trust assumptions (explicitly accepted, not omitted)

These boundaries are delegated to off-chain actors and cannot be defended on-chain by
design. They are accepted, not defects — but they define what monitoring and
reconciliation must compensate for:

- **KYC / eligibility truth** — vetting is off-chain; the chain enforces the gate only.
- **Off-chain payment settlement** — attested via `PAYMENT_HANDLER`; no on-chain
  settlement-currency transfer to verify.
- **EBSI infrastructure and bundler correctness** — proxy deployment, DID/template
  resolution, and bundler liveness are external; a malicious EBSI factory is undetectable
  on-chain.
- **Upstream ZeroDev Kernel and P-256 verifier** — pinned Kernel v3.3 internals and the
  Daimo/EIP-7212 P-256 paths are trusted as-is.
- **Permissionless `UNPAID` resolution** — accepted today (§4), with monitoring; gating
  it behind the role is a recommended future hardening.

Risks the protocol **can** reduce and that this model requires addressing before
mainnet: the `TimelockController` + multisig handoff (§1, §6) and re-validation of the
vendored `Multicall3` environment-dependent views on the deployed BESU/EBSI chain.

## Related documentation

- [Threat model](threat-model.md) — the risk baseline this model operationalises.
- [Roles overview](../roles.md) — full per-contract role reference.
- [Deployment guide](../deployment.md) — bootstrap flow and timelock configuration.
- [Wallet operational modes](wallet-operational-modes.md) — `CompanyWallet` ownership patterns.
- [`TimelockController`](../governance/TimelockController.md) — delay and operation lifecycle.
