SIP overview
============

System Integrity Protection (SIP, internal codename **"rootless"**, shipped in OS X 10.11 El
Capitan, 2015) **removes the equivalence "root == total control."** After SIP, a long list of
operations are denied *to every process regardless of uid* - including uid 0 - and re-granted
only to specific Apple components identified by **code signature and entitlement**, not by
privilege level. The decision is made in the **kernel** (via the MACF / Sandbox policy and
AMFI), so it cannot be talked out of from userspace.

Concretely, SIP is one configuration word (``csr-active-config``) that gates several
independent subsystems:

.. list-table::
   :header-rows: 1

   * - Subsystem
     - What it stops
     - Doc
   * - **Filesystem protection** ("rootless")
     - Writing/deleting protected files & dirs (``/System``, ``/usr``, ``TCC.db``, …)
     - :doc:`sip-filesystem-protection`
   * - **Runtime / process protection**
     - ``task_for_pid`` on Apple procs, unsigned kexts, dtrace on Apple procs, kernel debug,
       protected-NVRAM writes
     - :doc:`sip-runtime-protection`
   * - **Boot / volume integrity** (11+, Apple Silicon)
     - Booting a modified system volume; relaxing kext & boot policy
     - :doc:`sip-apple-silicon-ssv`

The bitmask that turns each of these on/off is the subject of :doc:`sip-configuration`.

Why it exists (threat model)
----------------------------

Pre-SIP, any root-level code (a malicious installer, an exploited setuid binary, a careless
``sudo``) could rewrite the OS: patch ``/System`` binaries, drop a persistent kext, disable
security daemons, or edit a privacy database to silently grant itself the camera. SIP raises
the floor: even *if* an attacker gets root, they still cannot

- modify the OS on disk (so the platform stays as Apple shipped it),
- attach to or inject into Apple's own processes,
- load unsigned kernel code, or
- tamper with the databases (like TCC's) that record the user's privacy decisions.

The protection therefore is **most valuable exactly against the privilege level that used to
defeat everything**. That is the lens for the rest of this suite.

SIP is a *family* of checks, not a single gate
----------------------------------------------

A frequent mistake is to treat "SIP" as one boolean. It is a bitmask (:doc:`sip-configuration`)
precisely because the pieces are independent: you can disable filesystem protection while
leaving kext signing on, allow ``task_for_pid`` for debugging while keeping ``/System``
read-only, etc. When someone says "SIP is off," always ask *which bits* - ``csrutil status``
and ``csr_check()`` answer per capability, not globally.

How it relates to TCC
---------------------

TCC (:doc:`tcc-internals`) decides per-app privacy permissions and stores them in ``TCC.db``.
SIP is what makes those decisions *trustworthy*: the TCC databases sit in SIP-protected
directories tagged with the **TCC storage class**, and only ``tccd`` - which carries the
matching storage-class entitlement **[verified]** (see :doc:`sip-and-tcc`) - may write them.
Without SIP, any root process could forge a "user allowed camera" row; with SIP, even root
cannot, and must instead go through ``tccd``'s entitlement-gated XPC interface or the MDM/PPPC
channel.

TCC's integrity *depends on* SIP.

Conclusion
----------

This project set out to programmatically pre-approve TCC permissions. The reverse engineering
(:doc:`tcc-internals`) established exactly how a genuine grant row looks and how to construct
one. The remaining question - "can a tool write it?" - resolves entirely into SIP:

- **To persist a row by writing** ``TCC.db`` **directly, you must disable SIP's filesystem
  protection** (``CSR_ALLOW_UNRESTRICTED_FS``), because the file is storage-class protected and
  the tool is not entitled. On macOS 11+, the Signed System Volume and a tightened policy make
  this effectively "SIP fully off." This is *not* a bug to route around - it is the kernel
  enforcing the boundary by design (:doc:`sip-and-tcc`, "Two blocks").
- **The only persist path that needs no SIP change** is the sanctioned one: an MDM-delivered
  **PPPC profile**, which ``tccd`` evaluates live and never writes to ``access`` (see
  :doc:`tcc-internals` §13–15).

Reading order
-------------

1. This overview.
2. :doc:`sip-configuration` - the bitmask and how to read/set it.
3. :doc:`sip-filesystem-protection` - the wall this project hits.
4. :doc:`sip-runtime-protection` - why injection/task-port routes also fail.
5. :doc:`sip-apple-silicon-ssv` - what changed on 11+/Apple Silicon.
6. :doc:`sip-and-tcc` - the synthesis, with repo-verified anchors.
