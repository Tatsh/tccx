# SIP filesystem protection ("rootless")

`TCC.db` cannot be written by an arbitrary process, even as root.

## Two ways a path becomes protected

A file or directory is SIP-protected ("restricted") if **either**:

1. it carries the BSD file flag **`SF_RESTRICTED`** (`0x00080000`), shown by `ls -lO` as
   the word `restricted`; **or**
2. it carries the extended attribute **`com.apple.rootless`**.

Both are evaluated in the kernel by the **Sandbox** MACF policy on every VFS mutation
(write, unlink, rename, chflags, setxattr, …). Because the check is a kernel MAC hook keyed
on the _acting process's_ code signature and entitlements - not its uid - `sudo`, setuid,
and "I am root" make no difference.

The canonical seed list of protected locations ships at
**`/System/Library/Sandbox/rootless.conf`**: each line names a path, and a leading `*`
marks a sub-path _exception_ (a hole carved out of an otherwise-protected tree, e.g.
`/usr/local`). A companion compatibility list
(`/System/Library/Sandbox/Compatibility.bundle`) preserves specific third-party paths
across OS upgrades. Representative protected trees: `/System`, `/bin`, `/sbin`, `/usr`
(except `/usr/local`), Apple apps in `/Applications`, and many `/private/var/db` and
`/Library/Application Support` subtrees - **including the TCC directories**.

## The `com.apple.rootless` xattr is the interesting one: storage classes

The `restricted` flag is binary ("no one but the install machinery touches this"). The
`com.apple.rootless` **xattr can carry a value naming a _storage class_** - a named
capability. The rule the kernel enforces:

> A process may modify a file tagged with storage class _C_ **iff** its code signature
> bears the entitlement **`com.apple.rootless.storage.C`** (the original name) or
> **`com.apple.private.security.storage.C`** (the later name). Otherwise the write is
> denied regardless of uid.

This is how Apple delegates write access to exactly one daemon per protected dataset
without ever granting "root can do it." `installd`/`system_installd` instead hold the
broad **`com.apple.rootless.install`** / **`com.apple.rootless.install.heritable`**
entitlements (the heritable variant passes the exemption to child processes), which is why
package installs can lay down `/System` content during an OS update while nothing else can.

### [verified] TCC's storage class, straight from this repo's `tccd`

`strings TCC.framework/Support/tccd` contains **both** storage-class entitlement names:

```
com.apple.rootless.storage.TCC
com.apple.private.security.storage.TCC
```

The TCC database directories - `/Library/Application Support/com.apple.TCC/` and
`~/Library/Application Support/com.apple.TCC/` - are tagged with the **`TCC` storage
class**. Therefore:

- `tccd`, holding `…storage.TCC`, may write `TCC.db`.
- Any other process - including root, including a copy of `tccd` you run yourself
  ([`sip-runtime-protection.md`](sip-runtime-protection.md) explains why re-running the
  code doesn't inherit the identity) - may **not**, while SIP filesystem protection is on.

This is the precise, evidence-backed refinement of
[`tcc-internals.md`](tcc-internals.md) §11's phrase "Apple-signed platform binary exempted
on those paths": the exemption is **entitlement-by-storage-class**, not "is it Apple."

## Inspecting protection on a live system

```bash
ls -lO "/Library/Application Support/com.apple.TCC"     # look for the 'restricted' flag
xattr -l "/Library/Application Support/com.apple.TCC/TCC.db"   # com.apple.rootless present?
ls -ldO /System /usr /usr/local                          # /usr restricted, /usr/local not
```

To see what an entitled daemon carries (on a real macOS box, not extractable the same way
on Linux):

```bash
codesign -d --entitlements :- /System/Library/PrivateFrameworks/TCC.framework/Support/tccd
# → includes com.apple.private.security.storage.TCC (and historically the rootless name)
```

## What "disable" means here, and what it does _not_

Clearing **`CSR_ALLOW_UNRESTRICTED_FS`** (bit 1 - i.e. SIP filesystem protection _off_,
see [`sip-configuration.md`](sip-configuration.md)) makes the kernel stop enforcing both
the `restricted` flag and the storage-class rule, so an ordinary root process can then
write `TCC.db`. Caveats:

- **macOS 11+ adds a second, independent wall: the Signed System Volume.** SSV protects
  the _system_ volume by cryptographic seal, separate from rootless. The TCC databases are
  on the _data_ volume, so SSV does not directly seal them - but Apple also tightened the
  TCC write policy on 11+ (the legacy Full-Disk-Access-can-write hole was closed), so in
  practice persisting a row on modern macOS means SIP off. See
  [`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md) and
  [`tcc-internals.md`](tcc-internals.md) §10.
- **A grant written with SIP off stays valid after re-enabling SIP.** The row's
  trustworthiness is decided by the `csreq` code-requirement match against the _running_
  client ([`tcc-internals.md`](tcc-internals.md) §5), not by SIP state at read time. So
  "disable → write row → re-enable" yields a permanent, genuine-looking grant - at the
  cost of recovery-mode reboots, which is only reasonable for a one-off personal bootstrap
  or a VM base image you build, never a distributable script.

## Why you cannot "just chflags it off"

Removing the `restricted` flag (`chflags norestricted …`) or deleting the
`com.apple.rootless` xattr is _itself_ a protected mutation: the kernel denies it under the
same policy. There is no in-band escape - the only levers are (a) clear the csr FS bit from
recovery, or (b) be the entitled daemon.
