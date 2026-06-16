# SIP × TCC — the synthesis (why the tools persist only with SIP off)

> Scope per [`README.md`](README.md): **[verified]** items are read from this repo's
> `tccd` (`TCC.framework/Support/tccd`, 10.15.6) or the Ghidra `tcc` project. This is the
> capstone that ties the SIP suite to [`tcc-internals.md`](tcc-internals.md).

## 1. The dependency, stated precisely

TCC's job is to record and enforce per-app privacy decisions. SIP's job is to make those
records **unforgeable**. The link is concrete and repo-verified:

- The TCC databases live under `…/Application Support/com.apple.TCC/`, directories tagged
  with the **`TCC` storage class** (the `com.apple.rootless` xattr mechanism,
  [`sip-filesystem-protection.md`](sip-filesystem-protection.md) §2).
- **[verified]** `tccd` carries the matching storage-class entitlements — both names are
  present in the binary:
  ```
  com.apple.rootless.storage.TCC
  com.apple.private.security.storage.TCC
  ```
- Therefore the kernel lets **only `tccd`** write `TCC.db`. Not root. Not a re-run of
  `tccd`'s own code under your identity. Only the process whose signature bears the
  entitlement, and only while SIP would otherwise forbid it — that is the whole point.

So: **TCC integrity is a SIP guarantee.** Remove SIP and you can forge any privacy grant;
keep SIP and even root cannot.

## 2. The two walls, refined

[`tcc-internals.md`](tcc-internals.md) §11 names "two walls." With the SIP suite we can
state each in its exact mechanism:

| Wall | Mechanism | Relaxed only by |
|---|---|---|
| **1. Can't write the file** | SIP filesystem protection: `TCC.db` dir is `TCC`-storage-class protected; the writer lacks `…storage.TCC` | `CSR_ALLOW_UNRESTRICTED_FS` off (recovery/1TR) — or be `tccd` |
| **2. Can't be the daemon** | `tccd`'s XPC verbs are entitlement-gated (`com.apple.private.tcc.manager*`), checked by audit token; you can't get its task port either | Apple signing you can't obtain; task-port protection (`CSR_ALLOW_TASK_FOR_PID`) |

**[verified]** anchors for wall 2 (from `tccd`): the manager entitlement family
(`com.apple.private.tcc.manager`, `…manager.access.modify`, `…manager.access.delete`, …)
and the audit-token caller check `CheckCallerHasEntitlement` (`0x10003fb16`, see
[`tcc-internals.md`](tcc-internals.md) §11). Wall 1's anchor is the storage-class
entitlement pair above. Both walls are SIP-rooted: one is SIP's filesystem layer, the other
is SIP's runtime/identity layer ([`sip-runtime-protection.md`](sip-runtime-protection.md)).

## 3. Every persist route, and its SIP requirement

| Route | Touches `TCC.db`? | SIP change needed | Verdict |
|---|---|---|---|
| `tcc-preapprove grant` direct write (user DB) | yes | **`CSR_ALLOW_UNRESTRICTED_FS` off** (or ≤10.15 FDA hole) | Works only SIP-off on 11+ |
| Direct write (system DB) | yes | SIP-off **and root** | One-off / VM base image only |
| Forge via `tccd` XPC | no (tccd writes) | n/a — needs `…tcc.manager*` entitlement you can't hold | Impossible unprivileged |
| Inject / task-port `tccd` | n/a | `CSR_ALLOW_TASK_FOR_PID` off + defeat library validation | Impossible while SIP on |
| **MDM PPPC profile** | **no** — `tccd` evaluates it *live* from `MDMOverrides.plist` | **none** | The sanctioned, SIP-free path |

The last row is the important one: the **PPPC/MDM** path
([`tcc-internals.md`](tcc-internals.md) §13–15) never writes the protected file, so it
sidesteps SIP entirely — at the cost of requiring user-approved MDM / supervision. It is
the only route that is both unprivileged-friendly *and* distributable.

## 4. What the tools should tell the user (UX of the caveat)

The tools are retained. To make the caveat honest and legible at runtime, the direct-DB
write paths should **pre-check SIP and refuse clearly** rather than emit a raw `EPERM`:

```c
#include <sys/csr.h>
if (csr_check(CSR_ALLOW_UNRESTRICTED_FS) != 0) {
    fprintf(stderr,
      "tcc-preapprove: TCC.db is SIP-protected (storage class \"TCC\").\n"
      "  Persisting a grant requires SIP filesystem protection OFF.\n"
      "  Intel:  reboot to Recovery (Cmd-R) -> csrutil disable -> reboot.\n"
      "  Apple Silicon: 1TR (hold power) -> csrutil disable (Reduced Security) -> reboot.\n"
      "  Or use the SIP-free path:  tcc-preapprove profile ...  (MDM/PPPC).\n");
    return EX_NOPERM;
}
```

(Read-only `list` and profile-emitting `profile` need no such gate — they don't write the
protected file.) This turns the project's central finding into a one-line, actionable
error instead of a mysterious failure.

## 5. The closed loop

- **Finding:** writing a TCC grant is gated by SIP — specifically `TCC.db`'s `TCC`
  storage class, which only `tccd`'s entitlement satisfies. **[verified]** from this repo's
  binary.
- **Consequence:** the tools can construct a perfectly genuine row
  ([`tcc-internals.md`](tcc-internals.md) §§5–8) but can only *persist* it with
  `CSR_ALLOW_UNRESTRICTED_FS` cleared (SIP off) — or hand the decision to MDM/PPPC.
- **Deliverable:** this documentation suite, which explains the boundary rather than
  pretending to route around it. The tools stay, the caveat is explicit, and the only
  no-SIP-change persist path (PPPC) is documented end-to-end.

> Honest scope note: the storage-class entitlements, the manager-entitlement family, the
> platform-binary policy strings, and the audit-token caller check are **[verified]** in
> the 10.15.6 `tccd`. The SIP *kernel mechanics* (MACF hooks, SSV sealing, LocalPolicy) are
> documented internals, not re-derived from this binary — see each SIP doc's header. The
> 11+/Apple-Silicon specifics ([`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md)) are
> documented behavior on hardware this Intel binary predates.
