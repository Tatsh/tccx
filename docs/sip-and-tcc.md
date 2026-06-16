# SIP × TCC

TCC's job is to record and enforce per-app privacy decisions. SIP's job is to make those
records **unforgeable**. The link is concrete and repo-verified:

- The TCC databases live under `…/Application Support/com.apple.TCC/`, directories tagged
  with the **`TCC` storage class** (the `com.apple.rootless` xattr mechanism,
  [`sip-filesystem-protection.md`](sip-filesystem-protection.md) §2).
- `tccd` carries the matching storage-class entitlements - both names are present in the binary:

  ```plain
  com.apple.rootless.storage.TCC
  com.apple.private.security.storage.TCC
  ```

- Therefore the kernel lets **only `tccd`** write `TCC.db`. Not root. Not a re-run of
  `tccd`'s own code under your identity. Only the process whose signature bears the
  entitlement, and only while SIP would otherwise forbid it - that is the whole point.

**TCC integrity is a SIP guarantee.** Remove SIP and you can forge any privacy grant;
keep SIP and even root cannot.

## Two blocks

[`tcc-internals.md`](tcc-internals.md) §11 names "two walls." With the SIP suite we can
state each in its exact mechanism:

| Wall                         | Mechanism                                                                                                                               | Relaxed only by                                                                 |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| **1. Cannot write the file** | SIP filesystem protection: `TCC.db` dir is `TCC`-storage-class protected; the writer lacks `…storage.TCC`                               | `CSR_ALLOW_UNRESTRICTED_FS` off (recovery/1TR) - or be `tccd`                   |
| **2. Cannot be the daemon**  | `tccd`'s XPC verbs are entitlement-gated (`com.apple.private.tcc.manager*`), checked by audit token; you can't get its task port either | Apple signing you can't obtain; task-port protection (`CSR_ALLOW_TASK_FOR_PID`) |

Anchors for wall 2 (from `tccd`): the manager entitlement family
(`com.apple.private.tcc.manager`, `…manager.access.modify`, `…manager.access.delete`, …)
and the audit-token caller check `CheckCallerHasEntitlement` (`0x10003fb16`, see
[`tcc-internals.md`](tcc-internals.md) §11). Wall 1's anchor is the storage-class
entitlement pair above. Both walls are SIP-rooted: one is SIP's filesystem layer, the other
is SIP's runtime/identity layer ([`sip-runtime-protection.md`](sip-runtime-protection.md)).

## Every persistence route, and its SIP requirement

| Route                                         | Touches `TCC.db`?                                             | SIP change needed                                        | Verdict                       |
| --------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------- | ----------------------------- |
| `tcc-preapprove grant` direct write (user DB) | yes                                                           | **`CSR_ALLOW_UNRESTRICTED_FS` off** (or ≤10.15 FDA hole) | Works only SIP-off on 11+     |
| Direct write (system DB)                      | yes                                                           | SIP-off **and root**                                     | One-off / VM base image only  |
| Forge via `tccd` XPC                          | no (tccd writes)                                              | n/a - needs `…tcc.manager*` entitlement you can't hold   | Impossible unprivileged       |
| Inject / task-port `tccd`                     | n/a                                                           | `CSR_ALLOW_TASK_FOR_PID` off + defeat library validation | Impossible while SIP on       |
| **MDM PPPC profile**                          | **no** - `tccd` evaluates it _live_ from `MDMOverrides.plist` | **none**                                                 | The sanctioned, SIP-free path |

The last row is the important one: the **PPPC/MDM** path
([`tcc-internals.md`](tcc-internals.md) §13–15) never writes the protected file, so it
sidesteps SIP entirely - at the cost of requiring user-approved MDM / supervision. It is
the only route that is both unprivileged-friendly _and_ distributable.
