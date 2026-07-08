# tccx

[![GitHub tag (with filter)](https://img.shields.io/github/v/tag/Tatsh/tccx)](https://github.com/Tatsh/tccx/tags)
[![License](https://img.shields.io/github/license/Tatsh/tccx)](https://github.com/Tatsh/tccx/blob/master/LICENSE)
[![Build](https://github.com/Tatsh/tccx/actions/workflows/release.yml/badge.svg)](https://github.com/Tatsh/tccx/actions/workflows/release.yml)
[![Tests](https://github.com/Tatsh/tccx/actions/workflows/tests.yml/badge.svg)](https://github.com/Tatsh/tccx/actions/workflows/tests.yml)
[![Documentation Status](https://readthedocs.org/projects/tccx/badge/?version=latest)](https://tccx.readthedocs.io/en/latest/)
[![Coverage Status](https://coveralls.io/repos/github/Tatsh/tccx/badge.svg?branch=master)](https://coveralls.io/github/Tatsh/tccx?branch=master)
[![Dependabot](https://img.shields.io/badge/Dependabot-enabled-blue?logo=dependabot)](https://github.com/dependabot)
[![Swift](https://img.shields.io/badge/Swift-5.7-orange?logo=swift&logoColor=white)](https://swift.org/)
[![Platform: macOS](https://img.shields.io/badge/platform-macOS-lightgrey?logo=apple)](https://developer.apple.com/macos/)
[![Prettier](https://img.shields.io/badge/Prettier-black?logo=prettier)](https://prettier.io/)
[![Stargazers](https://img.shields.io/github/stars/Tatsh/tccx?logo=github&style=flat)](https://github.com/Tatsh/tccx/stargazers)

[![@Tatsh](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fpublic.api.bsky.app%2Fxrpc%2Fapp.bsky.actor.getProfile%2F%3Factor=did%3Aplc%3Auq42idtvuccnmtl57nsucz72&query=%24.followersCount&label=Follow+%40Tatsh&logo=bluesky&style=social)](https://bsky.app/profile/Tatsh.bsky.social)
[![Mastodon Follow](https://img.shields.io/mastodon/follow/109370961877277568?domain=hostux.social&style=social)](https://hostux.social/@Tatsh)

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

See [documentation](https://tccx.readthedocs.io/en/latest/).

To build it locally: `yarn gen-docs` (output in `docs/_build/html`).

## Tool

`tcc-preapprove` is documented at
[tcc-preapprove reference](https://tccx.readthedocs.io/en/latest/tcc-preapprove.html).

## Building

Everything runs through `package.json` scripts:

```bash
yarn build          # debug build, signed with entitlements
yarn build:release  # universal (arm64 + x86-64) release build, signed with entitlements
yarn test           # swift test
swift run tcc-preapprove --help
```
