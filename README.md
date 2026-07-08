# tccx

Reverse-engineering of macOS **TCC** (Transparency, Consent & Control) and **SIP** (System
Integrity Protection), worked out from the `tccd` binary shipped at
`TCC.framework/Support/tccd` (macOS **10.15.6**) and the Ghidra project `tcc` - plus
[`tcc-preapprove`](https://tccx.readthedocs.io/en/latest/tcc-preapprove.html), a small Swift
CLI that implements the findings.

The question the project set out to answer: **can TCC privacy permissions be pre-approved
programmatically?** The short answer, established by reading the binary, is that a genuine
grant can be _constructed_ freely, but it can only be _persisted_ with SIP's filesystem
protection disabled, or handed to the Apple-sanctioned MDM/PPPC channel.

## Documentation

The full TCC & SIP write-up is published with Sphinx at
<https://tccx.readthedocs.io/en/latest/>.

To build it locally: `yarn gen-docs` (output in `docs/_build/html`).

## Tool

`tcc-preapprove` is a SwiftPM executable. Its reference - subcommands, service aliases,
build/run, and privilege notes - is documented at
<https://tccx.readthedocs.io/en/latest/tcc-preapprove.html>.

## Building

Everything runs through `package.json` scripts:

```bash
yarn build          # swift build (debug)
yarn build:release  # swift build -c release
yarn test           # swift test
yarn gen-docs       # build the Sphinx docs into docs/_build/html
swift run tcc-preapprove --help
```

This is **macOS-only** (it links `Security` and `SQLite3`); it will not build on Linux.
