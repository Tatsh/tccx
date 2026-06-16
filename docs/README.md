# tccx documentation

Reverse-engineering notes and internals for macOS **TCC** (Transparency, Consent &
Control) and **SIP** (System Integrity Protection), produced from the `tccd` binary
(macOS 10.15.6) shipped in this repo at `TCC.framework/Support/tccd` and from the
Ghidra project `tcc`.

## TCC

- [`tcc-internals.md`](tcc-internals.md) - the `access` table schema, `auth_value` /
  `auth_reason` enums, the `csreq` contract, write-path provenance, pre-approval recipe,
  and the PPPC/MDM profile path.

## SIP

See [`sip-overview.md`](sip-overview.md).

| Doc                                                            | Scope                                                                                                                   |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| [`sip-overview.md`](sip-overview.md)                           | What SIP is, history, threat model, and this project's conclusion                                                       |
| [`sip-configuration.md`](sip-configuration.md)                 | The `csr` flag bitmask, `csr-active-config` NVRAM var, `csrutil`, programmatic detection, disable mechanics             |
| [`sip-filesystem-protection.md`](sip-filesystem-protection.md) | "rootless": the `restricted` flag, `com.apple.rootless` xattr, storage classes, `rootless.conf`, exemption entitlements |
| [`sip-runtime-protection.md`](sip-runtime-protection.md)       | Task-port protection, kext signing, dtrace, kernel debugger, `DYLD_*` stripping, platform binaries                      |
| [`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md)         | LocalPolicy, `bputil`, security levels, the Signed System Volume, 1TR                                                   |
| [`sip-and-tcc.md`](sip-and-tcc.md)                             | Synthesis: how SIP gates everything this project's tools try to do                                                      |
