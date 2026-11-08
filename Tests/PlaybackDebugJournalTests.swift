import XCTest
#if canImport(PhilharmonicCore)
@testable import PhilharmonicCore
#else
@testable import Philharmonic_SE
#endif

final class PlaybackDebugJournalTests: XCTestCase {
    private let origin = Date(timeIntervalSince1970: 1_800_000_000)

    func testRelaunchRetainsExactlyTheLastDayIncludingTheCutoff() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let log = PlaybackDebugJournal(directory: root.appendingPathComponent("log"), reportDirectory: root.appendingPathComponent("reports"))
        await log.record(event("too-old", at: origin), now: origin)
        let cutoff = origin.addingTimeInterval(600)
        await log.record(event("at-cutoff", at: cutoff), now: cutoff)
        let now = cutoff.addingTimeInterval(PlaybackDebugJournal.retention)
        await log.record(event("recent", at: now.addingTimeInterval(-5)), now: now)
        let reopened = PlaybackDebugJournal(directory: root.appendingPathComponent("log"), reportDirectory: root.appendingPathComponent("reports"))
        let report = try await reopened.makeShareReport(now: now)
        XCTAssertEqual(try names(in: report), ["at-cutoff", "recent"])
        let status = await reopened.status(now: now)
        XCTAssertEqual(status.eventCount, 2)
        XCTAssertNil(status.storageError)
    }

    func testShareIsStableAndClearRejectsAlreadyQueuedOldEvents() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("log")
        let log = PlaybackDebugJournal(directory: directory, reportDirectory: root.appendingPathComponent("reports"))
        await log.record(event("first", at: origin), now: origin)
        let shared = try await log.makeShareReport(now: origin)
        let original = try Data(contentsOf: shared)
        let unrelated = directory.appendingPathComponent("keep.txt")
        try Data("unrelated".utf8).write(to: unrelated)
        try await log.clear(now: origin.addingTimeInterval(2))
        await log.record(event("late-callback", at: origin.addingTimeInterval(1)), now: origin.addingTimeInterval(3))
        await log.record(event("fresh", at: origin.addingTimeInterval(3)), now: origin.addingTimeInterval(3))
        let current = try await log.makeShareReport(now: origin.addingTimeInterval(4))
        XCTAssertEqual(try names(in: current), ["fresh"])
        XCTAssertEqual(try Data(contentsOf: shared), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testStorageBoundsKeepTheNewestEventsWithoutUnboundedSegments() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let log = PlaybackDebugJournal(directory: root.appendingPathComponent("log"), reportDirectory: root.appendingPathComponent("reports"),
                                       maximumBytes: 16_384, maximumEvents: 3)
        for index in 0..<8 {
            let now = origin.addingTimeInterval(Double(index))
            await log.record(event("event-\(index)", at: now), now: now)
        }
        let now = origin.addingTimeInterval(8)
        let report = try await log.makeShareReport(now: now)
        XCTAssertEqual(try names(in: report), ["event-5", "event-6", "event-7"])
        let status = await log.status(now: now)
        XCTAssertLessThanOrEqual(status.bytes, 16_384)
        XCTAssertEqual(status.eventCount, 3)
        XCTAssertGreaterThan(status.discardedForBounds, 0)
    }

    func testPersistedDataAndSharedFocusedCaptureAreRedactedAndCorruptLinesAreSkipped() async throws {
        let root = folder(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("log")
        let log = PlaybackDebugJournal(directory: directory, reportDirectory: root.appendingPathComponent("reports"))
        await log.record(.init(date: origin, category: "test", name: "safe", details: [
            "token": "key-secret", "stream_url": "https://private.invalid/path?key=secret",
            "message": "failure for person@example.com at https://private.invalid/path?token=hidden-token"]), now: origin)
        let segment = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "jsonl" })
        let handle = try FileHandle(forWritingTo: segment)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("broken-json\n".utf8)); try handle.close()
        let reopened = PlaybackDebugJournal(directory: directory, reportDirectory: root.appendingPathComponent("reports"))
        let report = try await reopened.makeShareReport(now: origin.addingTimeInterval(1), focusedCapture: "snapshot\nBearer focused-secret",
                                                       captureDate: origin)
        let data = try String(contentsOf: report, encoding: .utf8)
        for secret in ["key-secret", "private.invalid", "hidden-token", "person@example.com", "focused-secret", "broken-json"] {
            XCTAssertFalse(data.contains(secret), secret)
        }
        XCTAssertTrue(data.contains("focused_capture"))
        XCTAssertEqual(try names(in: report), ["safe"])
        let status = await reopened.status(now: origin.addingTimeInterval(1))
        XCTAssertGreaterThan(status.invalidLines, 0)
    }

    private func event(_ name: String, at date: Date) -> PlaybackDebugJournal.Event {
        .init(date: date, category: "test", name: name)
    }
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("philharmonic-debug-test-" + UUID().uuidString, isDirectory: true)
    }
    private func names(in url: URL) throws -> [String] {
        try Data(contentsOf: url).split(separator: 0x0A).map { try JSONDecoder().decode(PlaybackDebugJournal.Event.self, from: Data($0)) }
            .filter { $0.category == "test" }.map(\.name)
    }
}
