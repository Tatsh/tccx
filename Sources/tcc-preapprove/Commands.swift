import ArgumentParser
import Foundation
import SQLite3

// MARK: - Shared option groups

struct TargetOptions: ParsableArguments {
    @Option(name: [.customShort("a"), .long], help: "App bundle (client_type=0, CFBundleIdentifier).")
    var app: String?
    @Option(name: [.customShort("b"), .long], help: "Plain executable (client_type=1, absolute path).")
    var binary: String?
    @Option(help: "Use this client string directly (no signing needed).")
    var client: String?
    @Option(help: "Override client_type (0=bundleID, 1=path).")
    var clientType: Int?

    var path: String? { app ?? binary }

    func derive() throws -> (client: String, type: Int32) {
        if let c = client { return (c, Int32(clientType ?? (app != nil ? 0 : 1))) }
        guard let p = path else { throw ToolError("Need --app/--binary or --client.") }
        guard FileManager.default.fileExists(atPath: p) else { throw ToolError("Not found: \(p).") }
        if app != nil {
            guard let b = Bundle(path: p), let bid = b.bundleIdentifier else {
                throw ToolError("Could not read CFBundleIdentifier from \(p).")
            }
            return (bid, Int32(clientType ?? 0))
        }
        return ((p as NSString).standardizingPath, Int32(clientType ?? 1))
    }
}

struct ServiceOptions: ParsableArguments {
    @Option(name: [.customShort("p"), .long],
            help: "Comma list of aliases or raw kTCCService… names (downloads,documents,fda,…).")
    var permissions: String?
    @Flag(help: "Target all services for the client (revoke only; ignored elsewhere).")
    var all = false
    @Option(help: "DB routing override: user|system|both.")
    var db: String?

    func services() -> [ServiceInfo] { permissions.map(parseServices) ?? [] }

    func forcedKind() throws -> DBKind? {
        switch db?.lowercased() {
        case "user": return .user
        case "system": return .system
        case "both", nil: return nil
        default: throw ToolError("The --db option must be user, system, or both.")
        }
    }
}

// MARK: - Root

@main
struct TCCPreapprove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tcc-preapprove",
        abstract: "Inspect / pre-approve / revoke TCC grants for a binary or app (macOS).",
        discussion: "Built from tccd (10.15.6) RE notes (docs/tcc-internals.md). "
            + "Grant/revoke/list need FDA or SIP-off (root for the system DB); "
            + "profile needs neither.",
        version: "0.0.4",
        subcommands: [Grant.self, Revoke.self, List.self, Profile.self],
        defaultSubcommand: Grant.self
    )
}

// MARK: - grant

struct Grant: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write an allow row (csreq blob).")
    @OptionGroup var target: TargetOptions
    @OptionGroup var svc: ServiceOptions
    @Option(help: "Default 2 (allowed). 0 = denied.") var authValue: Int = 2
    @Option(help: "Default 3 (Service Policy — what the user-Allow path writes).") var authReason: Int = 3
    @Flag(help: "Print SQL; do not write.") var dryRun = false

    func run() throws {
        let (client, clientType) = try target.derive()
        guard let path = target.path else { throw ToolError("Grant needs --app/--binary to compute csreq.") }
        let services = svc.services()
        guard !services.isEmpty else { throw ToolError("Grant needs --permissions.") }
        let csreq = try designatedRequirementData(forPath: path)
        let av = Int32(authValue), ar = Int32(authReason)

        print("client : \(client) (client_type=\(clientType))")
        print("csreq  : \(csreq.count) bytes from \(path)")
        print("auth   : value=\(av) (\(authValueString(av))) reason=\(ar) (\(authReasonString(ar))) version=1")
        if dryRun { print("mode   : DRY RUN") }

        let sql = """
        INSERT OR REPLACE INTO access
         (service, client, client_type, auth_value, auth_reason, auth_version,
          csreq, policy_id, indirect_object_identifier_type,
          indirect_object_identifier, indirect_object_code_identity, flags)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
        """
        for info in services {
            let file = dbPath(for: try svc.forcedKind() ?? info.db)
            if dryRun {
                let hex = csreq.map { String(format: "%02x", Int($0)) }.joined()
                print("-- \(info.service) -> \(file)")
                print("INSERT OR REPLACE INTO access (...) VALUES ('\(info.service)','\(client)',\(clientType),\(av),\(ar),1,X'\(hex)',NULL,0,'UNUSED',NULL,0);")
                continue
            }
            guard let db = openDB(file, readonly: false) else { continue }
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw ToolError("Prepare failed: \(String(cString: sqlite3_errmsg(db))).")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, info.service, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, client, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, clientType)
            sqlite3_bind_int(stmt, 4, av)
            sqlite3_bind_int(stmt, 5, ar)
            sqlite3_bind_int(stmt, 6, 1)
            csreq.withUnsafeBytes { raw in
                _ = sqlite3_bind_blob(stmt, 7, raw.baseAddress, Int32(csreq.count), SQLITE_TRANSIENT)
            }
            sqlite3_bind_null(stmt, 8)
            sqlite3_bind_int(stmt, 9, 0)
            sqlite3_bind_text(stmt, 10, "UNUSED", -1, SQLITE_TRANSIENT)
            sqlite3_bind_null(stmt, 11)
            sqlite3_bind_int(stmt, 12, 0)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw ToolError("Insert failed for \(info.service): \(String(cString: sqlite3_errmsg(db))).")
            }
            print("  ✓ granted \(info.service) -> \(file)")
        }
        if !dryRun { reloadHint() }
    }
}

// MARK: - revoke

struct Revoke: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete access row(s) for a client.")
    @OptionGroup var target: TargetOptions
    @OptionGroup var svc: ServiceOptions
    @Flag(help: "Print SQL; do not delete.") var dryRun = false

    func run() throws {
        let (client, clientType) = try target.derive()
        let services = svc.services()
        guard svc.all || !services.isEmpty else { throw ToolError("Revoke needs --permissions or --all.") }

        var targets: [(file: String, service: String?)] = []
        if svc.all {
            let kinds = try svc.forcedKind().map { [$0] } ?? DBKind.allCases
            targets = kinds.map { (dbPath(for: $0), nil) }
        } else {
            for info in services { targets.append((dbPath(for: try svc.forcedKind() ?? info.db), info.service)) }
        }

        print("client : \(client) (client_type=\(clientType))")
        if dryRun { print("mode   : DRY RUN") }

        for (file, service) in targets {
            let sql = service == nil
                ? "DELETE FROM access WHERE client=? AND client_type=?;"
                : "DELETE FROM access WHERE service=? AND client=? AND client_type=?;"
            if dryRun {
                print("-- \(file)")
                if let s = service { print("DELETE FROM access WHERE service='\(s)' AND client='\(client)' AND client_type=\(clientType);") }
                else { print("DELETE FROM access WHERE client='\(client)' AND client_type=\(clientType);") }
                continue
            }
            guard let db = openDB(file, readonly: false) else { continue }
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw ToolError("Prepare failed: \(String(cString: sqlite3_errmsg(db))).")
            }
            defer { sqlite3_finalize(stmt) }
            var idx: Int32 = 1
            if let s = service { sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT); idx += 1 }
            sqlite3_bind_text(stmt, idx, client, -1, SQLITE_TRANSIENT); idx += 1
            sqlite3_bind_int(stmt, idx, clientType)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw ToolError("Delete failed: \(String(cString: sqlite3_errmsg(db))).")
            }
            print("  ✓ revoked \(sqlite3_changes(db)) row(s) \(service ?? "(all services)") <- \(file)")
        }
        if !dryRun { reloadHint() }
    }
}

// MARK: - list

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print existing access rows.")
    @OptionGroup var target: TargetOptions
    @OptionGroup var svc: ServiceOptions

    func run() throws {
        let client = (try? target.derive().client) ?? target.client
        let serviceNames = Set(svc.services().map { $0.service })
        let kinds = try svc.forcedKind().map { [$0] } ?? DBKind.allCases

        let header = pad("service", 44) + " " + pad("client", 34) + " " + pad("ct", 2)
                   + " " + pad("auth", 8) + " " + pad("reason", 18) + " " + pad("csreq", 6)
        var printedHeader = false

        for kind in kinds {
            let file = dbPath(for: kind)
            guard let db = openDB(file, readonly: true) else { continue }
            defer { sqlite3_close(db) }
            var sql = "SELECT service, client, client_type, auth_value, auth_reason, length(csreq) FROM access"
            var conds: [String] = []
            if client != nil { conds.append("client=?") }
            if !serviceNames.isEmpty { conds.append("service IN (" + serviceNames.map { _ in "?" }.joined(separator: ",") + ")") }
            if !conds.isEmpty { sql += " WHERE " + conds.joined(separator: " AND ") }
            sql += " ORDER BY service, client;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            var bindIdx: Int32 = 1
            if let c = client { sqlite3_bind_text(stmt, bindIdx, c, -1, SQLITE_TRANSIENT); bindIdx += 1 }
            for s in serviceNames { sqlite3_bind_text(stmt, bindIdx, s, -1, SQLITE_TRANSIENT); bindIdx += 1 }

            if !printedHeader { print(header); printedHeader = true }
            print("# \(kind == .user ? "USER" : "SYSTEM") DB: \(file)")
            var rows = 0
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows += 1
                let service = colText(stmt, 0)
                let cli = colText(stmt, 1)
                let ct = sqlite3_column_int(stmt, 2)
                let av = sqlite3_column_int(stmt, 3)
                let ar = sqlite3_column_int(stmt, 4)
                let csreqLen = sqlite3_column_int(stmt, 5)
                print(pad(service, 44) + " " + pad(cli, 34) + " " + pad("\(ct)", 2)
                    + " " + pad(authValueString(av), 8) + " " + pad(authReasonString(ar), 18)
                    + " " + pad("\(csreqLen)", 6))
            }
            if rows == 0 { print("  (no matching rows)") }
        }
        if !printedHeader { print("(no databases readable — need FDA / SIP-off / root)") }
    }
}

// MARK: - profile (PPPC .mobileconfig)

struct Profile: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Emit a PPPC .mobileconfig (no SIP/FDA needed; for MDM distribution).")
    @OptionGroup var target: TargetOptions
    @OptionGroup var svc: ServiceOptions
    @Option(name: [.customShort("o"), .long], help: "Write .mobileconfig here (default: stdout).")
    var output: String?

    func run() throws {
        let (client, clientType) = try target.derive()
        guard let path = target.path else { throw ToolError("Profile needs --app/--binary to read the designated requirement.") }
        let services = svc.services()
        guard !services.isEmpty else { throw ToolError("Profile needs --permissions.") }
        let codeReq = try designatedRequirementString(forPath: path)
        let idType = clientType == 0 ? "bundleID" : "path"

        var serviceDict: [String: [[String: Any]]] = [:]
        for info in services {
            let rule: [String: Any] = [
                "Identifier": client,
                "IdentifierType": idType,
                "CodeRequirement": codeReq,
                "Allowed": true,           // 10.14–10.15
                "Authorization": "Allow",  // 11+
                "StaticCode": false,
                "Comment": "Pre-approved by tcc-preapprove",
            ]
            serviceDict[pppcKey(info.service), default: []].append(rule)
        }

        let topId = "com.tcc-preapprove." + client.replacingOccurrences(of: "/", with: "_")
        let payload: [String: Any] = [
            "PayloadType": "com.apple.TCC.configuration-profile-policy",
            "PayloadIdentifier": topId + ".tcc",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
            "PayloadEnabled": true,
            "Services": serviceDict,
        ]
        let config: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadDisplayName": "TCC Pre-Approval — \(client)",
            "PayloadDescription": "Grants \(services.map { pppcKey($0.service) }.joined(separator: ", ")) to \(client).",
            "PayloadIdentifier": topId,
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1,
            "PayloadScope": "System",
            "PayloadContent": [payload],
        ]

        let data: Data
        do { data = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0) }
        catch { throw ToolError("Could not serialize profile: \(error).") }

        if let out = output {
            do { try data.write(to: URL(fileURLWithPath: out)) }
            catch { throw ToolError("Could not write \(out): \(error).") }
            stderrLine("Wrote \(data.count) bytes -> \(out).")
            stderrLine("Sign for MDM: security cms -S -N \"<cert>\" -i \(out) -o signed.mobileconfig")
            stderrLine("Note: PPPC only applies under user-approved MDM / supervision; SystemPolicy*Folder is not honored — prefer FDA.")
        } else {
            print(String(decoding: data, as: UTF8.self))
        }
    }
}

func reloadHint() {
    print("\nRestart tccd so it reloads:")
    print("  killall tccd          # user services")
    print("  sudo killall tccd     # system services")
}
