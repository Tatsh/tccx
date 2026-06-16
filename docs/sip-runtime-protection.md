# SIP runtime protection — processes, kexts, dtrace, NVRAM, and `DYLD_*`

> Scope per [`README.md`](README.md): the platform-binary strings cited as **[verified]**
> are from this repo's `tccd`. The kernel/AMFI mechanics are documented macOS internals.

Filesystem protection ([`sip-filesystem-protection.md`](sip-filesystem-protection.md))
stops you from *changing the OS on disk*. Runtime protection stops you from *defeating it
in memory* — which is why the "inject into / call into `tccd`" routes
([`tcc-internals.md`](tcc-internals.md) §11) are dead ends independent of the filesystem.

## 1. Task-port protection (`task_for_pid`) — bit 2

`task_for_pid()` returns a task port, which is full read/write/execute control over another
process's address space. With SIP on (`CSR_ALLOW_TASK_FOR_PID` clear), the kernel **refuses
to hand out the task port of an Apple-signed / restricted process to anyone**, root
included. Consequences for this project:

- You cannot get `tccd`'s task port to call its functions in-process or patch its memory.
- You cannot inject a dylib into `tccd` (no port → no remote thread, and the hardened
  runtime / library validation would reject the dylib anyway).
- Even a process that *is* allowed to debug others (with the bit set) still won't satisfy
  `tccd`'s **caller** entitlement check, which authenticates by audit token
  ([`tcc-internals.md`](tcc-internals.md) §11). So switching entry points changes nothing.

This is the runtime half of "you can't become `tccd`."

## 2. Kernel extension signing — bits 0 and 9

`CSR_ALLOW_UNTRUSTED_KEXTS` (bit 0) and `CSR_ALLOW_UNAPPROVED_KEXTS` (bit 9) gate loading
kernel code. With SIP on, only Apple-signed (and, on newer OSes, user-approved /
notarized) kexts load. This blocks the "drop a kext that bypasses TCC/SIP from ring 0"
approach: you'd have to disable SIP to load the very tool meant to subvert it.

## 3. dtrace and kernel debugging — bits 5 and 3

- `CSR_ALLOW_UNRESTRICTED_DTRACE` (bit 5): with SIP on, dtrace cannot instrument
  Apple-signed processes (you can dtrace your own code, not `tccd`).
- `CSR_ALLOW_KERNEL_DEBUGGER` (bit 3): kernel debugging is blocked. Together these stop
  the "observe/patch the decision live" tracing routes against system daemons.

## 4. Protected NVRAM — bit 6

`CSR_ALLOW_UNRESTRICTED_NVRAM` (bit 6) is what makes SIP self-protecting: while booted, you
cannot set the protected NVRAM variables — *including `csr-active-config` itself*. That is
the structural reason `csrutil` must run from recoveryOS
([`sip-configuration.md`](sip-configuration.md) §5): the running OS is forbidden from
weakening its own SIP word.

## 5. Platform binaries (and how `tccd` uses the concept) — [verified]

A **platform binary** is an executable whose code signature is anchored to Apple's platform
identity; AMFI sets the **`CS_PLATFORM_BINARY`** code-signing flag (`0x4000000`) on it at
load. Platform binaries get implicit trust in several policies (e.g. relaxed library
validation among themselves) and are the population SIP's exemptions are written against.

This is not abstract for TCC — `tccd` makes prompt-policy decisions on whether the *client*
is a platform binary. From this repo's `tccd` **[verified]**:

```
deriveIsPlatformBinary:withCodesignFlags:
clientIsApplePlatformBinary: %d
Allowing service %{public}@ from platform binary %{public}@ in background session.
CS_PLATFORM_BINARY set but not AppleSigned; internal policy for prompting is AllowWithInternalWarning.
CS_PLATFORM_BINARY set but not AppleSigned; prompt policy is Deny.
```

Two takeaways: (1) `tccd` reads the kernel-supplied codesign flags to classify callers, and
(2) it deliberately distinguishes "`CS_PLATFORM_BINARY` set" from "actually Apple-signed,"
denying the in-between case. You cannot forge platform-binary status from userspace — the
flag is set by AMFI from the signature, and faking it requires defeating code signing,
i.e. SIP/AMFI off.

## 6. `DYLD_*` environment stripping (AMFI, adjacent to SIP)

dyld ignores `DYLD_INSERT_LIBRARIES`, `DYLD_LIBRARY_PATH`, and friends for **restricted**
processes — those with the hardened runtime, library validation, a `__RESTRICT/__restrict`
segment, setuid/setgid bits, or restricted entitlements. This is enforced by **AMFI**, a
sibling of SIP rather than a `csr` bit, but it is part of the same "you can't load your code
into a protected process" wall and is commonly conflated with SIP. Net effect for this
project: the classic `DYLD_INSERT_LIBRARIES=hook.dylib` interposition does nothing against
`tccd` or other system daemons.

## 7. Why every in-memory route collapses to "SIP off"

Stack the runtime protections against the project's goal:

| Route to forge/inject a grant | Blocked by | csr bit to relax |
|---|---|---|
| Get `tccd`'s task port, patch its decision | Task-port protection | 2 (`TASK_FOR_PID`) |
| Inject a dylib into `tccd` | `DYLD_*` stripping + library validation (AMFI) | (AMFI; effectively SIP off) |
| Load a kext that writes `TCC.db` | Kext signing | 0/9 (`…KEXTS`) |
| dtrace/patch the live decision | dtrace restriction | 5 (`DTRACE`) |
| Pose as a platform/Apple binary | `CS_PLATFORM_BINARY` is signature-derived | (code signing; SIP/AMFI off) |
| Just write the file | Filesystem protection ([fs doc](sip-filesystem-protection.md)) | 1 (`UNRESTRICTED_FS`) |

Every row requires turning off some SIP capability. There is no combination that lets an
unentitled process persist a TCC grant while SIP is on — which is exactly the project's
conclusion. See [`sip-and-tcc.md`](sip-and-tcc.md).
