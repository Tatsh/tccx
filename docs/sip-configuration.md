# SIP configuration - the `csr` bitmask, where it lives, how to read & change it

SIP state is a single 32-bit configuration word, `csr_config_t`. Each bit _relaxes_ one
protection - so **all-bits-clear (`0x0`) is fully enabled SIP**, and setting a bit turns
the corresponding restriction _off_. From XNU `bsd/sys/csr.h`:

| Bit | Value   | Flag                                   | Relaxes                                               |
| --- | ------- | -------------------------------------- | ----------------------------------------------------- |
| 0   | `0x001` | `CSR_ALLOW_UNTRUSTED_KEXTS`            | Load kexts not signed/approved by Apple               |
| 1   | `0x002` | `CSR_ALLOW_UNRESTRICTED_FS`            | **Write SIP-protected files (incl. `TCC.db`)**        |
| 2   | `0x004` | `CSR_ALLOW_TASK_FOR_PID`               | `task_for_pid()` on Apple/protected processes         |
| 3   | `0x008` | `CSR_ALLOW_KERNEL_DEBUGGER`            | Attach a kernel debugger                              |
| 4   | `0x010` | `CSR_ALLOW_APPLE_INTERNAL`             | Apple-internal builds / dev features                  |
| 5   | `0x020` | `CSR_ALLOW_UNRESTRICTED_DTRACE`        | dtrace on Apple processes (was `…DESTRUCTIVE_DTRACE`) |
| 6   | `0x040` | `CSR_ALLOW_UNRESTRICTED_NVRAM`         | Set protected NVRAM variables while booted            |
| 7   | `0x080` | `CSR_ALLOW_DEVICE_CONFIGURATION`       | Device-config (mobile/internal)                       |
| 8   | `0x100` | `CSR_ALLOW_ANY_RECOVERY_OS`            | Boot an unsigned/any recoveryOS                       |
| 9   | `0x200` | `CSR_ALLOW_UNAPPROVED_KEXTS`           | Load user-approved-but-not-notarized kexts            |
| 10  | `0x400` | `CSR_ALLOW_EXECUTABLE_POLICY_OVERRIDE` | Override executable trust policy                      |
| 11  | `0x800` | `CSR_ALLOW_UNAUTHENTICATED_ROOT`       | Boot a modified (unsealed) system volume (SSV)        |

`CSR_VALID_FLAGS` is the OR of all defined bits; the set grows across releases, so treat
the table as "as of recent macOS" and decode unknown high bits conservatively.

> The bit that matters to this project is **bit 1, `CSR_ALLOW_UNRESTRICTED_FS`** - that is
> the gate on writing `TCC.db`. See [`sip-filesystem-protection.md`](sip-filesystem-protection.md)
> and [`sip-and-tcc.md`](sip-and-tcc.md).

## Where the word is stored

- **Intel Macs:** the firmware NVRAM variable **`csr-active-config`** (a little-endian
  4-byte blob). You can read it booted:

  ```bash
  nvram csr-active-config        # e.g. %00%00%00%00  → 0x00000000 → SIP fully on
  ```

  but you **cannot meaningfully _write_ it while booted** - setting it is itself a
  protected-NVRAM operation (`CSR_ALLOW_UNRESTRICTED_NVRAM`, bit 6) and the value is only
  consumed at boot. That is why `csrutil` must run from recoveryOS (§5).

- **Apple Silicon:** there is no user-writable NVRAM SIP word. The csr configuration is
  part of the per-OS **LocalPolicy**, signed by the Secure Enclave and changeable only
  from One True Recovery (1TR). See [`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md).

## "Disabled" is not a magic number - decode the bits

`csrutil disable` does **not** set some canonical constant you should memorize; it sets a
_bitset_ that has varied across macOS versions (Intel installs have commonly shown
`csr-active-config = 0x77`, i.e. bits 0,1,2,4,5,6, but newer releases differ). Always
decode what you actually have:

```bash
# Intel, booted:
nvram csr-active-config
# reverse the byte order, AND against the table above.
```

Rather than read a number, ask the kernel per capability (§4).

## Reading SIP state programmatically (the right way)

macOS exposes a per-capability query, not a global boolean. From libsystem:

```c
#include <sys/csr.h>
// returns 0 if the operation IS permitted (i.e. that protection is OFF), nonzero otherwise
int csr_check(csr_config_t mask);
// fills *config with the active bitmask (needs entitlement on some OSes)
int csr_get_active_config(csr_config_t *config);
```

Both are thin wrappers over the **`csrctl`** system call. Example: "can I write protected
files?"

```c
bool fs_protection_off = (csr_check(CSR_ALLOW_UNRESTRICTED_FS) == 0);
```

`csrutil status` is the CLI form and prints either `enabled`, `disabled`, or a
per-feature breakdown (`Filesystem Protections: disabled`, `Kext Signing: enabled`, …)
when the configuration is partial.

> Practical note for this repo's tools: before attempting a direct `TCC.db` write, a tool
> should `csr_check(CSR_ALLOW_UNRESTRICTED_FS)` and fail loudly with a clear message if it
> is nonzero, rather than letting the write fail with a confusing `EPERM`/`EROFS`. See
> [`sip-and-tcc.md`](sip-and-tcc.md).

## Changing SIP state (disable / enable)

SIP is deliberately **not** changeable from the running system - you change it from a
trusted recovery environment, then reboot.

### Intel

1. Reboot holding **⌘R** to enter recoveryOS.
2. Terminal → `csrutil disable` (or `csrutil enable`, or partial: `csrutil enable --without fs`,
   depending on version).
3. Reboot. The new `csr-active-config` is read at boot.

### Apple Silicon

1. Shut down; hold the **power button** until "Loading startup options"; choose
   **Options** → enter **1TR** (One True Recovery - required; ordinary recovery is not
   trusted enough to edit the policy).
2. Terminal → `csrutil disable`. On Apple Silicon this also **lowers the OS to Reduced
   Security** and prompts for an **admin credential**, because the change is written into
   the SEP-signed LocalPolicy, not NVRAM.
3. For _system-volume_ edits you must additionally
   `csrutil authenticated-root disable` (clears bit 11) - see
   [`sip-apple-silicon-ssv.md`](sip-apple-silicon-ssv.md).
4. Reboot.

### `bputil` (Apple Silicon, low-level)

`csrutil` is the friendly front end; `bputil` manipulates the boot policy directly and can
express states `csrutil` won't. It is unsupported for general use and easy to brick a boot
with - prefer `csrutil` unless you specifically need a policy bit it can't set.
