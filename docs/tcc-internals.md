# TCC Internals & Pre-Approval (macOS 10.15.6 `tccd`)

> Reverse-engineered from `tccd` (`/tccd/x86-64-cpu0x3`, Mach-O x86-64, image base
> `0x100000000`) in the Ghidra project `tcc`. All addresses,
> SQL, and enum values below were read directly out of this binary.

## What lives where

| Component         | Location                                                             | Notes                                                                                                                             |
| ----------------- | -------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Daemon binary     | `/System/Library/PrivateFrameworks/TCC.framework/Support/tccd`       | Standalone Mach-O; **not** in the dyld shared cache. Holds all the logic below.                                                   |
| User database     | `~/Library/Application Support/com.apple.TCC/TCC.db`                 | Per-user services: Downloads/Documents/Desktop folders, Camera, Mic, AppleEvents, etc.                                            |
| System database   | `/Library/Application Support/com.apple.TCC/TCC.db`                  | System/admin services: Full Disk Access (`SystemPolicyAllFiles`), Accessibility, etc.                                             |
| Linked frameworks | dyld shared cache (`/System/Library/dyld/dyld_shared_cache_x86_64h`) | CoreFoundation, Foundation, Security, LaunchServices, libobjc, libdispatch - all show as unresolved `EXTERNAL` imports in Ghidra. |

Both databases are SIP-protected. Writing requires **either SIP disabled, or the writing
process holding Full Disk Access** (and on macOS 11+, Apple closed the FDA-write hole, so
newer OSes effectively require SIP off for direct DB edits).

## `access` table schema (verified)

The exact statements `tccd` runs (string table addresses in parentheses):

```sql
-- Lookup on every access check (0x10005d181)
SELECT auth_value, auth_reason, csreq,
       strftime('%s','now') - last_modified AS age, flags, auth_version
  FROM access WHERE service = ? AND client = ? AND client_type = ?;

-- Request/prompt-grant insert, 11 columns (0x10005dd9c)
INSERT OR REPLACE INTO access
 (service, client, client_type, auth_value, auth_reason, auth_version,
  csreq, policy_id, indirect_object_identifier_type,
  indirect_object_identifier, indirect_object_code_identity)
 VALUES (?,?,?,?,?,?,?,?,?,?,?);

-- Explicit-set insert, 12 columns incl. flags (0x10005de9f)
INSERT OR REPLACE INTO access
 (service, client, client_type, auth_value, auth_reason, auth_version,
  csreq, policy_id, indirect_object_identifier_type,
  indirect_object_identifier, indirect_object_code_identity, flags)
 VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
```

Verbatim `CREATE TABLE` DDL (schema version 27, string @ `0x10005f2cc`) - authoritative:

```sql
CREATE TABLE access (
  service        TEXT    NOT NULL,
  client         TEXT    NOT NULL,
  client_type    INTEGER NOT NULL,
  auth_value     INTEGER NOT NULL,
  auth_reason    INTEGER NOT NULL,
  auth_version   INTEGER NOT NULL,
  csreq          BLOB,
  policy_id      INTEGER,
  indirect_object_identifier_type INTEGER,
  indirect_object_identifier      TEXT NOT NULL DEFAULT 'UNUSED',
  indirect_object_code_identity   BLOB,
  flags          INTEGER,
  last_modified  INTEGER NOT NULL DEFAULT (CAST(strftime('%s','now') AS INTEGER)),
  PRIMARY KEY (service, client, client_type, indirect_object_identifier),
  FOREIGN KEY (policy_id) REFERENCES policies(id) ON DELETE CASCADE ON UPDATE CASCADE);
-- sibling tables: admin(key,value), policies(id,bundle_id,uuid,display),
-- active_policy(client,client_type,policy_id), access_overrides(service PRIMARY KEY),
-- expired(service,client,client_type,csreq,last_modified,expired_at)
```

Column meanings:

| Column                            | Type      | Meaning                                                                                                |
| --------------------------------- | --------- | ------------------------------------------------------------------------------------------------------ |
| `service`                         | TEXT      | `kTCCService…` constant (see §3)                                                                       |
| `client`                          | TEXT      | bundle ID (if `client_type=0`) or absolute path (if `client_type=1`)                                   |
| `client_type`                     | INT       | `0`=bundle identifier, `1`=absolute path                                                               |
| `auth_value`                      | INT       | `0`=denied, `2`=allowed (`1`=unknown). Verified: migration SQL keys on `auth_value = 2` for "allowed". |
| `auth_reason`                     | INT       | see §4                                                                                                 |
| `auth_version`                    | INT       | always `1` in this build                                                                               |
| `csreq`                           | BLOB      | serialised `SecRequirement` (magic `0xfade0c00`); see §5                                               |
| `policy_id`                       | INT/NULL  | NULL for normal grants                                                                                 |
| `indirect_object_identifier_type` | INT       | `0` for non-AppleEvents services                                                                       |
| `indirect_object_identifier`      | TEXT      | `'UNUSED'` for non-AppleEvents services                                                                |
| `indirect_object_code_identity`   | BLOB/NULL | NULL for non-AppleEvents services                                                                      |
| `flags`                           | INT       | `0` normally (bit 0 = "disabled/denied marker" per lookups `flags & 1`)                                |
| `last_modified`                   | INT       | omitted on insert → table DEFAULT sets it                                                              |

## Service constants

Folder ("Files and Folders") services - **user DB**:

- `kTCCServiceSystemPolicyDownloadsFolder`
- `kTCCServiceSystemPolicyDocumentsFolder`
- `kTCCServiceSystemPolicyDesktopFolder`

System/admin services - **system DB**:

- `kTCCServiceSystemPolicyAllFiles` (Full Disk Access - supersedes the per-folder grants)
- `kTCCServiceSystemPolicyAppBundles`, `…DeveloperFiles`, `…NetworkVolumes`,
  `…RemovableVolumes`, `…SysAdminFiles`
- `kTCCServiceAccessibility`, `kTCCServiceEndpointSecurityClient`

## `auth_reason` enum (verified from `GetAuthReasonString` @ `0x100001e80`)

| Value | String                 |                                                     |
| ----- | ---------------------- | --------------------------------------------------- |
| 0     | `None`                 |                                                     |
| **1** | `Recorded`             |                                                     |
| 2     | `Service Default`      |                                                     |
| **3** | `Service Policy`       | **what the live request/prompt-grant path records** |
| 4     | `Compatibility Policy` |                                                     |
| 5     | `Override Policy`      |                                                     |
| 6     | `Set`                  | explicit administrative set                         |
| 1000  | `Error`                |                                                     |
| 1001  | `Service Override`     |                                                     |
| 1002  | `Missing Usage String` | app crashed: missing `NS…UsageDescription`          |
| 1003  | `Prompt Timeout`       |                                                     |
| 1004  | `Preflight Unknown`    |                                                     |
| 2000  | `Entitled`             | allowed via entitlement; no DB row needed           |

> NOTE: these strings differ from many online tables (which label 3 as "User Set", etc.).
> Those tables describe a different/newer build. For 10.15.6, trust this enum.

## The `csreq` contract (from `-[TCCDAccessIdentity matchesCodeRequirementData:]` @ `0x10001f1c5`)

```c
status = SecRequirementCreateWithData(csreqBlob, &req);
if (status == 0)                         // blob parsed
    return [identity matchesCodeRequirement: req];   // SecCodeCheckValidity vs the caller
else {                                   // blob malformed / NULL
    os_log_error(... "SecRequirementCreateWithData failure" ...);
    return false;                        // → NO MATCH → row does not authorise
}
```

Consequences:

- `csreq` **fails closed**. A NULL or garbage blob makes the row useless - it does _not_
  default to "allow".
- The blob must be a real serialised `SecRequirement`, and the **running** client must
  satisfy it (designated requirement match). Generate it from the target binary's own DR.

## Write-path provenance (who writes what)

| Path                                 | Function chain                                                                                                   | auth_value                           | auth_reason                                     |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------ | ----------------------------------------------- |
| Request / user "Allow"               | `HandleAccessRequest` → `InsertAccessRecordBlock` (`0x100017c70`) → `BindAccessInsertParameters` (`0x100017d1f`) | from decision (`2` allow / `0` deny) | **hardcoded `3`** (Service Policy), version `1` |
| Explicit set (MDM/`tccutil`/clients) | `TCCAccessSetInternal` → `BindFullAuthRowForReplace` (`0x100017fd2`)                                             | caller-supplied                      | caller-supplied                                 |

To produce a row **indistinguishable from a genuine user grant**: `auth_value=2`,
`auth_reason=3`, `auth_version=1`, valid `csreq`.

## Why there is no "private API" to inject a grant

The TCC XPC write verbs are entitlement-gated. `CopyRequiredEntitlementForTCCCommand`
(`0x1000298a4`) maps each command (e.g. `TCCAccessSetInternal`) to a
`com.apple.private.tcc.manager.*` entitlement. You cannot hold those without Apple
signing / disabling AMFI. The only realistic programmatic write paths are therefore:

1. **MDM PPPC profile** (`com.apple.TCC.configuration-profile-policy`) - sanctioned, but
   Apple restricts which services it may manage; the per-folder services generally cannot
   be pre-granted this way (use `SystemPolicyAllFiles`/FDA, which it can, and which
   supersedes folder access).
2. **Direct `sqlite3` write** - on a machine you control with SIP off (or an FDA-holding
   writer on ≤10.15).

## Pre-approval recipe

```sql
INSERT OR REPLACE INTO access
 (service, client, client_type, auth_value, auth_reason, auth_version,
  csreq, policy_id, indirect_object_identifier_type,
  indirect_object_identifier, indirect_object_code_identity, flags)
 VALUES ('kTCCServiceSystemPolicyDownloadsFolder', 'com.googlecode.iterm2',
         0, 2, 3, 1, X'<csreq_hex>', NULL, 0, 'UNUSED', NULL, 0);
```

Then `killall tccd` so it reloads. Generate `<csreq_hex>` from the target's designated
requirement (the `tcc-preapprove` tool does this - `swift run tcc-preapprove grant …`).

## Verify

```bash
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT service, client, client_type, auth_value, auth_reason, auth_version,
          length(csreq) FROM access WHERE client='com.googlecode.iterm2';"
# expect auth_value=2, auth_reason=3, non-zero csreq length
```

Real test: have the app read `~/Downloads` and confirm **no prompt** appears.

## Version caveats

Everything here is verified for **10.15.6**. On macOS 11/12+: the `access` schema gained
columns (`boot_uuid`, `last_reminded`, `pid`, `responsible`, …), `auth_value` gained
`3`=limited, the DB write path tightened to SIP-off only, and the cache-reload behaviour
changed. Re-verify `.schema access` and re-read `GetAuthReasonString` on the target OS.

## The two blockers (why direct writes need SIP off, and why there's no shortcut)

Pre-approving via the DB or via "calling tccd's functions" runs into **two independent,
kernel-enforced walls**:

1. **SIP filesystem protection on `TCC.db`.** Both databases are SIP-protected paths.
   `tccd` can write them because it's an Apple-signed _platform binary_ exempted on those
   paths; an arbitrary process is not. This is enforced by the kernel/sandbox, not by a
   userspace check.

2. **AMFI entitlement check on the caller.** `tccd`'s privileged operations are an **XPC
   service** (`com.apple.tccd` mach service). Every privileged verb runs through
   `CheckCallerHasEntitlement` (`0x10003fb16`):

   ```c
   xpc_dictionary_get_audit_token(message, &atoken);     // caller identity from the kernel
   secTask = SecTaskCreateWithAuditToken(atoken);
   if (![entitlement hasPrefix:@"com.apple.private.tcc."])  // only these are valid
       log("invalid entitlement requested");
   val = SecTaskCopyValueForEntitlement(secTask, entitlement);
   return (val == kCFBooleanTrue);
   // miss → "pid %d attempted to call %s without the %@ entitlement"
   ```

   The required entitlement (`com.apple.private.tcc.manager*`) must be **code-signed into
   the caller** and validated by AMFI. These are Apple-private entitlements; self-signing
   does not work because AMFI rejects restricted entitlements not backed by an Apple
   profile.

### Why `dlsym(tccd)` / injection is an architectural dead-end

- `tccd` is a separate **process**, not a library. `dlsym` resolves symbols in _your_
  address space. Even `dlopen`-ing the `tccd` Mach-O and calling its `SetInternal` code
  runs with **your** process's identity/entitlements - so it hits both walls anyway.
- The XPC interface authenticates the **caller** by audit token, so picking a different
  entry point changes nothing.
- Running code _inside_ `tccd`'s process needs its task port → blocked by SIP + hardened
  runtime + restricted entitlements. That's defeating the security boundary, not config.

**Conclusion:** the only ways to write a grant are (a) be SIP-off, (b) be a process Apple
blessed with the entitlement (you can't be), or (c) hand the decision to the sanctioned
channel - an MDM **PPPC profile** (§13).

## Audience → method matrix

| Audience                         | Method                                                                                           | SIP change?            |
| -------------------------------- | ------------------------------------------------------------------------------------------------ | ---------------------- |
| **Managed fleet (MDM)**          | PPPC profile granting **FDA** (`SystemPolicyAllFiles`), which supersedes the per-folder services | **None**               |
| **Individual dev's own Mac**     | Script the Settings deep-link + one manual click                                                 | None                   |
| **CI / ephemeral VMs you build** | Bake **SIP-off into the base image**, then write rows directly with the `sqlite` path            | SIP off (once, by you) |

Notes:

- **PPPC cannot pre-grant the folder services** (`SystemPolicyDownloadsFolder/Documents/
Desktop`) reliably - they're user-consent-only. Grant **FDA** instead; it covers them.
- FDA-via-profile only auto-applies under **user-approved MDM / supervision**; a
  double-clicked profile won't grant it.
- "Disable SIP → write → re-enable" _does_ leave valid grants (csreq is validated against
  the running process, not SIP state), but it's two Recovery trips / three reboots - only
  sane for a one-off personal bootstrap, never for a distributed script.

## PPPC `.mobileconfig` generation (the SIP-free, distributable path)

A Privacy Preferences Policy Control profile is the Apple-sanctioned pre-approval. Shape:

```
Configuration profile (PayloadType "Configuration", PayloadScope "System")
└─ PayloadContent[0]  PayloadType "com.apple.TCC.configuration-profile-policy"
   └─ Services = {
        "<ServiceKey>" = ( { Identifier; IdentifierType; CodeRequirement; Allowed/Authorization } )
      }
```

Key differences from the direct-DB path:

- **Service keys drop the `kTCCService` prefix** (e.g. `SystemPolicyAllFiles`,
  `SystemPolicyDownloadsFolder`).
- **`CodeRequirement` is the requirement _string_**, not the binary `csreq` blob - use
  `SecRequirementCopyString` (not `SecRequirementCopyData`).
- **`IdentifierType`** = `bundleID` (apps) or `path` (plain binaries).
- **`Allowed` (bool)** is the 10.14–10.15 key; **`Authorization` ("Allow")** is the 11+
  key. Emitting both keeps one profile compatible across versions (each OS reads its own).
- The profile should be **signed** for MDM acceptance:
  `security cms -S -N "<Installer/Developer ID cert>" -i in.mobileconfig -o signed.mobileconfig`.

Generate one with: `swift run tcc-preapprove profile --app <App> -p fda -o tcc.mobileconfig`.

## CLI reference (`tcc-preapprove` - SwiftPM package at repo root)

| Subcommand        | Purpose                                                       | Needs the binary?        |
| ----------------- | ------------------------------------------------------------- | ------------------------ |
| `grant` (default) | Write an allow row (csreq blob, `auth_value=2 auth_reason=3`) | yes (computes `csreq`)   |
| `revoke`          | `DELETE` row(s) for a client - `-p <svc>` or `--all`          | no (works by `--client`) |
| `list`            | Print rows across user/system DBs, decoded                    | no                       |
| `profile`         | Emit a PPPC `.mobileconfig` (CodeRequirement string)          | yes (computes DR string) |

Direct-DB subcommands (`grant`/`revoke`/`list`) need FDA or SIP-off (root for system DB).
`profile` needs neither - it only reads the target's signature and emits XML.

## Deploying the PPPC profile (the UAMDM requirement)

Generating the `.mobileconfig` (§13) is the easy half. Getting macOS to **honour** it is
the half with prerequisites.

### Install ≠ enforce

You can double-click a `.mobileconfig` and approve it in **System Settings → Privacy &
Security → Profiles**, and it will show as installed. But the
`com.apple.TCC.configuration-profile-policy` payload is special-cased: its grants are
**only applied when the profile is delivered by MDM**, and that enrolment must be
**user-approved (UAMDM)** or the device **supervised** (ADE / Apple Configurator). A
manually double-clicked PPPC profile on a non-MDM Mac installs but grants **nothing** —
this gate exists so a rogue `.mobileconfig` can't self-grant Full Disk Access.

Also: `sudo profiles install -path …` for configuration profiles was **removed in macOS
11+** (the CLI can still `list`/`remove`). So on 11+ with no MDM there is _no_ path to an
effective PPPC grant.

### Deployment options

| Channel                                      | Effort                | Notes                                                                            |
| -------------------------------------------- | --------------------- | -------------------------------------------------------------------------------- |
| Commercial MDM (Jamf, Kandji, Mosyle, …)     | low (if you have one) | Upload the `.mobileconfig`; assign to the device/group.                          |
| **Self-hosted MDM** (`nanomdm` / `micromdm`) | medium                | The only way to make PPPC work on _your own_ machine without a commercial MDM.   |
| Supervision via **Apple Configurator 2**     | medium–high           | Supervising an Apple-silicon Mac erases it; via ADE it's seamless on next setup. |
| Manual double-click                          | n/a                   | Installs but TCC ignores the grants. Don't rely on it.                           |

### Minimal self-hosted flow (`nanomdm`, outline)

1. **APNs push certificate** - obtain an MDM vendor (CSR) signature, then create the push
   cert at the Apple Push Certificates Portal; load it into the MDM server.
2. **Run the MDM server** (`nanomdm`) behind TLS with a reachable hostname.
3. **Enrolment profile** - serve an enrolment `.mobileconfig` (MDM payload pointing at
   your server's check-in/command URLs). Install it on the Mac.
4. **User-approve the enrolment (UAMDM)** - on the Mac, approve Device Management in
   System Settings (Apple-silicon requires the local user to click Allow). Without this
   approval the enrolment is _not_ user-approved and PPPC still won't apply.
5. **Push the PPPC profile** - queue an `InstallProfile` command carrying the signed
   `.mobileconfig` from `tcc-preapprove profile`.

### Sign the profile

MDMs generally require a signed profile:

```bash
security cms -S -N "<Developer ID / installer certificate>" \
  -i tcc.mobileconfig -o tcc-signed.mobileconfig
```

### Verify it took (close the loop on the target Mac)

- `profiles list` (or System Settings → Profiles) shows the profile installed.
- **Profile/MDM grants are NOT written to the `access` table.** `tccd` evaluates them
  _live_ via `-[TCCDPolicyOverride evaluateOverridePolicyForAccessByIdentity:…]`
  (`0x1000440c2`) → `_locked_evaluateAccessByIdentity:…` (`0x100045dfd`), iterating
  `orderedOverridePolicies` loaded from:
  - `/Library/Application Support/com.apple.TCC/MDMOverrides.plist` (MDM)
  - `/Library/Application Support/com.apple.TCC/SiteOverrides.plist` (Site)
  - a bin-compat override path (`binCompatOverridePath`)
    So `tcc-preapprove list` / `sqlite3` will **not** show them - inspect the plist instead.
    (The `access_overrides` SQLite table is **unrelated**: it's a per-service flag list,
    `service TEXT NOT NULL PRIMARY KEY`, toggled by the `TCCAccessSetOverride` verb —
    not where profile grants live.)
- **VERIFIED keys** `tccd` reads from each override entry (`0x100045dfd`): `IdentifierType`
  (`bundleID`/`path`), `CodeRequirementData` (the **binary** blob the OS compiles from your
  profile's `CodeRequirement` _string_ at install), `Authorization`
  (`Allow`/`Deny`/`AllowStandardUserToSetSystemService`), `Allowed` (legacy bool),
  `StaticCode`, plus AppleEvents `AEReceiver*`. The code-requirement check uses the same
  `matchesCodeRequirementData:` → `SecRequirementCreateWithData` path as DB grants. **This
  confirms `tcc-preapprove profile` emits the correct keys** (`CodeRequirement` string +
  `Authorization` + `Allowed`).
- The evaluation returns an auth **value** (`2`=allow / `0`=deny / `1`=no-decision); the
  result is reported under the **Override Policy** reason (vs `Service Policy` for DB
  grants) and logged as `Override: eval: matched …; result: Auth:…`.
- Functional test: launch the app and confirm no prompt.

**`auth_reason = 5` ("Override Policy") is verified written in the request path.** In
`HandleAccessRequest`, the policy-decision branch stamps the result accumulators directly —
e.g. the unsigned-code policy _deny_: `auth_value = 0; auth_reason = 5` (logged
`"Policy Denies: %@ for %@ due to unsigned code policy."`). The literal `5` occurs exactly
once in that function - this branch — confirming `5` is the policy/override reason (not just
the enum label). Decompiler form: `local_2a8[3] = 0; local_3d0[3] = 5;` where `[3]` = the
`+0x18` result slot that `EvaluateAccessByIdentityOverrides` writes.

> Honest scope note: the override _evaluation_ (sources, keys, csreq match, value
> semantics) and the `auth_reason = 5` stamp are **verified** from `tccd` (`0x1000440c2`,
> `0x100045dfd`, `HandleAccessRequest`) - but `5` is proven specifically for a policy
> **deny** (unsigned code). For an MDM-profile **allow** the reason is **not** pinned to
> `5`: in `HandleAccessRequest` the reason accumulator (`local_3d0`, a `__block` byref)
> initialises to `0`/None and is written to `5` **only** in that deny branch; the allow
> branch (`auth_value=2`) does not stamp `5` in view. Resolving the allow reason would need
> the `__block`-forwarding chain + the override-decided branch (or `EvaluateAccessAuthorization`,
> which the decompiler times out on) - not done here, and **not** assumed. Treat profile
> _deny_ → reason 5 as verified; profile _allow_ reason as **unresolved**. (The `nanomdm`
> enrolment sequence above is likewise the standard documented flow, not run end-to-end.)
