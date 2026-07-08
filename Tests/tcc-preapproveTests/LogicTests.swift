import ArgumentParser
import XCTest

@testable import tcc_preapprove

final class LogicTests: XCTestCase {
    func testResolveServiceAlias() {
        let d = resolveService("downloads")
        XCTAssertEqual(d.service, "kTCCServiceSystemPolicyDownloadsFolder")
        XCTAssertEqual(d.db, .user)
        // Aliases are case-insensitive.
        let fda = resolveService("FDA")
        XCTAssertEqual(fda.service, "kTCCServiceSystemPolicyAllFiles")
        XCTAssertEqual(fda.db, .system)
    }

    func testResolveServiceRawNames() {
        XCTAssertEqual(resolveService("kTCCServiceAccessibility").db, .system)
        XCTAssertEqual(resolveService("kTCCServiceSystemPolicyAllFiles").db, .system)
        // Unknown raw names default to the user DB.
        let unknown = resolveService("kTCCServiceUnknownXYZ")
        XCTAssertEqual(unknown.service, "kTCCServiceUnknownXYZ")
        XCTAssertEqual(unknown.db, .user)
    }

    func testParseServices() {
        let s = parseServices("downloads, fda ,accessibility")
        XCTAssertEqual(s.map { $0.service }, [
            "kTCCServiceSystemPolicyDownloadsFolder",
            "kTCCServiceSystemPolicyAllFiles",
            "kTCCServiceAccessibility",
        ])
        XCTAssertTrue(parseServices("").isEmpty)
    }

    func testPppcKey() {
        XCTAssertEqual(pppcKey("kTCCServiceSystemPolicyAllFiles"), "SystemPolicyAllFiles")
        XCTAssertEqual(pppcKey("SystemPolicyAllFiles"), "SystemPolicyAllFiles")
    }

    func testAuthValueString() {
        XCTAssertEqual(authValueString(0), "denied")
        XCTAssertEqual(authValueString(2), "allowed")
        XCTAssertEqual(authValueString(3), "limited")
        XCTAssertEqual(authValueString(9), "unknown(9)")
    }

    func testAuthReasonString() {
        XCTAssertEqual(authReasonString(0), "None")
        XCTAssertEqual(authReasonString(3), "Service Policy")
        XCTAssertEqual(authReasonString(6), "Set")
        XCTAssertEqual(authReasonString(2000), "Entitled")
        XCTAssertEqual(authReasonString(42), "Reason(42)")
    }

    func testPad() {
        XCTAssertEqual(pad("ab", 5), "ab   ")
        XCTAssertEqual(pad("abcdef", 3), "abc")
        XCTAssertEqual(pad("abc", 3), "abc")
    }

    func testDBPath() {
        XCTAssertEqual(dbPath(for: .system), "/Library/Application Support/com.apple.TCC/TCC.db")
        let user = dbPath(for: .user)
        XCTAssertTrue(user.hasSuffix("Library/Application Support/com.apple.TCC/TCC.db"))
        XCTAssertFalse(user.hasPrefix("~"))
    }

    func testToolError() {
        XCTAssertEqual(ToolError("boom").description, "boom")
    }

    func testDBKindCases() {
        XCTAssertEqual(DBKind.allCases.count, 2)
    }

    func testTargetDeriveClient() throws {
        let (client, type) = try TargetOptions.parse(["--client", "com.example.app", "--client-type", "0"]).derive()
        XCTAssertEqual(client, "com.example.app")
        XCTAssertEqual(type, 0)
    }

    func testTargetDeriveClientDefaultType() throws {
        // With only --client (no --app), the default client_type is 1 (path).
        let (_, type) = try TargetOptions.parse(["--client", "com.example.app"]).derive()
        XCTAssertEqual(type, 1)
    }

    func testTargetDeriveMissing() throws {
        XCTAssertThrowsError(try TargetOptions.parse([]).derive())
    }

    func testServiceOptionsForcedKind() throws {
        XCTAssertEqual(try ServiceOptions.parse(["--db", "user"]).forcedKind(), .user)
        XCTAssertEqual(try ServiceOptions.parse(["--db", "system"]).forcedKind(), .system)
        XCTAssertNil(try ServiceOptions.parse(["--db", "both"]).forcedKind())
        XCTAssertNil(try ServiceOptions.parse([]).forcedKind())
        XCTAssertThrowsError(try ServiceOptions.parse(["--db", "bogus"]).forcedKind())
    }

    func testServiceOptionsServices() throws {
        XCTAssertEqual(try ServiceOptions.parse(["-p", "downloads,fda"]).services().count, 2)
        XCTAssertTrue(try ServiceOptions.parse([]).services().isEmpty)
    }

    func testCommandParsing() {
        XCTAssertNoThrow(try TCCPreapprove.parseAsRoot(["grant", "--client", "com.x", "-p", "downloads", "--dry-run"]))
        XCTAssertNoThrow(try TCCPreapprove.parseAsRoot(["revoke", "--client", "com.x", "--all"]))
        XCTAssertNoThrow(try TCCPreapprove.parseAsRoot(["list"]))
    }
}
