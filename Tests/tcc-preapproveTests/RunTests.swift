import ArgumentParser
import Foundation
import XCTest

@testable import tcc_preapprove

/// Exercises command `run()` bodies and the Security/SQLite helpers. `/bin/ls` is an
/// Apple-signed platform binary on every macOS runner, so its designated requirement can be
/// read for real. The actual SIP-protected `TCC.db` writes are not reachable in CI, so those
/// branches (non-dry-run SQLite bind/step) stay uncovered by design.
final class RunTests: XCTestCase {
    // MARK: Security helpers

    func testDesignatedRequirementForSignedBinary() throws {
        XCTAssertFalse(try designatedRequirementData(forPath: "/bin/ls").isEmpty)
        XCTAssertFalse(try designatedRequirementString(forPath: "/bin/ls").isEmpty)
    }

    func testDesignatedRequirementForMissingPathThrows() {
        XCTAssertThrowsError(try designatedRequirementData(forPath: "/nonexistent/binary"))
        XCTAssertThrowsError(try designatedRequirementString(forPath: "/nonexistent/binary"))
    }

    // MARK: SQLite / stderr helpers

    func testOpenDBFailureReturnsNil() {
        XCTAssertNil(openDB("/nonexistent/dir/does-not-exist.db", readonly: true))
    }

    func testStderrLine() {
        stderrLine("tcc-preapprove tests: stderrLine exercised")
    }

    // MARK: grant

    func testGrantDryRunWithSignedBinary() {
        XCTAssertNoThrow(try Grant.parse(["--binary", "/bin/ls", "-p", "downloads,fda", "--dry-run"]).run())
    }

    func testGrantNeedsPathForCsreq() {
        XCTAssertThrowsError(try Grant.parse(["--client", "com.example.app", "-p", "downloads"]).run())
    }

    func testGrantNeedsPermissions() {
        XCTAssertThrowsError(try Grant.parse(["--binary", "/bin/ls"]).run())
    }

    // MARK: revoke

    func testRevokeDryRunSpecificServices() {
        XCTAssertNoThrow(try Revoke.parse(["--client", "com.example.app", "-p", "downloads,fda", "--dry-run"]).run())
    }

    func testRevokeDryRunAll() {
        XCTAssertNoThrow(try Revoke.parse(["--client", "com.example.app", "--all", "--dry-run"]).run())
    }

    func testRevokeDryRunForcedSystemDB() {
        XCTAssertNoThrow(try Revoke.parse(["--client", "com.example.app", "--all", "--db", "system", "--dry-run"]).run())
    }

    func testRevokeNeedsPermissionsOrAll() {
        XCTAssertThrowsError(try Revoke.parse(["--client", "com.example.app"]).run())
    }

    // MARK: list

    func testListRunsGracefullyWithoutMatches() {
        XCTAssertNoThrow(try List.parse(["--client", "com.example.nonexistent.client"]).run())
    }

    // MARK: profile

    func testProfileToStdout() {
        XCTAssertNoThrow(try Profile.parse(["--binary", "/bin/ls", "-p", "downloads"]).run())
    }

    func testProfileToFile() throws {
        let out = NSTemporaryDirectory() + "tccx-test-\(UUID().uuidString).mobileconfig"
        defer { try? FileManager.default.removeItem(atPath: out) }
        XCTAssertNoThrow(try Profile.parse(["--binary", "/bin/ls", "-p", "downloads,fda", "-o", out]).run())
        XCTAssertTrue(FileManager.default.fileExists(atPath: out))
    }

    func testProfileNeedsPath() {
        XCTAssertThrowsError(try Profile.parse(["--client", "com.example.app", "-p", "downloads"]).run())
    }

    func testProfileNeedsPermissions() {
        XCTAssertThrowsError(try Profile.parse(["--binary", "/bin/ls"]).run())
    }
}
