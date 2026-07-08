import ArgumentParser
import Foundation
import SQLite3
import XCTest

@testable import tcc_preapprove

/// Drives the real SQLite read/write code against a temporary database by overriding
/// `dbPathResolver`. Nothing here touches the real, SIP-protected `TCC.db`.
final class DBTests: XCTestCase {
    private var tempPath = ""

    override func tearDown() {
        dbPathResolver = defaultDBPath
        if !tempPath.isEmpty {
            try? FileManager.default.removeItem(atPath: tempPath)
            tempPath = ""
        }
        super.tearDown()
    }

    private static let accessSchema = """
    CREATE TABLE access (
      service TEXT NOT NULL, client TEXT NOT NULL, client_type INTEGER NOT NULL,
      auth_value INTEGER NOT NULL, auth_reason INTEGER NOT NULL, auth_version INTEGER NOT NULL,
      csreq BLOB, policy_id INTEGER, indirect_object_identifier_type INTEGER,
      indirect_object_identifier TEXT NOT NULL DEFAULT 'UNUSED', indirect_object_code_identity BLOB,
      flags INTEGER, last_modified INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (service, client, client_type, indirect_object_identifier));
    """

    /// Create a temp DB (optionally seeded with `schema`), route the tool at it, and remember
    /// the path for cleanup.
    @discardableResult
    private func useTempDB(schema: String?) -> String {
        let path = NSTemporaryDirectory() + "tccx-\(UUID().uuidString).db"
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        if let schema {
            XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)
        }
        sqlite3_close(db)
        tempPath = path
        dbPathResolver = { _ in path }
        return path
    }

    private func exec(_ sql: String) {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempPath, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
    }

    // MARK: happy path: grant -> list -> revoke against a real (temp) access table

    func testGrantListRevokeRoundTrip() throws {
        useTempDB(schema: Self.accessSchema)
        XCTAssertNoThrow(try Grant.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
        // list prints the freshly-written row (exercises colText + column reads).
        XCTAssertNoThrow(try List.parse(["--binary", "/bin/ls", "--db", "user"]).run())
        // list with a non-matching client hits the "(no matching rows)" branch.
        XCTAssertNoThrow(try List.parse(["--client", "com.absent.client", "--db", "user"]).run())
        XCTAssertNoThrow(try Revoke.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
        XCTAssertNoThrow(try Revoke.parse(["--client", "com.x", "--all", "--db", "user"]).run())
    }

    // MARK: prepare failures (no table)

    func testGrantPrepareFailsWithoutTable() {
        useTempDB(schema: nil)
        XCTAssertThrowsError(try Grant.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
    }

    func testRevokePrepareFailsWithoutTable() {
        useTempDB(schema: nil)
        XCTAssertThrowsError(try Revoke.parse(["--client", "com.x", "-p", "downloads", "--db", "user"]).run())
    }

    func testListPrepareFailContinues() {
        useTempDB(schema: nil)
        XCTAssertNoThrow(try List.parse(["--client", "com.x", "--db", "user"]).run())
    }

    // MARK: step failures

    func testGrantStepFailsOnConstraint() {
        // Add a NOT NULL column the tool's INSERT does not populate -> step-time constraint error.
        useTempDB(schema: Self.accessSchema.replacingOccurrences(
            of: "flags INTEGER,",
            with: "flags INTEGER, extra_required INTEGER NOT NULL,"))
        XCTAssertThrowsError(try Grant.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
    }

    func testRevokeStepFailsWithTrigger() {
        useTempDB(schema: Self.accessSchema
            + "\nCREATE TRIGGER block_del BEFORE DELETE ON access BEGIN SELECT RAISE(ABORT, 'blocked'); END;")
        exec("INSERT INTO access (service,client,client_type,auth_value,auth_reason,auth_version) "
            + "VALUES ('kTCCServiceSystemPolicyDownloadsFolder','/bin/ls',1,2,3,1);")
        XCTAssertThrowsError(try Revoke.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
    }

    // MARK: openDB failure -> skip (continue) rather than throw

    func testGrantOpenDBFailContinues() {
        dbPathResolver = { _ in "/nonexistent/dir/x.db" }
        XCTAssertNoThrow(try Grant.parse(["--binary", "/bin/ls", "-p", "downloads", "--db", "user"]).run())
    }

    func testRevokeOpenDBFailContinues() {
        dbPathResolver = { _ in "/nonexistent/dir/x.db" }
        XCTAssertNoThrow(try Revoke.parse(["--client", "com.x", "--all", "--db", "user"]).run())
    }

    // MARK: colText both branches

    func testColTextNullAndValue() {
        useTempDB(schema: Self.accessSchema)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(tempPath, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT NULL, 'hello';", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(colText(stmt, 0), "")
        XCTAssertEqual(colText(stmt, 1), "hello")
    }

    // MARK: TargetOptions.derive app-bundle branches

    func testTargetDeriveAppBundle() throws {
        let (client, type) = try TargetOptions
            .parse(["--app", "/System/Applications/Utilities/Terminal.app"]).derive()
        XCTAssertEqual(client, "com.apple.Terminal")
        XCTAssertEqual(type, 0)
    }

    func testTargetDeriveAppWithoutBundleIDThrows() {
        // /usr exists but is not an app bundle -> no CFBundleIdentifier.
        XCTAssertThrowsError(try TargetOptions.parse(["--app", "/usr"]).derive())
    }
}
