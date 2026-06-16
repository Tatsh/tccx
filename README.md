# tcc-preapprove (SwiftPM)

A Swift package built on
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser),
providing four subcommands with real `--help`, validation, and routing.

Built from the `tccd` (macOS 10.15.6) reverse-engineering notes in
[`docs/tcc-internals.md`](docs/tcc-internals.md). For why the direct-DB paths need SIP
disabled — and a full write-up of SIP internals — see the docs index at
[`docs/README.md`](docs/README.md) and the SIP suite
([`docs/sip-overview.md`](docs/sip-overview.md) →
[`docs/sip-and-tcc.md`](docs/sip-and-tcc.md)).

> **Caveat (the project's conclusion).** `list` and `profile` work with no special
> privilege. The direct-DB write paths (`grant`, `revoke`) can build a genuine grant row
> but can only **persist** it with **SIP filesystem protection disabled**
> (`CSR_ALLOW_UNRESTRICTED_FS`) — `TCC.db` is in a SIP storage-class–protected directory
> only `tccd` is entitled to write. The only persist path needing no SIP change is the
> sanctioned **MDM/PPPC profile** (`profile` subcommand). Details:
> [`docs/sip-and-tcc.md`](docs/sip-and-tcc.md).

## Build & run (macOS)

```bash
swift build -c release
.build/release/tcc-preapprove --help

# or run directly:
swift run tcc-preapprove list --client com.googlecode.iterm2
```

## Subcommands

| Command | Purpose | Needs the binary? | Privilege |
|---|---|---|---|
| `grant` (default) | Write an allow row (`csreq` blob; `auth_value=2 auth_reason=3`) | yes | FDA / SIP-off (root for system DB) |
| `revoke` | `DELETE` row(s) — `-p <svc>` or `--all` | no (`--client`) | FDA / SIP-off |
| `list` | Print rows across user/system DBs, decoded | no | read access to TCC.db |
| `profile` | Emit a PPPC `.mobileconfig` (CodeRequirement string) | yes | none |

```bash
swift run tcc-preapprove grant   -a /Applications/iTerm.app -p downloads,documents
swift run tcc-preapprove revoke  --client com.googlecode.iterm2 --all --dry-run
swift run tcc-preapprove list    --client com.googlecode.iterm2
swift run tcc-preapprove profile -a /Applications/iTerm.app -p fda -o tcc.mobileconfig
```

## Service aliases
`downloads`, `documents`, `desktop`, `fda`/`fulldisk`, `accessibility`, `removable`,
`network`, `appbundles`, `developerfiles` — or pass a raw `kTCCService…` name.

## Notes
- Direct-DB subcommands need Full Disk Access or SIP disabled (see the docs §11–12).
- `profile` output should be **signed** before MDM distribution:
  `security cms -S -N "<cert>" -i tcc.mobileconfig -o signed.mobileconfig`, and PPPC only
  takes effect under user-approved MDM / supervision (docs §15).
- This is macOS-only (`Security` + `SQLite3`); it will not build on Linux.
