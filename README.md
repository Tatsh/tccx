# tccx

Reverse-engineering of macOS **TCC** (Transparency, Consent & Control) and **SIP** (System
Integrity Protection), worked out from the `tccd` binary shipped at
`TCC.framework/Support/tccd` (macOS **10.15.6**) and the Ghidra project `tcc` - plus
[`tcc-preapprove`](Sources/README.md), a small Swift CLI that implements the findings.

The question the project set out to answer: **can TCC privacy permissions be pre-approved
programmatically?** The short answer, established by reading the binary,
is that a genuine grant can be _constructed_ freely, but it can only be _persisted_ with
SIP's filesystem protection disabled, or handed to the Apple-sanctioned MDM/PPPC channel.

## Documentation

Start at the docs index, then the overviews:

- **[`docs/README.md`](docs/README.md)** - index, provenance convention, and the tool caveat.

### TCC

- [`docs/tcc-internals.md`](docs/tcc-internals.md) - the `access` table schema,
  `auth_value` / `auth_reason` enums, the `csreq` contract, write-path provenance, the
  pre-approval recipe, and the PPPC/MDM profile path. Verified against the 10.15.6 binary.

### SIP

- [`docs/sip-overview.md`](docs/sip-overview.md) - what SIP is, history, threat model, the
  project's conclusion (read this first).
- [`docs/sip-configuration.md`](docs/sip-configuration.md) - the `csr` flag bitmask,
  `csr-active-config`, `csrutil`, programmatic detection, disable mechanics.
- [`docs/sip-filesystem-protection.md`](docs/sip-filesystem-protection.md) - "rootless":
  the `restricted` flag, the `com.apple.rootless` xattr, storage classes, exemptions.
- [`docs/sip-runtime-protection.md`](docs/sip-runtime-protection.md) - task-port
  protection, kext signing, dtrace, kernel debugging, `DYLD_*` stripping, platform binaries.
- [`docs/sip-apple-silicon-ssv.md`](docs/sip-apple-silicon-ssv.md) - LocalPolicy, `bputil`,
  security levels, the Signed System Volume, 1TR.
- [`docs/sip-and-tcc.md`](docs/sip-and-tcc.md) - synthesis: how SIP gates everything the
  tool tries to do, with repo-verified anchors.

## Tool

`tcc-preapprove` is a SwiftPM executable. Its reference - subcommands, service aliases,
build/run, and privilege notes - lives in **[`Sources/README.md`](Sources/README.md)**.

## Building

A [`Makefile`](Makefile) wraps the common tasks (run `make help` for the full list):

```bash
make build          # swift build (debug)
make release        # swift build -c release
make run ARGS='list --client com.googlecode.iterm2'
```
