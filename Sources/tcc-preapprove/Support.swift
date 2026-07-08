import Foundation
import Security
import SQLite3

// SQLite tells the binder to copy the bound buffer immediately.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Tool-level error whose text ArgumentParser prints verbatim.
struct ToolError: Error, CustomStringConvertible {
    let message: String
    init(_ m: String) { message = m }
    var description: String { message }
}

// MARK: - Service aliases -> kTCCService constants + which DB they live in.

enum DBKind: CaseIterable { case user, system }

struct ServiceInfo { let service: String; let db: DBKind }

let serviceAliases: [String: ServiceInfo] = [
    "downloads":     .init(service: "kTCCServiceSystemPolicyDownloadsFolder",  db: .user),
    "documents":     .init(service: "kTCCServiceSystemPolicyDocumentsFolder",  db: .user),
    "desktop":       .init(service: "kTCCServiceSystemPolicyDesktopFolder",    db: .user),
    "fda":           .init(service: "kTCCServiceSystemPolicyAllFiles",         db: .system),
    "fulldisk":      .init(service: "kTCCServiceSystemPolicyAllFiles",         db: .system),
    "accessibility": .init(service: "kTCCServiceAccessibility",                db: .system),
    "removable":     .init(service: "kTCCServiceSystemPolicyRemovableVolumes", db: .user),
    "network":       .init(service: "kTCCServiceSystemPolicyNetworkVolumes",   db: .user),
    "appbundles":    .init(service: "kTCCServiceSystemPolicyAppBundles",       db: .user),
    "developerfiles":.init(service: "kTCCServiceSystemPolicyDeveloperFiles",   db: .user),
]

let systemServices: Set<String> = [
    "kTCCServiceSystemPolicyAllFiles", "kTCCServiceAccessibility",
    "kTCCServiceEndpointSecurityClient", "kTCCServiceSystemPolicySysAdminFiles",
]

func resolveService(_ token: String) -> ServiceInfo {
    if let info = serviceAliases[token.lowercased()] { return info }
    return ServiceInfo(service: token, db: systemServices.contains(token) ? .system : .user)
}

func parseServices(_ csv: String) -> [ServiceInfo] {
    csv.split(separator: ",").map { resolveService($0.trimmingCharacters(in: .whitespaces)) }
}

/// Test seam: override where the TCC databases live so tests can point at a temporary SQLite
/// file instead of the real, SIP-protected paths. Production code never mutates this.
var dbPathResolver: (DBKind) -> String = defaultDBPath

func defaultDBPath(for kind: DBKind) -> String {
    switch kind {
    case .user:   return NSString(string: "~/Library/Application Support/com.apple.TCC/TCC.db").expandingTildeInPath
    case .system: return "/Library/Application Support/com.apple.TCC/TCC.db"
    }
}

func dbPath(for kind: DBKind) -> String { dbPathResolver(kind) }

/// PPPC service keys drop the kTCCService prefix (e.g. SystemPolicyAllFiles).
func pppcKey(_ service: String) -> String {
    service.hasPrefix("kTCCService") ? String(service.dropFirst("kTCCService".count)) : service
}

// MARK: - Pretty-printers (mirror GetAuthReasonString @ 0x100001e80)

func authValueString(_ v: Int32) -> String {
    switch v { case 0: return "denied"; case 2: return "allowed"; case 3: return "limited"; default: return "unknown(\(v))" }
}
func authReasonString(_ v: Int32) -> String {
    switch v {
    case 0: return "None"; case 1: return "Recorded"; case 2: return "Service Default"
    case 3: return "Service Policy"; case 4: return "Compatibility Policy"
    case 5: return "Override Policy"; case 6: return "Set"
    case 1000: return "Error"; case 1001: return "Service Override"
    case 1002: return "Missing Usage String"; case 1003: return "Prompt Timeout"
    case 1004: return "Preflight Unknown"; case 2000: return "Entitled"
    default: return "Reason(\(v))"
    }
}

func pad(_ s: String, _ w: Int) -> String {
    s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
}

func colText(_ stmt: OpaquePointer?, _ i: Int32) -> String {
    guard let c = sqlite3_column_text(stmt, i) else { return "" }
    return String(cString: c)
}

// MARK: - Code-signing requirement extraction

func designatedRequirementData(forPath path: String) throws -> Data {
    let url = URL(fileURLWithPath: path) as CFURL
    var staticCode: SecStaticCode?
    var st = SecStaticCodeCreateWithPath(url, SecCSFlags(rawValue: 0), &staticCode)
    guard st == errSecSuccess, let code = staticCode else {
        throw ToolError("SecStaticCodeCreateWithPath failed (OSStatus \(st)) — is the target code-signed?")
    }
    var req: SecRequirement?
    st = SecCodeCopyDesignatedRequirement(code, SecCSFlags(rawValue: 0), &req)
    guard st == errSecSuccess, let r = req else { throw ToolError("SecCodeCopyDesignatedRequirement failed (\(st)).") }
    var data: CFData?
    st = SecRequirementCopyData(r, SecCSFlags(rawValue: 0), &data)
    guard st == errSecSuccess, let blob = data else { throw ToolError("SecRequirementCopyData failed (\(st)).") }
    return blob as Data
}

func designatedRequirementString(forPath path: String) throws -> String {
    let url = URL(fileURLWithPath: path) as CFURL
    var staticCode: SecStaticCode?
    var st = SecStaticCodeCreateWithPath(url, SecCSFlags(rawValue: 0), &staticCode)
    guard st == errSecSuccess, let code = staticCode else {
        throw ToolError("SecStaticCodeCreateWithPath failed (OSStatus \(st)) — is the target code-signed?")
    }
    var req: SecRequirement?
    st = SecCodeCopyDesignatedRequirement(code, SecCSFlags(rawValue: 0), &req)
    guard st == errSecSuccess, let r = req else { throw ToolError("SecCodeCopyDesignatedRequirement failed (\(st)).") }
    var str: CFString?
    st = SecRequirementCopyString(r, SecCSFlags(rawValue: 0), &str)
    guard st == errSecSuccess, let s = str else { throw ToolError("SecRequirementCopyString failed (\(st)).") }
    return s as String
}

// MARK: - SQLite open (warns + returns nil rather than aborting, so `list` can continue)

func openDB(_ path: String, readonly: Bool) -> OpaquePointer? {
    var db: OpaquePointer?
    let flags = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
    if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
        let msg = db != nil ? String(cString: sqlite3_errmsg(db)) : "cannot open"
        FileHandle.standardError.write(Data("warning: \(path): \(msg) (need FDA / SIP-off; root for system DB)\n".utf8))
        sqlite3_close(db)
        return nil
    }
    return db
}

func stderrLine(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
