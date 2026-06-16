# SIP on Apple Silicon & the Signed System Volume

Two large shifts move SIP from "a NVRAM bitmask" to "one layer of a signed boot chain":

1. **macOS 11 (Big Sur): the Signed System Volume (SSV).** The OS now boots from a
   _cryptographically sealed, read-only_ system volume.
2. **Apple Silicon (M1+): LocalPolicy.** Security configuration is no longer a firmware
   NVRAM word; it is a per-install policy object signed by the **Secure Enclave (SEP)**.

SIP (the `csr` bitmask, [`sip-configuration.md`](sip-configuration.md)) still exists and is
still queried with `csr_check`/`csrutil`, but it now sits _inside_ this larger structure.

## The Signed System Volume

Pre-SSV, SIP's filesystem protection was the main thing keeping `/System` pristine - but it
was a _policy_ check the kernel performed. SSV replaces "policy" with **cryptography**:

- The entire system volume is hashed as a **Merkle tree**; every block's hash rolls up to a
  single **seal** (root hash).
- That seal is verified by the boot chain and re-checked at runtime by APFS as blocks are
  read. A single modified byte anywhere on the system volume breaks the seal.
- You actually boot from a **sealed APFS snapshot**, not the live volume.

Implication: **disabling SIP does not let you edit `/System` on 11+.** Even with
`CSR_ALLOW_UNRESTRICTED_FS` set, the volume is sealed. To modify system files you must also:

1. `csrutil authenticated-root disable` - clears **`CSR_ALLOW_UNAUTHENTICATED_ROOT`**
   (bit 11), telling the boot chain to accept an _unsealed_ / custom-snapshot root;
2. Mount the system volume read-write and make changes;
3. Recreate a snapshot and bless it (`bless --create-snapshot` / handled via `bputil`),
   accepting that the device now boots an **unsealed** system whose integrity is no longer
   cryptographically guaranteed.

User data (the **Data volume**) - and therefore the **TCC databases**, which live on the
data volume - is **not** under SSV. So SSV is not the thing blocking a `TCC.db` write;
rootless filesystem protection ([`sip-filesystem-protection.md`](sip-filesystem-protection.md))
plus the tightened TCC policy are. SSV matters here mainly as the reason "turn SIP off and
edit the OS" is now a bigger, seal-breaking operation than it was on 10.15.

## LocalPolicy and security levels

On Apple Silicon there is no `csrutil` writing to firmware NVRAM. Instead each bootable OS
has a **LocalPolicy** - a policy object signed by the SEP, established when the OS was
installed and the user authenticated. It encodes a **security level**:

| Level                   | What it allows                                                                                                        |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------- |
| **Full Security**       | Default. Only the exact, current, Apple-signed OS boots. SIP fully on; no third-party kexts.                          |
| **Reduced Security**    | Allows older signed OSes, third-party kexts (with consent), and **SIP changes**. Required before SIP can be disabled. |
| **Permissive Security** | Reduced + boots non-Apple-signed / custom kernels; the level needed for the deepest changes.                          |

Because the policy is SEP-signed, weakening it requires **physical presence + an admin
credential**, performed from **One True Recovery (1TR)** - the recovery environment reached
by holding the power button at boot. Ordinary recovery is not trusted enough to rewrite the
policy. Tools:

- **`csrutil`** - the supported front end (`csrutil disable`, `csrutil authenticated-root
disable`). On Apple Silicon `csrutil disable` itself drops the OS to Reduced Security and
  prompts for credentials.
- **`bputil`** - Apple's low-level boot-policy utility. It can express states `csrutil`
  hides; it is explicitly "for development only," easy to render a volume unbootable, and
  should be avoided unless you need a specific bit it sets.
- **`kmutil`** - manages kext collections for the (relaxed) third-party-kext case.

## Detecting state on modern macOS

```bash
csrutil status                       # SIP, possibly per-feature
csrutil authenticated-root status    # SSV seal enforcement on/off
bputil -d                            # dump LocalPolicy (Apple Silicon; verbose, low-level)
```

Programmatically, `csr_check()` ([`sip-configuration.md`](sip-configuration.md) §4) still
answers per-capability, including `CSR_ALLOW_UNAUTHENTICATED_ROOT`.

## Conclusion

- Persisting a `TCC.db` row still reduces to **SIP filesystem protection off**
  (`CSR_ALLOW_UNRESTRICTED_FS`), now reached via Reduced Security + 1TR rather than a
  simple Intel `csrutil disable`.
- You generally do **not** need to break SSV for a TCC write (TCC is on the data volume),
  but you _do_ on any task that touches `/System`.
- The friction is strictly higher than on 10.15, which is why the
  [`tcc-internals.md`](tcc-internals.md) §13–15 **MDM/PPPC** route - which needs no SIP or
  SSV change at all - is the only sane distributable path on modern macOS.
