# tccx documentation

Reverse-engineering notes and internals for macOS **TCC** (Transparency, Consent &
Control) and **SIP** (System Integrity Protection), produced from the `tccd` binary
(macOS 10.15.6) shipped in this repo at `TCC.framework/Support/tccd` and from the
Ghidra project `tcc` (ghidra-mcp port **8090**).

## TCC

- [`tcc-internals.md`](tcc-internals.md) — the `access` table schema, `auth_value` /
  `auth_reason` enums, the `csreq` contract, write-path provenance, pre-approval recipe,
  and the PPPC/MDM profile path. Everything verified against the 10.15.6 binary.

## SIP

A focused suite — read [`sip-overview.md`](sip-overview.md) first; it links the rest.

| Doc | Scope |
|---|---|
| [`sip-overview.md`](sip-overview.md) | What SIP is, history, threat model, and this project's conclusion |
| [`sip-configuration.md`](sip-configuration.md) | The `csr` flag bitmask, `csr-active-config` NVRAM var, `csrutil`, programmatic detection, disable mechanics |
| [`sip-filesystem-protection.md`](sip-filesystem-protection.md) | "rootless": the `restricted` flag, `com.apple.rootless` xattr, storage classes, `rootless.conf`, exemption entitlements |
| [`sip-runtime-protection.md`](sip-runtime-protection.md) | Task-port protection, kext signing, dtrace, kernel debugger, `DYLD_*` stripping, platform binaries |
| [`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md) | LocalPolicy, `bputil`, security levels, the Signed System Volume, 1TR |
| [`sip-and-tcc.md`](sip-and-tcc.md) | Synthesis: how SIP gates everything this project's tools try to do |

## Provenance & honesty convention

These docs mix two kinds of claim, and label them so you never have to guess:

- **[verified]** — read directly out of this repo's `tccd` binary or the Ghidra project.
  An address (`0x…`) or an exact string is cited. For 10.15.6, the binary wins over any
  online table.
- Unmarked prose — **established, documented macOS internals** (XNU headers, Apple
  Platform Security guide, public research). Accurate to the best of current knowledge,
  but *not* freshly reverse-engineered here. Where a fact is version-specific or I could
  not confirm it from primary sources, it says so.

## The tools, and their one caveat

The `tcc-preapprove` CLI (repo root, see [`../README.md`](../README.md)) is **kept**. Its
read-only and profile-generating paths (`list`, `profile`) need no special privilege. But
its **direct-DB write paths (`grant`, `revoke`) cannot *persist* anything unless SIP's
filesystem protection is disabled** (or, on ≤10.15 only, the writer holds Full Disk
Access) — because `TCC.db` lives under a SIP storage-class–protected directory that only
`tccd` is entitled to write. That is the whole reason the SIP suite is the project's
capstone: the tooling is correct, but the OS reserves the persist step for SIP-off or for
the sanctioned MDM/PPPC channel. See [`sip-and-tcc.md`](sip-and-tcc.md).
