# tcc-preapprove

A Swift package built on
[`swift-argument-parser`](https://github.com/apple/swift-argument-parser), providing four
subcommands with real `--help`, validation, and routing.

Built from the `tccd` (macOS 10.15.6) reverse-engineering notes in
[`../docs/tcc-internals.md`](../docs/tcc-internals.md). For _why_ the direct-DB paths need
SIP disabled, and the full SIP write-up, see the docs index
([`../docs/README.md`](../docs/README.md)) and the synthesis
([`../docs/sip-and-tcc.md`](../docs/sip-and-tcc.md)).

> **Caveat.** `list` and `profile` work with no special
> privilege. The direct-DB write paths (`grant`, `revoke`) can build a genuine grant row
> but can only **persist** it with **SIP filesystem protection disabled**
> (`CSR_ALLOW_UNRESTRICTED_FS`) — `TCC.db` lives in a SIP storage-class–protected directory
> only `tccd` is entitled to write. The only persist path needing no SIP change is the
> sanctioned **MDM/PPPC profile** (`profile` subcommand).

## Build & run (macOS)

From the repository root:

```bash
make build                  # or: swift build
make run ARGS='--help'       # or: swift run tcc-preapprove --help

# run a subcommand directly:
swift run tcc-preapprove list --client com.googlecode.iterm2
```

This is **macOS-only** (`Security` + `SQLite3`); it will not build on Linux.

## Subcommands

| Command           | Purpose                                                         | Needs the binary? | Privilege                          |
| ----------------- | --------------------------------------------------------------- | ----------------- | ---------------------------------- |
| `grant` (default) | Write an allow row (`csreq` blob; `auth_value=2 auth_reason=3`) | yes               | FDA / SIP-off (root for system DB) |
| `revoke`          | `DELETE` row(s) — `-p <svc>` or `--all`                         | no (`--client`)   | FDA / SIP-off                      |
| `list`            | Print rows across user/system DBs, decoded                      | no                | read access to TCC.db              |
| `profile`         | Emit a PPPC `.mobileconfig` (CodeRequirement string)            | yes               | none                               |

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

- Direct-DB subcommands need Full Disk Access or SIP disabled (see
  [`../docs/sip-and-tcc.md`](../docs/sip-and-tcc.md) and
  [`../docs/sip-filesystem-protection.md`](../docs/sip-filesystem-protection.md)). On
  macOS 11+ this effectively means SIP off.
- `profile` output should be **signed** before MDM distribution:
  `security cms -S -N "<cert>" -i tcc.mobileconfig -o signed.mobileconfig`, and PPPC only
  takes effect under user-approved MDM / supervision (see
  [`../docs/tcc-internals.md`](../docs/tcc-internals.md) §15).
- A grant written with SIP off stays valid after re-enabling SIP — the row is checked
  against the running client's code requirement, not SIP state
  ([`../docs/tcc-internals.md`](../docs/tcc-internals.md) §5).
